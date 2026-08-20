--!strict
-- Tests de l'instrumentation analytique.
--
-- Portent sur le filtre (pur) et sur le catalogue. Les emissions elles-memes
-- dependent de Player et se verifient en playtest ; ce qui doit etre
-- verrouille ici, c'est la regle qu'on ne peut pas se permettre d'enfreindre :
-- aucune donnee personnelle ne sort.
--
--   require(game.ServerStorage.Tests.AnalyticsTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Sanitize = require(ServerScriptService.Server.Analytics.Sanitize)
local Schema = require(ServerScriptService.Server.Data.Schema)
local Migrations = require(ServerScriptService.Server.Data.Migrations)

local AnalyticsTests = {}

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

-- ------------------------------------------------------------ Catalogue ---

local function testCatalogue(report: Report)
	table.insert(report.lines, "catalogue")

	local required = {
		"PlayerJoined", "TutorialStarted", "TutorialCompleted", "RunStarted",
		"FirstLoot", "FirstEnemyEncounter", "FirstDeath", "FirstExtraction",
		"RunExtracted", "RunFailed", "MissionCompleted",
		"BossSpawned", "BossKilled", "PurchaseStarted", "PurchaseCompleted",
	}

	for _, name in required do
		local definition = Config.Analytics.events[name]
		check(report, `evenement {name} declare`, definition ~= nil)
		if definition then
			check(report, `{name} documente ses champs`, type(definition.fields) == "table" and #definition.fields > 0)
		end
	end

	-- Les jalons doivent etre marques : sans `once`, ils se rejoueraient a
	-- chaque session et l'entonnoir d'accueil serait faux.
	for _, name in { "FirstLoot", "FirstEnemyEncounter", "FirstDeath", "FirstExtraction" } do
		local definition = Config.Analytics.events[name]
		check(report, `{name} marque comme jalon`, definition ~= nil and definition.once == true)
	end

	-- Ceux qui se repetent ne doivent surtout PAS l'etre.
	for _, name in { "RunStarted", "RunExtracted", "RunFailed", "PurchaseCompleted" } do
		local definition = Config.Analytics.events[name]
		check(report, `{name} n'est pas un jalon`, definition ~= nil and definition.once ~= true)
	end

	-- Entonnoirs : chaque etape doit exister au catalogue.
	local orphans = {}
	for _, funnel in Config.Analytics.funnels do
		for _, step in funnel.steps do
			if not Config.Analytics.events[step] then
				table.insert(orphans, step)
			end
		end
	end
	check(report, "aucune etape d'entonnoir orpheline", #orphans == 0, table.concat(orphans, ", "))

	local name, step = Sanitize.funnelStep("FirstExtraction")
	check(report, "FirstExtraction situe dans l'entonnoir", name == "onboarding" and step == 3, `{tostring(name)} #{tostring(step)}`)
	check(report, "evenement hors entonnoir -> nil", Sanitize.funnelStep("PurchaseCompleted") == nil)
end

-- ------------------------------------------------------------- Anti-PII ---

local function testPii(report: Report)
	table.insert(report.lines, "donnees personnelles")

	-- Cles interdites, sous toutes leurs graphies.
	local forbidden = { "name", "Name", "userName", "display_name", "playerName", "email", "IP", "birthDate" }
	for _, key in forbidden do
		local result = Sanitize.payload({ [key] = "quelque chose" })
		check(report, `cle {key} refusee`, not result.ok, tostring(result.error))
	end

	-- Une cle refusee doit faire echouer, pas etre retiree en silence.
	local mixed = Sanitize.payload({ zone = "Nord", username = "quelquun" })
	check(report, "refus global, pas nettoyage partiel", not mixed.ok)
	check(report, "aucune charge utile rendue", mixed.payload == nil)

	-- Le nom du joueur, meme sous une cle anodine.
	local sneaky = Sanitize.payload({ source = "Xrod_Off2" }, { "xrod_off2", "Xrod" })
	check(report, "nom du joueur sous cle anodine refuse", not sneaky.ok, tostring(sneaky.error))

	-- L'identifiant technique reste autorise : les API Roblox l'attendent.
	local ok = Sanitize.payload({ userId = 12345, zone = "Nord" })
	check(report, "identifiant technique autorise", ok.ok, tostring(ok.error))

	-- Types non transmissibles.
	check(report, "table imbriquee refusee", not Sanitize.payload({ data = { a = 1 } }).ok)
	check(report, "fonction refusee", not Sanitize.payload({ f = print }).ok)
	check(report, "Instance refusee", not Sanitize.payload({ part = workspace }).ok)
	check(report, "NaN refuse", not Sanitize.payload({ n = 0 / 0 }).ok)
	check(report, "infini refuse", not Sanitize.payload({ n = math.huge }).ok)

	-- Chaine trop longue : souvent le signe d'un texte libre non maitrise.
	local long = string.rep("a", Config.Analytics.maxStringLength + 1)
	check(report, "chaine trop longue refusee", not Sanitize.payload({ note = long }).ok)

	-- Trop de champs.
	local wide = {}
	for index = 1, Config.Analytics.maxFields + 3 do
		wide[`champ{index}`] = index
	end
	check(report, "trop de champs refuse", not Sanitize.payload(wide).ok)

	-- Cas nominaux.
	local clean = Sanitize.payload({ zone = "Nord", credits = 1650, isNewPlayer = true })
	check(report, "charge utile propre acceptee", clean.ok, tostring(clean.error))
	check(report, "champs preserves", clean.payload ~= nil and clean.payload.credits == 1650)
	check(report, "charge utile nil acceptee", Sanitize.payload(nil).ok)
	check(report, "charge utile non tabulaire refusee", not Sanitize.payload("bonjour").ok)
end

-- --------------------------------------------- Charges reelles du jeu ----

local function testRealPayloads(report: Report)
	table.insert(report.lines, "charges utiles reelles")

	-- Celles que les services emettent effectivement doivent passer.
	local samples = {
		PlayerJoined = { level = 3, credits = 7350, isNewPlayer = false, raids = 12, extractions = 7 },
		RunStarted = { raidState = "InRaid", level = 3, stashValue = 4200 },
		FirstLoot = { itemId = "gold_chain", rarity = "Uncommon", quantity = 2 },
		FirstEnemyEncounter = { enemy = "Crawler", distance = 42 },
		FirstDeath = { cause = "mort", lostValue = 1400, survivedFor = 180 },
		FirstExtraction = { zone = "Nord", lootValue = 1400, credits = 1650 },
		RunExtracted = { zone = "Nord", lootValue = 1400, credits = 1650, stacks = 1, duration = 240, threat = 55 },
		RunFailed = { cause = "mort", lostValue = 1400, duration = 180, threat = 88 },
		MissionCompleted = { missionId = "recover_black_box", reward = 2000, duration = 300 },
		BossSpawned = { boss = "CrawlerAlpha", threat = 100, players = 4 },
		BossKilled = { boss = "CrawlerAlpha", duration = 95, players = 4 },
		PurchaseStarted = { product = "BlackTokens", kind = "produit" },
		PurchaseCompleted = { product = "BlackTokens", summary = "+500 Black Tokens (total 500)" },
		TutorialStarted = { trigger = "premiere_connexion" },
		TutorialCompleted = { trigger = "premiere_extraction", raids = 1 },
	}

	for eventName, payload in samples do
		check(report, `{eventName} : au catalogue`, Config.Analytics.events[eventName] ~= nil)
		local result = Sanitize.payload(payload, { "xrod_off2" })
		check(report, `{eventName} : charge utile acceptee`, result.ok, tostring(result.error))
	end
end

-- ------------------------------------------------------ Jalons persistes --

local function testMilestones(report: Report)
	table.insert(report.lines, "jalons persistes")

	local defaults = Schema.defaults()
	check(report, "Milestones present par defaut", type(defaults.Milestones) == "table")
	check(report, "aucun jalon au depart", next(defaults.Milestones) == nil)

	-- Migration v3 -> v4 : additive, rien de perdu.
	local v3 = {
		Version = 3,
		Credits = 4200,
		XP = 90,
		Level = 2,
		BlackTokens = 500,
		Purchases = { seen = { ["recu-1"] = true }, order = { "recu-1" } },
		Statistics = { Raids = 6, Extractions = 3, Deaths = 3, Kills = 0, CreditsEarned = 0, ItemsLooted = 0, Playtime = 0 },
	}

	local migrated, applied, err = Migrations.migrate(v3, Schema.CURRENT_VERSION)
	check(report, "migration sans erreur", err == nil, tostring(err))
	check(report, "une etape appliquee", applied == 1, tostring(applied))
	check(report, "version 4", migrated.Version == 4, tostring(migrated.Version))
	check(report, "Milestones cree", type(migrated.Milestones) == "table")
	check(report, "credits preserves", migrated.Credits == 4200)
	check(report, "Black Tokens preserves", migrated.BlackTokens == 500)
	check(report, "historique d'achat preserve", migrated.Purchases.seen["recu-1"] == true)

	-- Chaine complete depuis le prototype.
	local v1 = { credits = 100, xp = 0, level = 1, stash = { slots = {} }, stats = {} }
	local full, steps, fullError = Migrations.migrate(v1, Schema.CURRENT_VERSION)
	check(report, "chaine v1 -> v4 sans erreur", fullError == nil, tostring(fullError))
	check(report, "trois etapes appliquees", steps == 3, tostring(steps))
	check(report, "credits traverses", full.Credits == 100, tostring(full.Credits))
	check(report, "Milestones present au bout", type(full.Milestones) == "table")
end

-- ------------------------------------------------------------- Run ------

function AnalyticsTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testCatalogue(report)
	testPii(report)
	testRealPayloads(report)
	testMilestones(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return AnalyticsTests
