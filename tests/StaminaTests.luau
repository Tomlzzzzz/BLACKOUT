--!strict
-- Tests de l'endurance.
--
-- Le HUD lui-meme n'est pas teste ici : c'est de l'affichage, il se verifie
-- a l'oeil et par capture. Ce qui doit etre verrouille, c'est le calcul qui
-- l'alimente — et celui-la est serveur, donc il compte.
--
--   require(game.ServerStorage.Tests.StaminaTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Stamina = require(Shared.Stamina)
local Config = require(Shared.Config)

local StaminaTests = {}

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

local function cfg()
	return Config.Player.stamina
end

local function testDrainAndRegen(report: Report)
	table.insert(report.lines, "consommation et recuperation")

	local state = Stamina.new(0)
	check(report, "demarre plein", state.value == cfg().max, tostring(state.value))
	check(report, "pas epuise au depart", not state.exhausted)

	-- Effort : au-dela du seuil de vitesse.
	local fast = cfg().moveThreshold + 5
	Stamina.step(state, 1, fast, 10)
	check(report, "l'effort consomme", state.value == cfg().max - cfg().drainPerSecond, tostring(state.value))

	-- Repos immediat : le delai de recuperation n'est pas ecoule.
	local before = state.value
	Stamina.step(state, 0.5, 0, 10.2)
	check(report, "pas de recuperation avant le delai", state.value == before, tostring(state.value))

	-- Delai ecoule : recuperation.
	Stamina.step(state, 1, 0, 10 + cfg().regenDelay + 1)
	check(report, "recuperation apres le delai", state.value > before, tostring(state.value))

	-- Sous le seuil de vitesse, on recupere : marcher n'est pas un effort.
	local walker = Stamina.new(0)
	walker.value = 50
	walker.lastEffortAt = -100
	Stamina.step(walker, 1, cfg().moveThreshold - 1, 0)
	check(report, "marcher n'est pas un effort", walker.value > 50, tostring(walker.value))
end

local function testBounds(report: Report)
	table.insert(report.lines, "bornes")

	local state = Stamina.new(0)

	-- Effort prolonge : plancher a 0, jamais negatif.
	for tick = 1, 40 do
		Stamina.step(state, 1, cfg().moveThreshold + 10, tick)
	end
	check(report, "plancher a 0", state.value == 0, tostring(state.value))
	check(report, "epuise", state.exhausted)

	-- Repos prolonge : plafond a max.
	for tick = 1, 60 do
		Stamina.step(state, 1, 0, 100 + tick)
	end
	check(report, "plafond au maximum", state.value == cfg().max, tostring(state.value))
	check(report, "plus epuise", not state.exhausted)

	-- dt aberrants sans effet.
	local dirty = Stamina.new(0)
	dirty.value = 50
	Stamina.step(dirty, -1, 100, 0)
	Stamina.step(dirty, 0 / 0, 100, 0)
	Stamina.step(dirty, math.huge, 100, 0)
	check(report, "dt aberrants ignores", dirty.value == 50, tostring(dirty.value))

	-- Vitesse aberrante : traitee comme un non-effort, pas comme une erreur.
	local nanSpeed = Stamina.new(0)
	nanSpeed.value = 50
	nanSpeed.lastEffortAt = -100
	Stamina.step(nanSpeed, 1, 0 / 0, 0)
	check(report, "vitesse NaN n'est pas un effort", nanSpeed.value > 50, tostring(nanSpeed.value))
end

local function testHysteresis(report: Report)
	table.insert(report.lines, "hysteresis d'epuisement")

	local state = Stamina.new(0)
	state.value = cfg().exhaustedBelow + 1
	state.lastEffortAt = -100

	Stamina.step(state, 0.2, cfg().moveThreshold + 5, 0)
	check(report, "tombe epuise sous le seuil", state.exhausted, tostring(state.value))

	-- On recupere un peu : on ne doit PAS sortir de l'epuisement tout de
	-- suite, sinon la vitesse alternerait plusieurs fois par seconde.
	Stamina.step(state, 0.5, 0, 100)
	check(report, "reste epuise juste au-dessus du seuil", state.exhausted, tostring(state.value))

	-- On recupere jusqu'au quart de la jauge : on en sort.
	for tick = 1, 10 do
		Stamina.step(state, 1, 0, 100 + tick)
	end
	check(report, "sort de l'epuisement au quart", not state.exhausted, tostring(state.value))
	check(report, "et bien au-dessus du seuil d'entree", state.value >= cfg().max * 0.25)
end

local function testChangeReporting(report: Report)
	table.insert(report.lines, "signalement des changements")

	local state = Stamina.new(0)
	state.value = cfg().max
	state.lastEffortAt = -100

	-- Deja plein et au repos : rien ne change, donc rien a envoyer.
	local changed = Stamina.step(state, 1, 0, 0)
	check(report, "plein au repos : aucun changement", not changed)

	-- Effort : ca change.
	check(report, "effort : changement signale", Stamina.step(state, 1, cfg().moveThreshold + 5, 1))

	check(report, "fraction bornee", Stamina.fraction(state) >= 0 and Stamina.fraction(state) <= 1)
end

local function testConfig(report: Report)
	table.insert(report.lines, "configuration")

	check(report, "maximum defini", cfg().max > 0)
	check(report, "recuperation plus lente que consommation", cfg().regenPerSecond < cfg().drainPerSecond)
	check(report, "delai de recuperation positif", cfg().regenDelay > 0)
	check(report, "vitesse d'epuisement sous la normale", cfg().exhaustedSpeed < 16)
	check(report, "seuil d'epuisement sous le maximum", cfg().exhaustedBelow < cfg().max * 0.25)
end

function StaminaTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testDrainAndRegen(report)
	testBounds(report)
	testHysteresis(report)
	testChangeReporting(report)
	testConfig(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return StaminaTests
