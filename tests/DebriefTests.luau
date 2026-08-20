--!strict
-- Tests du rapport de fin de raid.
--
-- L'ecran lui-meme ne se teste pas ici : c'est de la mise en page, elle se
-- verifie a l'oeil. Ce qui compte, c'est le DOCUMENT qu'on lui donne — un
-- rapport qui annoncerait une prime a un joueur mort, ou dont le total ne
-- correspondrait pas a la somme de ses lignes, ferait mentir l'interface
-- sans qu'aucune erreur ne soit levee.
--
--   require(game.ServerStorage.Tests.DebriefTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Debrief = require(Shared.Debrief)
local ItemDatabase = require(Shared.ItemDatabase)
local Types = require(Shared.Types)

local DebriefTests = {}

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

-- Deux objets du catalogue reel, choisis pour leur ecart de valeur : le tri
-- et la troncature ne prouvent rien sur des objets equivalents.
local CHEAP = "scrap_metal"
local RICH = "prototype_core"

local function valueOf(id: string): number
	local definition = ItemDatabase.get(id)
	return if definition then definition.value else 0
end

local function baseInput(): Debrief.BuildInput
	return {
		outcome = "EXTRACTED" :: Types.RaidOutcome,
		userId = 1173430041,
		raids = 116,
		duration = 754,
		manifest = {},
	}
end

-- --------------------------------------------------------------- Lignes --

local function testLines(report: Report)
	table.insert(report.lines, "manifeste")

	local lines = Debrief.lines({
		{ id = CHEAP, quantity = 3 },
		{ id = RICH, quantity = 1 },
	})

	check(report, "deux lignes", #lines == 2, tostring(#lines))
	check(report, "la plus chere en premier", lines[1].id == RICH, lines[1].id)
	check(report, "valeur = unitaire x quantite", lines[2].value == valueOf(CHEAP) * 3, tostring(lines[2].value))
	check(report, "unitaire conserve", lines[2].unitValue == valueOf(CHEAP), tostring(lines[2].unitValue))
	check(report, "rarete resolue", lines[1].rarity ~= nil and lines[1].rarity ~= "")

	-- Une pile a zero n'est pas une ligne : elle occuperait une place dans un
	-- manifeste tronque, au detriment d'une ligne qui existe vraiment.
	local withEmpty = Debrief.lines({
		{ id = CHEAP, quantity = 0 },
		{ id = RICH, quantity = 2 },
	})
	check(report, "pile vide ignoree", #withEmpty == 1, tostring(#withEmpty))

	-- Un objet retire du catalogue ne doit pas faire tomber le rapport : il
	-- vaut zero et reste lisible.
	local unknown = Debrief.lines({ { id = "objet_inexistant", quantity = 2 } })
	check(report, "objet inconnu tolere", #unknown == 1)
	check(report, "objet inconnu vaut zero", unknown[1] ~= nil and unknown[1].value == 0)

	check(report, "total = somme des lignes", Debrief.total(lines) == valueOf(RICH) + valueOf(CHEAP) * 3)
	check(report, "total d'un manifeste vide", Debrief.total({}) == 0)
end

-- -------------------------------------------------------------- Notation --

local function testRating(report: Report)
	table.insert(report.lines, "notation")

	local tiers = Config.Debrief.rating
	local top = tiers[1]
	local bottom = tiers[#tiers]

	check(report, "paliers decroissants", top.minValue > bottom.minValue)
	check(report, "palier le plus bas a zero", bottom.minValue == 0, tostring(bottom.minValue))

	check(report, "haute valeur -> meilleure note", Debrief.rate("EXTRACTED", top.minValue, false) == top.key)
	check(report, "rien rapporte -> note la plus basse", Debrief.rate("EXTRACTED", 0, false) == bottom.key)

	-- La mort efface le bareme. C'est la regle qui donne son ton au jeu : on
	-- ne rattrape pas une perte seche par un bon raid.
	check(report, "mort -> perte seche", Debrief.rate("KIA", top.minValue, true) == Config.Debrief.lostRating)
	check(report, "fenetre close -> perte seche", Debrief.rate("EXPIRED", top.minValue, true) == Config.Debrief.lostRating)

	-- Promotion par contrat rempli.
	local plain = Debrief.rate("EXTRACTED", bottom.minValue, false)
	local promoted = Debrief.rate("EXTRACTED", bottom.minValue, true)
	check(report, "contrat rempli fait monter d'un cran", plain ~= promoted, `{plain} / {promoted}`)

	-- Et jamais au-dela du sommet : promouvoir la meilleure note doit rester
	-- la meilleure note, pas sortir du tableau.
	check(
		report,
		"promotion bornee au sommet",
		Debrief.rate("EXTRACTED", top.minValue, true) == top.key
	)
end

-- ------------------------------------------------------------- Reference --

local function testReference(report: Report)
	table.insert(report.lines, "numero de dossier")

	local a = Debrief.reference(1173430041, 116)
	local b = Debrief.reference(1173430041, 116)

	check(report, "deterministe", a == b, `{a} / {b}`)
	check(report, "prefixe respecte", string.sub(a, 1, #Config.Debrief.referencePrefix) == Config.Debrief.referencePrefix, a)
	check(report, "format a deux groupes de quatre", string.match(a, "^%u+%-%d%d%d%d%-%d%d%d%d$") ~= nil, a)

	-- Deux sorties du meme joueur portent des numeros differents : c'est ce
	-- qui en fait un numero de dossier et non un identifiant de compte.
	check(report, "une sortie plus tard = autre numero", Debrief.reference(1173430041, 117) ~= a)

	-- Valeurs hors bornes : un profil neuf a zero raid, un identifiant
	-- gigantesque. Aucun des deux ne doit produire de format casse.
	check(report, "zero raid tolere", string.match(Debrief.reference(1, 0), "^%u+%-%d%d%d%d%-%d%d%d%d$") ~= nil)
	check(report, "grand identifiant tolere", string.match(Debrief.reference(99999999999, 99999), "^%u+%-%d%d%d%d%-%d%d%d%d$") ~= nil)
end

-- --------------------------------------------------------------- Rapport --

local function testBuild(report: Report)
	table.insert(report.lines, "assemblage")

	local input = baseInput()
	input.manifest = {
		{ id = RICH, quantity = 1 },
		{ id = CHEAP, quantity = 4 },
	}
	input.bonus = 250
	input.credits = 1250
	input.xpGained = 120
	input.level = 4
	input.leveledUp = true
	input.balance = 9910
	input.zone = "NORTH GATE"
	input.kills = 3
	input.damageTaken = 182
	input.peakThreat = 71

	local built = Debrief.build(input)

	check(report, "issue conservee", built.outcome == "EXTRACTED")
	check(report, "zone conservee", built.zone == "NORTH GATE")
	check(report, "duree conservee", built.duration == 754, tostring(built.duration))
	check(report, "credits conserves", built.credits == 1250, tostring(built.credits))
	check(report, "prime conservee", built.bonus == 250)
	check(report, "solde conserve", built.balance == 9910)
	check(report, "montee de niveau conservee", built.leveledUp)
	check(report, "eliminations conservees", built.kills == 3)
	check(report, "degats conserves", built.damageTaken == 182)
	check(report, "pic conserve", built.peakThreat == 71)
	check(report, "numero present", built.reference ~= "" and built.reference ~= nil)
	check(report, "note calculee", built.rating ~= nil and built.rating ~= "")

	check(
		report,
		"valeur du manifeste = somme",
		built.manifestValue == valueOf(RICH) + valueOf(CHEAP) * 4,
		tostring(built.manifestValue)
	)

	-- Sans contrat : aucun objectif, et pas de promotion possible.
	check(report, "aucun objectif sans contrat", built.objectivesTotal == 0 and built.objectivesDone == 0)
	check(report, "contrat non rempli sans contrat", not built.contractComplete)
	check(report, "cle de contrat absente", built.contractKey == nil)
end

local function testTruncation(report: Report)
	table.insert(report.lines, "troncature du manifeste")

	local limit = Config.Debrief.manifestLimit
	local input = baseInput()

	-- Un objet cher en tete, puis assez de piles bon marche pour deborder de
	-- deux lignes.
	input.manifest = { { id = RICH, quantity = 1 } }
	for _ = 1, limit + 1 do
		table.insert(input.manifest, { id = CHEAP, quantity = 1 })
	end

	local built = Debrief.build(input)

	check(report, "lignes affichees bornees", #built.manifest == limit, tostring(#built.manifest))
	check(report, "l'objet cher survit a la coupe", built.manifest[1].id == RICH, built.manifest[1].id)
	-- Le debordement compte des LIGNES. Deux piles coupees, donc deux.
	check(report, "debordement compte des lignes", built.overflowCount == 2, tostring(built.overflowCount))
	check(
		report,
		"debordement chiffre",
		built.overflowValue == valueOf(CHEAP) * 2,
		tostring(built.overflowValue)
	)

	-- Piles GROSSES en debordement : c'est le seul cas ou compter les
	-- lignes et compter les unites divergent. Sans lui, le test
	-- passerait avec l'une comme avec l'autre.
	local bulky = baseInput()
	bulky.manifest = { { id = RICH, quantity = 1 } }
	for _ = 1, limit + 1 do
		table.insert(bulky.manifest, { id = CHEAP, quantity = 30 })
	end
	local bulked = Debrief.build(bulky)
	check(
		report,
		"debordement insensible aux quantites",
		bulked.overflowCount == 2,
		tostring(bulked.overflowCount)
	)

	-- LA propriete qui compte : ce qui est affiche plus ce qui est agrege
	-- egale le total. Sans elle, le joueur additionne les lignes visibles et
	-- trouve un autre chiffre que celui du bas de page.
	local shown = 0
	for _, line in built.manifest do
		shown += line.value
	end
	check(
		report,
		"affiche + agrege = total",
		shown + built.overflowValue == built.manifestValue,
		`{shown} + {built.overflowValue} vs {built.manifestValue}`
	)
end

local function testFailedRuns(report: Report)
	table.insert(report.lines, "sorties ratees")

	-- Un appelant distrait — ou un futur refactor — pourrait transmettre une
	-- recompense sur un chemin d'echec. Le rapport doit la refuser lui-meme :
	-- afficher une prime a un joueur qui vient de mourir serait la pire
	-- trahison possible de l'interface.
	for _, outcome in { "KIA", "EXPIRED" } do
		local input = baseInput()
		input.outcome = outcome :: Types.RaidOutcome
		input.manifest = { { id = RICH, quantity = 1 } }
		input.bonus = 250
		input.credits = 1250
		input.xpGained = 120
		input.leveledUp = true

		local built = Debrief.build(input)

		check(report, `{outcome} : aucun credit`, built.credits == 0, tostring(built.credits))
		check(report, `{outcome} : aucune prime`, built.bonus == 0, tostring(built.bonus))
		check(report, `{outcome} : aucune experience`, built.xpGained == 0, tostring(built.xpGained))
		check(report, `{outcome} : aucune promotion`, not built.leveledUp)
		check(report, `{outcome} : perte seche`, built.rating == Config.Debrief.lostRating, built.rating)

		-- La cargaison perdue reste chiffree : c'est tout l'interet du
		-- rapport. On doit savoir CE QU'ON VIENT DE PERDRE.
		check(report, `{outcome} : perte chiffree`, built.manifestValue == valueOf(RICH), tostring(built.manifestValue))
		check(report, `{outcome} : perte detaillee`, #built.manifest == 1)
	end
end

local function testContract(report: Report)
	table.insert(report.lines, "contrat")

	local contract: Types.Contract = {
		id = "C004",
		titleKey = "contract.C004.title",
		subtitleKey = "contract.C004.sub",
		objectives = {
			{ kind = "collect" :: any, labelKey = "a", progress = 1, done = true },
			{ kind = "collect" :: any, labelKey = "b", progress = 0, done = false },
			{ kind = "collect" :: any, labelKey = "c", progress = 1, done = true },
		},
		reward = 500,
		complete = false,
	}

	local input = baseInput()
	input.manifest = { { id = CHEAP, quantity = 1 } }
	input.contract = contract

	local built = Debrief.build(input)
	check(report, "objectifs comptes", built.objectivesTotal == 3, tostring(built.objectivesTotal))
	check(report, "objectifs remplis comptes", built.objectivesDone == 2, tostring(built.objectivesDone))
	check(report, "cle de titre transmise", built.contractKey == "contract.C004.title")
	check(report, "contrat incomplet reporte", not built.contractComplete)

	contract.complete = true
	local finished = Debrief.build(input)
	check(report, "contrat complet reporte", finished.contractComplete)
end

local function testLeftBehind(report: Report)
	table.insert(report.lines, "coffre plein")

	local input = baseInput()
	input.manifest = { { id = CHEAP, quantity = 1 } }
	input.leftBehind = { { id = RICH, quantity = 1 }, { id = CHEAP, quantity = 2 } }

	local built = Debrief.build(input)
	check(report, "piles laissees comptees", built.leftBehind == 2, tostring(built.leftBehind))

	local none = Debrief.build(baseInput())
	check(report, "aucune pile laissee par defaut", none.leftBehind == 0)
	check(report, "manifeste vide tolere", #none.manifest == 0 and none.manifestValue == 0)
end

function DebriefTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testLines(report)
	testRating(report)
	testReference(report)
	testBuild(report)
	testTruncation(report)
	testFailedRuns(report)
	testContract(report)
	testLeftBehind(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return DebriefTests
