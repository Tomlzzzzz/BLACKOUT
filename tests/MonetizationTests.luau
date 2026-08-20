--!strict
-- Tests de la monetisation.
--
-- Portent sur Grants (pur, opere sur un profil brut) et sur le catalogue.
-- Le chemin ProcessReceipt lui-meme depend de Roblox et ne se teste pas
-- ici ; son idempotence est verifiee a travers Grants.wasPurchased et
-- rememberPurchase, qui en portent toute la logique.
--
--   require(game.ServerStorage.Tests.MonetizationTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Schema = require(ServerScriptService.Server.Data.Schema)
local Migrations = require(ServerScriptService.Server.Data.Migrations)
local Grants = require(ServerScriptService.Server.Monetization.Grants)

local MonetizationTests = {}

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

	local products = Config.Monetization.developerProducts
	for _, key in { "BlackTokens", "CreditBoost", "CosmeticBundle" } do
		check(report, `produit {key} present`, products[key] ~= nil)
		if products[key] then
			check(report, `produit {key} a un effet declare`, type(products[key].grant) == "table")
		end
	end

	local passes = Config.Monetization.gamepasses
	check(report, "gamepasses declares", next(passes) ~= nil)

	-- Aucun identifiant ne doit avoir ete invente. Ils valent tous 0 tant
	-- que les produits n'existent pas sur create.roblox.com.
	local invented = {}
	for key, product in products do
		if product.id ~= 0 then
			table.insert(invented, key)
		end
	end
	for key, pass in passes do
		if pass.id ~= 0 then
			table.insert(invented, key)
		end
	end
	check(
		report,
		"aucun identifiant Roblox invente",
		#invented == 0,
		table.concat(invented, ", ")
	)

	-- La separation config / logique : le catalogue ne doit contenir aucune
	-- fonction, sinon la logique aurait commence a s'y glisser.
	local hasFunctions = false
	for _, product in products do
		for _, value in product.grant do
			if type(value) == "function" then
				hasFunctions = true
			end
		end
	end
	check(report, "le catalogue reste declaratif", not hasFunctions)
end

-- ---------------------------------------------------- Regles anti P2W ----

local function testRules(report: Report)
	table.insert(report.lines, "garde-fous pay-to-win")

	local profile = Schema.defaults()

	-- Octroi d'objets : refuse.
	local items = Grants.apply(profile, { type = "items", itemIds = { "black_box" } }, 0)
	check(report, "octroi d'objets refuse", not items.ok, tostring(items.error))
	check(report, "raison explicite", items.error ~= nil and items.error:find("pay%-to%-win") ~= nil, tostring(items.error))

	-- Statistique de combat : refuse.
	local stat = Grants.apply(profile, { type = "stat", stat = "Damage", bonus = 10 }, 0)
	check(report, "boost de statistique refuse", not stat.ok, tostring(stat.error))

	-- Effet en raid : refuse quel que soit le type.
	local inRaid = Grants.apply(profile, { type = "currency", currency = "BlackTokens", amount = 10, inRaid = true }, 0)
	check(report, "effet en raid refuse", not inRaid.ok, tostring(inRaid.error))

	-- Multiplicateur au-dela du plafond : refuse.
	local greedy = Grants.apply(profile, { type = "boost", boostId = "credits", multiplier = 5, duration = 60 }, 0)
	check(report, "multiplicateur excessif refuse", not greedy.ok, tostring(greedy.error))

	-- Duree au-dela du plafond : refusee.
	local eternal = Grants.apply(profile, {
		type = "boost",
		boostId = "credits",
		multiplier = 1.2,
		duration = Config.Monetization.rules.maxBoostDuration + 1,
	}, 0)
	check(report, "duree excessive refusee", not eternal.ok, tostring(eternal.error))

	-- Aucun refus ne doit avoir modifie le profil.
	check(report, "aucun octroi partiel", profile.BlackTokens == 0 and next(profile.Boosts) == nil)

	-- Les trois produits reels passent les regles.
	for key, product in Config.Monetization.developerProducts do
		local fresh = Schema.defaults()
		local result = Grants.apply(fresh, product.grant, 1000)
		check(report, `produit {key} conforme aux regles`, result.ok, tostring(result.error))
	end
end

-- -------------------------------------------------------------- Effets ---

local function testGrants(report: Report)
	table.insert(report.lines, "effets")

	-- Black Tokens : cumulatif.
	local profile = Schema.defaults()
	Grants.apply(profile, Config.Monetization.developerProducts.BlackTokens.grant, 1000)
	check(report, "500 Black Tokens", profile.BlackTokens == 500, tostring(profile.BlackTokens))
	Grants.apply(profile, Config.Monetization.developerProducts.BlackTokens.grant, 1000)
	check(report, "second achat cumule", profile.BlackTokens == 1000, tostring(profile.BlackTokens))

	local bad = Grants.apply(profile, { type = "currency", currency = "Robux", amount = 10 }, 0)
	check(report, "monnaie inconnue refusee", not bad.ok)

	-- Credit Boost : prolonge au lieu de remplacer.
	local boosted = Schema.defaults()
	local grant = Config.Monetization.developerProducts.CreditBoost.grant
	Grants.apply(boosted, grant, 1000)
	local firstExpiry = boosted.Boosts.credits
	check(report, "bonus pose", firstExpiry == 1000 + grant.duration, tostring(firstExpiry))

	Grants.apply(boosted, grant, 1000)
	check(report, "second achat prolonge", boosted.Boosts.credits == firstExpiry + grant.duration, tostring(boosted.Boosts.credits))

	check(report, "multiplicateur actif", Grants.creditMultiplier(boosted, 1000) == grant.multiplier)
	check(report, "multiplicateur expire", Grants.creditMultiplier(boosted, 9e9) == 1)
	check(report, "aucun bonus : multiplicateur 1", Grants.creditMultiplier(Schema.defaults(), 0) == 1)

	-- Le plafond est reapplique a la lecture, meme sur un profil trafique.
	local tampered = Schema.defaults()
	tampered.Boosts.credits = 9e9
	check(
		report,
		"plafond reapplique a la lecture",
		Grants.creditMultiplier(tampered, 0) <= Config.Monetization.rules.maxCreditMultiplier
	)

	-- Cosmetiques : idempotents, et racheter n'est pas une erreur.
	local cosmetic = Schema.defaults()
	local bundle = Config.Monetization.developerProducts.CosmeticBundle.grant
	local first = Grants.apply(cosmetic, bundle, 0)
	check(report, "lot cosmetique accorde", first.ok)
	check(report, "cosmetique possede", Grants.hasCosmetic(cosmetic, "skin_urban"))

	local second = Grants.apply(cosmetic, bundle, 0)
	check(report, "rachat honore sans erreur", second.ok, tostring(second.error))

	-- Capacite de coffre : posee, pas accumulee.
	local upgraded = Schema.defaults()
	local passGrant = Config.Monetization.gamepasses.StashExpansion.grant
	Grants.apply(upgraded, passGrant, 0)
	Grants.apply(upgraded, passGrant, 0)
	check(
		report,
		"gamepass idempotent",
		upgraded.BaseUpgrades.StashCapacity == passGrant.bonus,
		tostring(upgraded.BaseUpgrades.StashCapacity)
	)
end

-- ------------------------------------------------------- Idempotence ----

local function testIdempotence(report: Report)
	table.insert(report.lines, "idempotence des recus")

	local profile = Schema.defaults()

	check(report, "recu inconnu au depart", not Grants.wasPurchased(profile, "recu-1"))
	Grants.rememberPurchase(profile, "recu-1")
	check(report, "recu memorise", Grants.wasPurchased(profile, "recu-1"))

	-- Memoriser deux fois ne doit pas dupliquer l'entree.
	Grants.rememberPurchase(profile, "recu-1")
	check(report, "pas de doublon", #profile.Purchases.order == 1, tostring(#profile.Purchases.order))

	-- Historique borne : les plus anciens sortent, les recents restent.
	local limit = Config.Monetization.purchaseHistoryLimit
	for index = 1, limit + 25 do
		Grants.rememberPurchase(profile, `recu-lot-{index}`)
	end
	check(report, "historique borne", #profile.Purchases.order <= limit, tostring(#profile.Purchases.order))
	check(report, "les recents sont conserves", Grants.wasPurchased(profile, `recu-lot-{limit + 25}`))
	check(report, "les plus anciens sont purges", not Grants.wasPurchased(profile, "recu-lot-1"))

	-- La purge doit nettoyer les deux structures, sinon `seen` fuirait.
	local count = 0
	for _ in profile.Purchases.seen do
		count += 1
	end
	check(report, "seen et order restent coherents", count == #profile.Purchases.order, `{count} vs {#profile.Purchases.order}`)
end

-- ------------------------------------------------------- Migration v3 ---

local function testMigrationV3(report: Report)
	table.insert(report.lines, "migration v2 -> v3")

	-- Un profil v2, tel qu'il existait avant la monetisation.
	local v2 = {
		Version = 2,
		Credits = 5000,
		XP = 120,
		Level = 2,
		Reputation = {},
		Inventory = { Stash = { { id = "medkit", quantity = 2 } } },
		UnlockedItems = {},
		BaseUpgrades = {},
		Cosmetics = { Owned = {}, Equipped = {} },
		Statistics = { Raids = 4, Extractions = 2, Deaths = 2, Kills = 0, CreditsEarned = 0, ItemsLooted = 0, Playtime = 0 },
	}

	local migrated, applied, err = Migrations.migrate(v2, Schema.CURRENT_VERSION)
	check(report, "aucune erreur", err == nil, tostring(err))
	-- Un profil v2 doit remonter jusqu'a la version courante, quel que
	-- soit le nombre d'etapes ajoutees depuis.
	local expected = Schema.CURRENT_VERSION - 2
	check(report, `{expected} etape(s) appliquee(s)`, applied == expected, tostring(applied))
	check(report, "version courante", migrated.Version == Schema.CURRENT_VERSION, tostring(migrated.Version))

	check(report, "credits preserves", migrated.Credits == 5000)
	check(report, "coffre preserve", #migrated.Inventory.Stash == 1)
	check(report, "statistiques preservees", migrated.Statistics.Raids == 4)

	check(report, "BlackTokens initialise", migrated.BlackTokens == 0)
	check(report, "Boosts initialise", type(migrated.Boosts) == "table")
	check(report, "Gamepasses initialise", type(migrated.Gamepasses) == "table")
	check(report, "Purchases initialise", type(migrated.Purchases) == "table" and type(migrated.Purchases.seen) == "table")

	-- Chaine complete v1 -> v3, le cas d'un joueur absent depuis longtemps.
	local v1 = { credits = 999, xp = 10, level = 1, stash = { slots = {} }, stats = { raids = 1 } }
	local full, steps, fullError = Migrations.migrate(v1, Schema.CURRENT_VERSION)
	check(report, "chaine v1 -> v3 sans erreur", fullError == nil, tostring(fullError))
	check(
		report,
		"toutes les etapes appliquees depuis la v1",
		steps == Schema.CURRENT_VERSION - 1,
		tostring(steps)
	)
	check(report, "credits traverses", full.Credits == 999, tostring(full.Credits))
	check(report, "champs v3 presents", full.BlackTokens == 0 and type(full.Purchases) == "table")
	check(report, "champs v4 presents", type(full.Milestones) == "table")
end

-- ------------------------------------------------------------- Run ------

function MonetizationTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testCatalogue(report)
	testRules(report)
	testGrants(report)
	testIdempotence(report)
	testMigrationV3(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return MonetizationTests
