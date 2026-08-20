--!strict
-- Tests de la vue spectateur.
--
-- La camera ne se teste pas ici : c'est de la presentation. Ce qui compte,
-- c'est QUI est regardable. Une liste qui laisserait passer un mort, un
-- extrait ou le spectateur lui-meme braquerait la camera sur un cadavre ou
-- sur le vide, et ce genre de defaut ne leve aucune erreur.
--
--   require(game.ServerStorage.Tests.SpectateTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spectate = require(Shared.Spectate)

local SpectateTests = {}

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

local function entry(userId: number, name: string, alive: boolean, extracted: boolean): Spectate.Entry
	return { userId = userId, name = name, alive = alive, extracted = extracted }
end

local function squad(): { Spectate.Entry }
	return {
		entry(300, "Charlie", true, false),
		entry(100, "Alpha", true, false),
		entry(200, "Bravo", false, false),
		entry(400, "Delta", true, true),
	}
end

-- ------------------------------------------------------------ Matricule --

local function testTag(report: Report)
	table.insert(report.lines, "matricule")

	check(report, "format a quatre chiffres", Spectate.tag(41) == "SCAV-0041", Spectate.tag(41))
	check(report, "deterministe", Spectate.tag(1173430041) == Spectate.tag(1173430041))
	check(report, "tronque a quatre chiffres", #Spectate.tag(999999999) == 9, Spectate.tag(999999999))
	check(report, "identifiant negatif tolere", Spectate.tag(-77) == "SCAV-0077", Spectate.tag(-77))
end

-- --------------------------------------------------------------- Cibles --

local function testTargets(report: Report)
	table.insert(report.lines, "cibles regardables")

	local targets = Spectate.targets(squad(), 100)

	check(report, "une seule cible", #targets == 1, tostring(#targets))
	check(report, "c'est le vivant restant", targets[1] ~= nil and targets[1].userId == 300, tostring(targets[1] and targets[1].userId))
	check(report, "matricule joint", targets[1] ~= nil and targets[1].tag == Spectate.tag(300))

	-- Chaque exclusion verifiee isolement : un test global passerait meme si
	-- deux regles sur trois etaient cassees.
	local withoutViewer = Spectate.targets({ entry(100, "Alpha", true, false) }, 100)
	check(report, "on ne se regarde pas soi-meme", #withoutViewer == 0, tostring(#withoutViewer))

	local dead = Spectate.targets({ entry(200, "Bravo", false, false) }, 999)
	check(report, "un mort n'est pas regardable", #dead == 0, tostring(#dead))

	local gone = Spectate.targets({ entry(400, "Delta", true, true) }, 999)
	check(report, "un extrait n'est pas regardable", #gone == 0, tostring(#gone))

	-- ORDRE STABLE. Les entrees arrivent en desordre ; deux appels doivent
	-- rendre la meme sequence, sinon la camera saute toute seule d'un joueur
	-- a l'autre a chaque diffusion.
	local many = {
		entry(500, "Echo", true, false),
		entry(100, "Alpha", true, false),
		entry(300, "Charlie", true, false),
	}
	local first = Spectate.targets(many, 999)
	check(report, "trie par identifiant", first[1].userId == 100 and first[3].userId == 500)

	local shuffled = { many[3], many[1], many[2] }
	local second = Spectate.targets(shuffled, 999)
	local identical = #first == #second
	if identical then
		for index, target in first do
			if target.userId ~= second[index].userId then
				identical = false
				break
			end
		end
	end
	check(report, "ordre insensible a l'ordre d'entree", identical)

	check(report, "aucun coequipier = liste vide", #Spectate.targets({}, 100) == 0)
end

-- ---------------------------------------------------------------- Cycle --

local function testCycle(report: Report)
	table.insert(report.lines, "changement de flux")

	local targets = Spectate.targets({
		entry(100, "Alpha", true, false),
		entry(200, "Bravo", true, false),
		entry(300, "Charlie", true, false),
	}, 999)

	check(report, "suivant", Spectate.cycle(targets, 100, 1) == 200)
	check(report, "precedent", Spectate.cycle(targets, 200, -1) == 100)
	check(report, "boucle en avant", Spectate.cycle(targets, 300, 1) == 100)
	check(report, "boucle en arriere", Spectate.cycle(targets, 100, -1) == 300)

	-- Cible inconnue : on ne renvoie pas nil, on repart du debut. Sinon la
	-- touche parait morte apres que le sujet suivi a disparu.
	check(report, "cible inconnue -> une cible valide", Spectate.cycle(targets, 999, 1) == 200)
	check(report, "liste vide -> rien", Spectate.cycle({}, 100, 1) == nil)

	local single = Spectate.targets({ entry(100, "Alpha", true, false) }, 999)
	check(report, "une seule cible reste elle-meme", Spectate.cycle(single, 100, 1) == 100)
end

-- ------------------------------------------------------------ Resolution --

local function testResolve(report: Report)
	table.insert(report.lines, "cible apres diffusion")

	local targets = Spectate.targets({
		entry(100, "Alpha", true, false),
		entry(200, "Bravo", true, false),
	}, 999)

	check(report, "la cible tenable est conservee", Spectate.resolve(targets, 200) == 200)
	check(report, "aucune cible -> la premiere", Spectate.resolve(targets, nil) == 100)

	-- LE cas qui compte : celui qu'on regardait vient de mourir.
	check(report, "cible disparue -> bascule", Spectate.resolve(targets, 777) == 100)
	check(report, "plus personne -> nil", Spectate.resolve({}, 200) == nil)

	check(report, "contains sur cible presente", Spectate.contains(targets, 100))
	check(report, "contains sur cible absente", not Spectate.contains(targets, 777))
	check(report, "contains sur nil", not Spectate.contains(targets, nil))
end

function SpectateTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testTag(report)
	testTargets(report)
	testCycle(report)
	testResolve(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return SpectateTests
