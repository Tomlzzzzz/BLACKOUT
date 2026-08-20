--!strict
-- Tests du systeme de menace.
--
-- Portent sur Shared.Threat et Shared.Utils.Signal, purs. Le temps etant un
-- argument et non une horloge, une partie de vingt minutes se simule en
-- quelques appels — et la decroissance apres periode calme devient testable
-- sans attendre vingt secondes de silence reel.
--
--   require(game.ServerStorage.Tests.ThreatTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Threat = require(Shared.Threat)
local Config = require(Shared.Config)
local Signal = require(Shared.Utils.Signal)

local ThreatTests = {}

type Report = {
	passed: number,
	failed: number,
	lines: { string },
}

local function check(report: Report, name: string, condition: boolean, detail: string?)
	if condition then
		report.passed += 1
		table.insert(report.lines, `  PASS  {name}`)
	else
		report.failed += 1
		table.insert(report.lines, `  FAIL  {name}` .. (if detail then ` -> {detail}` else ""))
	end
end

-- ---------------------------------------------------------- Paliers -----

local function testBands(report: Report)
	table.insert(report.lines, "paliers")

	local cases = {
		{ value = 0, band = "SAFE" },
		{ value = 20, band = "SAFE" },
		{ value = 20.9, band = "SAFE" },
		{ value = 21, band = "ALERT" },
		{ value = 40, band = "ALERT" },
		{ value = 41, band = "DANGER" },
		{ value = 60, band = "DANGER" },
		{ value = 61, band = "SEVERE" },
		{ value = 80, band = "SEVERE" },
		-- Bornes alignees sur la specification du HUD v2 : SEVERE couvre
		-- desormais 61-85, CRITICAL commence a 86.
		{ value = 85, band = "SEVERE" },
		{ value = 86, band = "CRITICAL" },
		{ value = 99, band = "CRITICAL" },
		{ value = 99.9, band = "CRITICAL" },
		{ value = 100, band = "HUNT" },
	}

	for _, case in cases do
		local got = Threat.bandFor(case.value)
		check(report, `{case.value} -> {case.band}`, got == case.band, got)
	end

    -- Les six paliers de la spec existent bien dans la config.
	local names: { [string]: boolean } = {}
	for _, band in Config.Threat.bands do
		names[band.name] = true
	end
	for _, expected in { "SAFE", "ALERT", "DANGER", "SEVERE", "CRITICAL", "HUNT" } do
		check(report, `palier {expected} configure`, names[expected] == true)
	end
end

-- ------------------------------------------------------- Bornes et API --

local function testBounds(report: Report)
	table.insert(report.lines, "bornes et mutations")

	local meter = Threat.new(0, 0)
	check(report, "demarre a 0", meter.value == 0)

	Threat.add(meter, 30, "test", 0)
	check(report, "ajout simple", meter.value == 30, tostring(meter.value))

	Threat.add(meter, -10, "test", 0)
	check(report, "retrait simple", meter.value == 20, tostring(meter.value))

	Threat.add(meter, 500, "test", 0)
	check(report, "plafonne a 100", meter.value == 100, tostring(meter.value))

	Threat.add(meter, -500, "test", 0)
	check(report, "plancher a 0", meter.value == 0, tostring(meter.value))

	local set = Threat.set(meter, 55, "test")
	check(report, "set exact", meter.value == 55, tostring(meter.value))
	check(report, "set rapporte l'ancienne valeur", set.previous == 0, tostring(set.previous))
	check(report, "set rapporte le nouveau palier", set.band == "DANGER", set.band)
	check(report, "set rapporte l'ancien palier", set.previousBand == "SAFE", set.previousBand)

	Threat.set(meter, 250, "test")
	check(report, "set plafonne aussi", meter.value == 100, tostring(meter.value))

	-- Entrees aberrantes : ignorees, jamais propagees.
	Threat.set(meter, 50, "test")
	Threat.add(meter, 0 / 0, "test", 0)
	check(report, "NaN ignore", meter.value == 50, tostring(meter.value))
	Threat.add(meter, math.huge, "test", 0)
	check(report, "infini ignore", meter.value == 50, tostring(meter.value))
	Threat.set(meter, 0 / 0, "test")
	check(report, "set NaN ignore", meter.value == 50, tostring(meter.value))
end

-- --------------------------------------------- Temps et decroissance ----

local function testTimeAndDecay(report: Report)
	table.insert(report.lines, "temps et decroissance")

	local passive = Config.Threat.passivePerSecond
	local decay = Config.Threat.decayPerSecond
	local quietDelay = Config.Threat.quietDelay

	-- Juste apres un evenement : gain passif seul, pas de decroissance.
	local meter = Threat.new(50, 0)
	Threat.add(meter, 0, "amorce", 100)
	local before = meter.value
	Threat.step(meter, 10, 105)
	check(
		report,
		"gain passif pendant l'activite",
		math.abs(meter.value - (before + passive * 10)) < 0.001,
		tostring(meter.value)
	)

	-- Passe le delai de calme : le bilan devient negatif.
	local quiet = Threat.new(50, 0)
	quiet.lastEventAt = 0
	local change = Threat.step(quiet, 10, quietDelay + 50)
	local expected = 50 + (passive - decay) * 10
	check(report, "decroissance au calme", math.abs(quiet.value - expected) < 0.001, tostring(quiet.value))
	check(report, "raison decay", change.reason == "decay", change.reason)
	check(report, "le calme fait baisser", quiet.value < 50)

	-- Un ajout repousse la decroissance.
	local pushed = Threat.new(50, 0)
	pushed.lastEventAt = 0
	Threat.add(pushed, 1, "bruit", 100)
	local pushedChange = Threat.step(pushed, 1, 105)
	check(report, "un evenement repousse le calme", pushedChange.reason == "time", pushedChange.reason)

	-- set() ne compte PAS comme activite : c'est un acte de scenario.
	local scripted = Threat.new(50, 0)
	scripted.lastEventAt = 0
	Threat.set(scripted, 60, "scenario")
	local scriptedChange = Threat.step(scripted, 1, quietDelay + 10)
	check(report, "set ne repousse pas le calme", scriptedChange.reason == "decay", scriptedChange.reason)

	-- dt aberrant : aucun effet.
	local dirty = Threat.new(50, 0)
	Threat.step(dirty, -5, 0)
	Threat.step(dirty, 0 / 0, 0)
	Threat.step(dirty, math.huge, 0)
	check(report, "dt aberrants sans effet", dirty.value == 50, tostring(dirty.value))

	-- Le temps seul finit par tout faire monter : on simule une partie
	-- bruyante de 25 minutes, evenement toutes les 10 s.
	local session = Threat.new(0, 0)
	local now = 0
	for _ = 1, 150 do
		Threat.add(session, 0, "bruit", now)
		now += 10
		Threat.step(session, 10, now)
	end
	check(report, "25 min d'activite mene au sommet", session.value >= 81, tostring(session.value))
end

-- ------------------------------------------------------------- Traque ---

local function testHunt(report: Report)
	table.insert(report.lines, "The Hunt")

	local meter = Threat.new(90, 0)
	local change = Threat.add(meter, 5, "montee", 100)
	check(report, "95 reste CRITICAL", change.band == "CRITICAL", change.band)
	check(report, "pas de traque sous 100", not Threat.shouldTriggerHunt(meter, change, 100))

	local hit = Threat.add(meter, 10, "montee", 110)
	check(report, "100 atteint", meter.value == 100, tostring(meter.value))
	check(report, "palier HUNT", hit.band == "HUNT", hit.band)
	check(report, "traque declenchee", Threat.shouldTriggerHunt(meter, hit, 110))

	Threat.markHuntTriggered(meter, 110)
	check(report, "traque active juste apres", Threat.isHuntActive(meter, 111))

	-- Rester a 100 ne redeclenche pas : le palier n'a pas change.
	local again = Threat.add(meter, 5, "encore", 112)
	check(report, "rester a 100 ne redeclenche pas", not Threat.shouldTriggerHunt(meter, again, 112), again.band)

	-- Redescendre puis remonter pendant le temps de recharge : refuse.
	Threat.set(meter, 50, "retombee")
	local retrigger = Threat.set(meter, 100, "remontee")
	check(report, "palier HUNT de nouveau atteint", retrigger.band == "HUNT")
	check(
		report,
		"recharge empeche la seconde traque",
		not Threat.shouldTriggerHunt(meter, retrigger, 110 + Config.Threat.hunt.cooldown - 5)
	)
	check(
		report,
		"apres la recharge, traque de nouveau possible",
		Threat.shouldTriggerHunt(meter, retrigger, 110 + Config.Threat.hunt.cooldown + 1)
	)

	check(
		report,
		"traque terminee apres sa duree",
		not Threat.isHuntActive(meter, 110 + Config.Threat.hunt.duration + 1)
	)
end

-- ------------------------------------------------------------ Signaux ---

local function testSignals(report: Report)
	table.insert(report.lines, "signaux")

	local signal = Signal.new()
	local received = {}

	local a = Signal.connect(signal, function(value)
		table.insert(received, `a:{value}`)
	end)
	Signal.connect(signal, function(value)
		table.insert(received, `b:{value}`)
	end)

	check(report, "deux abonnes", Signal.count(signal) == 2, tostring(Signal.count(signal)))

	Signal.fire(signal, 1)
	check(report, "les deux recoivent", #received == 2, tostring(#received))

	Signal.disconnect(a)
	check(report, "un abonne en moins", Signal.count(signal) == 1)

	Signal.fire(signal, 2)
	check(report, "seul le restant recoit", #received == 3 and received[3] == "b:2", received[3])

	-- Un abonne qui leve ne doit pas empecher les suivants d'etre servis.
	local resilient = Signal.new()
	local reached = false
	Signal.connect(resilient, function()
		error("abonne casse")
	end)
	Signal.connect(resilient, function()
		reached = true
	end)
	Signal.fire(resilient, nil)
	check(report, "un abonne casse n'empeche pas les autres", reached)

	-- Se desabonner pendant l'emission ne fait pas sauter le suivant.
	local reentrant = Signal.new()
	local seen = 0
	local selfConn
	selfConn = Signal.connect(reentrant, function()
		seen += 1
		Signal.disconnect(selfConn)
	end)
	Signal.connect(reentrant, function()
		seen += 1
	end)
	Signal.fire(reentrant, nil)
	check(report, "desabonnement pendant l'emission", seen == 2, tostring(seen))

	Signal.clear(reentrant)
	check(report, "clear vide le signal", Signal.count(reentrant) == 0)
end

-- ---------------------------------------------------- Config decouplee --

local function testConfigDriven(report: Report)
	table.insert(report.lines, "configuration")

	check(report, "min/max definis", Config.Threat.min == 0 and Config.Threat.max == 100)
	check(report, "sources definies", Config.Threat.sources.GENERATOR ~= nil)
	check(report, "butin majeur defini", Config.Threat.majorLoot.Mythic ~= nil)
	check(report, "traque configuree", Config.Threat.hunt.duration > 0 and Config.Threat.hunt.cooldown > 0)

	-- Le calme doit vraiment faire baisser, sinon la decroissance annoncee
	-- n'existe pas.
	check(
		report,
		"bilan net negatif au calme",
		Config.Threat.decayPerSecond > Config.Threat.passivePerSecond,
		`passif={Config.Threat.passivePerSecond} decay={Config.Threat.decayPerSecond}`
	)

	-- Seules les raretes reellement majeures comptent.
	check(report, "ferraille non majeure", Config.Threat.majorLoot.Common == nil)
	check(report, "rarete Rare majeure", Config.Threat.majorLoot.Rare ~= nil)
end

-- --------------------------------------------------------------- Run ----

function ThreatTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testBands(report)
	testBounds(report)
	testTimeAndDecay(report)
	testHunt(report)
	testSignals(report)
	testConfigDriven(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return ThreatTests
