--!strict
-- Tests du generateur de butin.
--
-- Ils portent sur Shared.Loot, pur et sans monde. Le Random est toujours
-- fourni avec une graine explicite : un test de tirage aleatoire qui n'est
-- pas reproductible ne teste rien, il finit juste par echouer un jour.
--
--   require(game.ServerStorage.Tests.LootTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loot = require(Shared.Loot)
local Config = require(Shared.Config)
local ItemDatabase = require(Shared.ItemDatabase)

local LootTests = {}

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

-- ------------------------------------------------------ Configuration ---

local function testConfig(report: Report)
	table.insert(report.lines, "configuration")

	local tiers = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
	for _, tier in tiers do
		check(report, `palier {tier} pondere`, (Config.Loot.rarityWeights :: any)[tier] ~= nil)
	end

	-- Chaque palier doit exister dans la base, sinon il est decoratif.
	local seen: { [string]: boolean } = {}
	for _, def in ItemDatabase.all() do
		seen[def.rarity] = true
	end
	for _, tier in tiers do
		check(report, `palier {tier} represente par un item`, seen[tier] == true)
	end

	-- Toute entree de table doit designer un item connu, sinon elle pese
	-- zero et pollue silencieusement la table.
	local orphans = {}
	for tableId, entries in Config.Loot.tables do
		for _, entry in entries do
			if not ItemDatabase.has(entry.id) then
				table.insert(orphans, `{tableId}/{entry.id}`)
			end
		end
	end
	check(report, "aucune entree orpheline", #orphans == 0, table.concat(orphans, ", "))

	-- Tout conteneur doit pointer une table existante.
	local badKinds = {}
	for kindId, kind in Config.Loot.containers do
		if not Loot.hasTable(kind.tableId) then
			table.insert(badKinds, `{kindId}->{kind.tableId}`)
		end
	end
	check(report, "tous les conteneurs pointent une table connue", #badKinds == 0, table.concat(badKinds, ", "))
end

-- --------------------------------------------------- Poids et raretes ---

local function testWeighting(report: Report)
	table.insert(report.lines, "ponderation")

	-- prototype_core est Mythic (poids 1), gold_chain Uncommon (poids 400).
	-- A poids local comparable, le Mythic doit peser bien moins.
	local mythic = Loot.effectiveWeight({ id = "prototype_core", weight = 2, min = 1, max = 1 })
	local uncommon = Loot.effectiveWeight({ id = "gold_chain", weight = 8, min = 1, max = 1 })
	check(report, "poids effectif Mythic = 2", mythic == 2, tostring(mythic))
	check(report, "poids effectif Uncommon = 3200", uncommon == 3200, tostring(uncommon))
	check(report, "Mythic bien plus rare qu'Uncommon", mythic < uncommon / 100)

	local unknown = Loot.effectiveWeight({ id = "item_fantome", weight = 100, min = 1, max = 1 })
	check(report, "entree orpheline pese zero", unknown == 0, tostring(unknown))

	-- Distribution reelle sur la table Valuables, graine fixe.
	local counts: { [string]: number } = {}
	local rng = Random.new(1234)
	local draws = 4000
	for _ = 1, draws do
		local stack = Loot.rollOne("Valuables", rng)
		if stack then
			counts[stack.id] = (counts[stack.id] or 0) + 1
		end
	end

	local chain = counts["gold_chain"] or 0
	local core = counts["prototype_core"] or 0
	local box = counts["black_box"] or 0

	check(report, "gold_chain domine la table", chain > box and chain > core, `chain={chain} box={box} core={core}`)
	check(report, "prototype_core quasi absent", core <= draws / 200, `{core}/{draws}`)
	check(report, "toutes les sorties sont des items connus", (function()
		for id in counts do
			if not ItemDatabase.has(id) then
				return false
			end
		end
		return true
	end)())
end

-- --------------------------------------------------------- Tirages ------

local function testRolling(report: Report)
	table.insert(report.lines, "tirages")

	local rng = Random.new(7)

	check(report, "table inconnue -> nil", Loot.rollOne("TableInexistante", rng) == nil)
	check(report, "conteneur inconnu -> vide", #Loot.rollContainer("PasUnConteneur", rng) == 0)

	-- Les quantites doivent rester dans les bornes de l'entree.
	local outOfBounds = 0
	local ammoRng = Random.new(99)
	for _ = 1, 500 do
		local stack = Loot.rollOne("Military", ammoRng)
		if stack and stack.id == "ammo_762" and (stack.quantity < 15 or stack.quantity > 45) then
			outOfBounds += 1
		end
	end
	check(report, "quantites dans les bornes min/max", outOfBounds == 0, `{outOfBounds} hors bornes`)

	-- rollMany fusionne : jamais deux piles du meme id.
	local many = Loot.rollMany("Scrap", 12, Random.new(3))
	local seen: { [string]: boolean } = {}
	local duplicated = false
	for _, stack in many do
		if seen[stack.id] then
			duplicated = true
		end
		seen[stack.id] = true
		if stack.quantity <= 0 then
			duplicated = true
		end
	end
	check(report, "rollMany fusionne par item", not duplicated, `{#many} piles`)
	check(report, "rollMany produit quelque chose", #many > 0)
	check(report, "rollMany(0) est vide", #Loot.rollMany("Scrap", 0, rng) == 0)
	check(report, "rollMany(-5) est vide", #Loot.rollMany("Scrap", -5, rng) == 0)

	-- Reproductibilite : meme graine, meme resultat.
	local a = Loot.rollContainer("Armory", Random.new(42))
	local b = Loot.rollContainer("Armory", Random.new(42))
	local same = #a == #b
	if same then
		for index, stack in a do
			if stack.id ~= b[index].id or stack.quantity ~= b[index].quantity then
				same = false
				break
			end
		end
	end
	check(report, "meme graine -> meme tirage", same)

	-- Nombre de tirages dans les bornes du conteneur : Armory tire 2 a 4,
	-- donc au plus 4 piles distinctes apres fusion.
	local overflow = 0
	for seed = 1, 200 do
		local contents = Loot.rollContainer("Armory", Random.new(seed))
		if #contents > 4 or #contents < 1 then
			overflow += 1
		end
	end
	check(report, "taille de conteneur dans les bornes", overflow == 0, `{overflow} hors bornes`)
end

-- ------------------------------------------------------------- Run ------

function LootTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testConfig(report)
	testWeighting(report)
	testRolling(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return LootTests
