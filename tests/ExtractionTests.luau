--!strict
-- Tests du coeur d'extraction.
--
-- Ils portent sur Shared.Extraction, pur. C'est ce qui rend testables les
-- quatre scenarios demandes — dont "mourir pendant l'extraction" et
-- "plusieurs joueurs simultanement", impossibles a produire avec un seul
-- client Studio.
--
--   require(game.ServerStorage.Tests.ExtractionTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Extraction = require(Shared.Extraction)
local Inventory = require(Shared.Inventory)

local ExtractionTests = {}

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

-- Conditions nominales : joueur vivant, dans une zone ouverte, raid en cours.
local function nominal(overrides: { [string]: boolean }?)
	local conditions = { inZone = true, alive = true, zoneActive = true, runValid = true }
	if overrides then
		for key, value in overrides do
			(conditions :: any)[key] = value
		end
	end
	return conditions
end

-- ------------------------------------------------ Extraction normale ----

local function testNormal(report: Report)
	table.insert(report.lines, "extraction normale")

	local progress = Extraction.begin("Nord", 3)
	check(report, "demarre a 0%", Extraction.fraction(progress) == 0)
	check(report, "en cours au depart", Extraction.isRunning(progress))

	local outcome = Extraction.step(progress, 1, nominal())
	check(report, "1s -> running", outcome == "running", tostring(outcome))
	check(report, "progression a 1/3", math.abs(Extraction.fraction(progress) - 1 / 3) < 0.001)
	check(report, "restant = 2s", math.abs(Extraction.remaining(progress) - 2) < 0.001)

	Extraction.step(progress, 1, nominal())
	outcome = Extraction.step(progress, 1, nominal())
	check(report, "3s -> completed", outcome == "completed", tostring(outcome))
	check(report, "progression a 100%", Extraction.fraction(progress) == 1)
	check(report, "elapsed borne au holdTime", progress.elapsed == 3, tostring(progress.elapsed))
	check(report, "plus en cours", not Extraction.isRunning(progress))

	-- Duree minimale : un seul pas ne doit pas suffire si dt < holdTime.
	local quick = Extraction.begin("Est", 12)
	check(report, "duree minimale respectee", Extraction.step(quick, 11.9, nominal()) == "running")
	check(report, "puis complete au dernier pas", Extraction.step(quick, 0.2, nominal()) == "completed")
end

-- --------------------------------------------------- Sortie de zone -----

local function testLeavingZone(report: Report)
	table.insert(report.lines, "sortie de zone")

	local progress = Extraction.begin("Nord", 10)
	Extraction.step(progress, 4, nominal())
	check(report, "progression acquise avant sortie", progress.elapsed == 4)

	local outcome, reason = Extraction.step(progress, 1, nominal({ inZone = false }))
	check(report, "sortie -> cancelled", outcome == "cancelled", tostring(outcome))
	check(report, "raison LEFT_ZONE", reason == "LEFT_ZONE", tostring(reason))
	check(report, "le temps ne s'accumule plus", progress.elapsed == 4, tostring(progress.elapsed))

	-- Revenir ne reprend pas : il faut une nouvelle extraction.
	local after = Extraction.step(progress, 1, nominal())
	check(report, "un pas apres annulation -> finished", after == "finished", tostring(after))
	check(report, "toujours annulee", progress.phase == "Cancelled")

	-- Zone qui se ferme pendant le maintien.
	local closing = Extraction.begin("Sud", 10)
	Extraction.step(closing, 3, nominal())
	local closedOutcome, closedReason = Extraction.step(closing, 1, nominal({ zoneActive = false }))
	check(report, "zone fermee -> cancelled", closedOutcome == "cancelled")
	check(report, "raison ZONE_INACTIVE", closedReason == "ZONE_INACTIVE", tostring(closedReason))

	-- Raid termine pendant le maintien.
	local ending = Extraction.begin("Ouest", 10)
	Extraction.step(ending, 3, nominal())
	local endedOutcome, endedReason = Extraction.step(ending, 1, nominal({ runValid = false }))
	check(report, "raid invalide -> cancelled", endedOutcome == "cancelled")
	check(report, "raison RUN_INVALID", endedReason == "RUN_INVALID", tostring(endedReason))
end

-- ------------------------------------------ Mort pendant l'extraction ---

local function testDeath(report: Report)
	table.insert(report.lines, "mort pendant l'extraction")

	local progress = Extraction.begin("Nord", 10)
	Extraction.step(progress, 9, nominal())
	check(report, "a 90% juste avant la mort", math.abs(Extraction.fraction(progress) - 0.9) < 0.001)

	local outcome, reason = Extraction.step(progress, 1, nominal({ alive = false }))
	check(report, "mort -> cancelled", outcome == "cancelled", tostring(outcome))
	check(report, "raison DEAD", reason == "DEAD", tostring(reason))
	check(report, "pas de completion malgre le dernier pas", progress.phase == "Cancelled")

	-- Un mort quitte mecaniquement la zone : les deux conditions tombent
	-- ensemble et c'est la mort qui doit etre annoncee, pas la sortie.
	local both = Extraction.begin("Est", 5)
	Extraction.step(both, 2, nominal())
	local _, bothReason = Extraction.step(both, 1, nominal({ alive = false, inZone = false }))
	check(report, "mort prime sur sortie de zone", bothReason == "DEAD", tostring(bothReason))

	-- Mourir pile au pas qui aurait complete.
	local lastMoment = Extraction.begin("Sud", 5)
	Extraction.step(lastMoment, 4.9, nominal())
	local lastOutcome = Extraction.step(lastMoment, 1, nominal({ alive = false }))
	check(report, "mort au dernier pas : aucune recompense", lastOutcome == "cancelled", tostring(lastOutcome))
end

-- ------------------------------------------ Plusieurs joueurs a la fois --

local function testConcurrent(report: Report)
	table.insert(report.lines, "plusieurs joueurs simultanement")

	-- Quatre joueurs, memes zones ou non, destins differents.
	local players = {
		{ name = "A", progress = Extraction.begin("Nord", 3), fate = "normal" },
		{ name = "B", progress = Extraction.begin("Nord", 3), fate = "leaves" },
		{ name = "C", progress = Extraction.begin("Est", 6), fate = "dies" },
		{ name = "D", progress = Extraction.begin("Est", 6), fate = "normal" },
	}

	local outcomes: { [string]: string } = {}

	for step = 1, 6 do
		for _, entry in players do
			local conditions = nominal()
			if entry.fate == "leaves" and step == 2 then
				conditions = nominal({ inZone = false })
			elseif entry.fate == "dies" and step == 4 then
				conditions = nominal({ alive = false })
			end

			local outcome = Extraction.step(entry.progress, 1, conditions)
			if outcome == "completed" or outcome == "cancelled" then
				if not outcomes[entry.name] then
					outcomes[entry.name] = `{outcome}@{step}`
				end
			end
		end
	end

	check(report, "A complete a 3s", outcomes["A"] == "completed@3", tostring(outcomes["A"]))
	check(report, "B annule a 2s", outcomes["B"] == "cancelled@2", tostring(outcomes["B"]))
	check(report, "C annule a 4s", outcomes["C"] == "cancelled@4", tostring(outcomes["C"]))
	check(report, "D complete a 6s", outcomes["D"] == "completed@6", tostring(outcomes["D"]))

	check(report, "A n'a pas ete affecte par B", players[1].progress.phase == "Completed")
	check(report, "D n'a pas ete affecte par C", players[4].progress.phase == "Completed")
	check(report, "B garde sa progression figee", players[2].progress.elapsed == 1, tostring(players[2].progress.elapsed))
	check(report, "C garde sa progression figee", players[3].progress.elapsed == 3, tostring(players[3].progress.elapsed))
end

-- --------------------------------------- Double recompense et dt sales ---

local function testGuards(report: Report)
	table.insert(report.lines, "garde-fous")

	-- Une extraction terminee ne redonne jamais "completed", quel que soit
	-- le nombre de pas supplementaires.
	local progress = Extraction.begin("Nord", 2)
	Extraction.step(progress, 2, nominal())
	check(report, "premier passage -> completed", progress.phase == "Completed")

	local extra = 0
	for _ = 1, 10 do
		local outcome = Extraction.step(progress, 1, nominal())
		if outcome == "completed" then
			extra += 1
		end
	end
	check(report, "10 pas de plus, 0 completion supplementaire", extra == 0, `{extra} completions`)

	-- Pas de temps aberrants : ignores, jamais propages.
	local dirty = Extraction.begin("Est", 10)
	Extraction.step(dirty, -5, nominal())
	check(report, "dt negatif ignore", dirty.elapsed == 0, tostring(dirty.elapsed))
	Extraction.step(dirty, 0 / 0, nominal())
	check(report, "dt NaN ignore", dirty.elapsed == 0, tostring(dirty.elapsed))
	Extraction.step(dirty, math.huge, nominal())
	check(report, "dt infini ignore", dirty.elapsed == 0, tostring(dirty.elapsed))
	check(report, "toujours en cours apres dt sales", dirty.phase == "Running")
	Extraction.step(dirty, 10, nominal())
	check(report, "un dt propre complete normalement", dirty.phase == "Completed")

	-- holdTime nul : complete au premier pas, sans division par zero.
	local instant = Extraction.begin("Sud", 0)
	check(report, "holdTime 0 -> fraction 1", Extraction.fraction(instant) == 1)
	check(report, "holdTime 0 -> complete au 1er pas", Extraction.step(instant, 0.1, nominal()) == "completed")
end

-- ------------------------------------- Effet economique de l'extraction --

local function testPayout(report: Report)
	table.insert(report.lines, "butin extrait")

	-- Ce que ExtractionService fera : transferer le sac dans le coffre puis
	-- chiffrer ce qui a bouge. On verifie que la valeur suit le transfert.
	local bag = Inventory.new(40)
	local stash = Inventory.new(600)
	Inventory.add(bag, "graphics_card", 1)
	Inventory.add(bag, "gold_chain", 2)

	local expected = 1800 + 2 * 350
	check(report, "valeur du sac avant extraction", Inventory.value(bag) == expected, tostring(Inventory.value(bag)))

	local summary = Inventory.transfer(bag, stash)
	check(report, "tout est extrait", #summary.leftBehind == 0)
	check(report, "sac vide apres extraction", Inventory.value(bag) == 0)
	check(report, "valeur transferee au coffre", Inventory.value(stash) == expected, tostring(Inventory.value(stash)))

	-- Extraire deux fois de suite ne cree rien : le sac est deja vide.
	local second = Inventory.transfer(bag, stash)
	check(report, "seconde extraction ne rapporte rien", #second.moved == 0)
	check(report, "coffre inchange", Inventory.value(stash) == expected)
end

-- ------------------------------------------------------------- Run ------

function ExtractionTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testNormal(report)
	testLeavingZone(report)
	testDeath(report)
	testConcurrent(report)
	testGuards(report)
	testPayout(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return ExtractionTests
