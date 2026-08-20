--!strict
-- Tests du coeur d'inventaire.
--
-- Ils portent sur le module pur (Shared.Inventory) et sur RequestGuard,
-- jamais sur InventoryService : c'est precisement pour pouvoir les executer
-- sans joueur ni partie lancee que la logique est separee du service.
--
-- Execution depuis la barre de commande Studio ou via MCP :
--   require(game.ServerStorage.Tests.InventoryTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Inventory = require(Shared.Inventory)
local ItemDatabase = require(Shared.ItemDatabase)
local RequestGuard = require(Shared.Utils.RequestGuard)

local InventoryTests = {}

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

-- --------------------------------------------------------------- Ajout ---

local function testAdding(report: Report)
	table.insert(report.lines, "ajout d'items")

	local inv = Inventory.new(40)

	local result = Inventory.add(inv, "military_battery", 1)
	check(report, "ajout simple accepte", result.ok, tostring(result.error))
	check(report, "quantite comptee = 1", Inventory.count(inv, "military_battery") == 1)
	check(report, "poids = 2", Inventory.weight(inv) == 2, tostring(Inventory.weight(inv)))
	check(report, "has() vrai", Inventory.has(inv, "military_battery"))
	check(report, "has() faux pour un absent", not Inventory.has(inv, "bandage"))

	-- maxStack de military_battery vaut 4 : 6 unites tiennent en 2 piles.
	Inventory.add(inv, "military_battery", 5)
	check(report, "empilement jusqu'a maxStack", #inv.slots == 2, `{#inv.slots} piles`)
	check(report, "total apres empilement = 6", Inventory.count(inv, "military_battery") == 6)
	check(report, "premiere pile pleine", inv.slots[1].quantity == 4, tostring(inv.slots[1].quantity))

	-- Non empilable : une pile par exemplaire, meme sous la capacite.
	local bag = Inventory.new(40)
	Inventory.add(bag, "keycard_blue", 3)
	check(report, "non empilable = 3 piles", #bag.slots == 3, `{#bag.slots} piles`)

	local resolved = Inventory.contents(inv)
	check(report, "contents() resout la definition", resolved[1] ~= nil and resolved[1].name == "Batterie militaire")
	check(report, "contents() donne la rarete", resolved[1] ~= nil and resolved[1].rarity == "Rare")
	check(report, "contents() valorise la pile", resolved[1] ~= nil and resolved[1].value == 4 * 500, tostring(resolved[1] and resolved[1].value))
end

-- -------------------------------------------------------------- Retrait ---

local function testRemoving(report: Report)
	table.insert(report.lines, "retrait d'items")

	local inv = Inventory.new(40)
	Inventory.add(inv, "scrap_metal", 10)

	local partial = Inventory.remove(inv, "scrap_metal", 4)
	check(report, "retrait partiel accepte", partial.ok, tostring(partial.error))
	check(report, "reste 6", Inventory.count(inv, "scrap_metal") == 6)
	check(report, "poids suit le retrait", Inventory.weight(inv) == 6)

	local rest = Inventory.remove(inv, "scrap_metal", 6)
	check(report, "retrait total accepte", rest.ok)
	check(report, "pile vide supprimee", #inv.slots == 0, `{#inv.slots} piles restantes`)
	check(report, "poids retombe a 0", Inventory.weight(inv) == 0)

	local tooMuch = Inventory.remove(inv, "scrap_metal", 1)
	check(report, "retrait sans stock refuse", not tooMuch.ok and tooMuch.error == "NOT_ENOUGH", tostring(tooMuch.error))

	-- Retrait reparti sur plusieurs piles.
	local multi = Inventory.new(40)
	Inventory.add(multi, "military_battery", 6)
	local across = Inventory.remove(multi, "military_battery", 5)
	check(report, "retrait a cheval sur 2 piles", across.ok and Inventory.count(multi, "military_battery") == 1)

	local unknown = Inventory.remove(multi, "nope", 1)
	check(report, "item inconnu refuse", not unknown.ok and unknown.error == "UNKNOWN_ITEM", tostring(unknown.error))
end

-- ------------------------------------------------------------ Capacite ---

local function testCapacity(report: Report)
	table.insert(report.lines, "depassement de capacite")

	-- Capacite 5, batteries a 2 : trois n'entrent pas.
	local inv = Inventory.new(5)

	local first = Inventory.add(inv, "military_battery", 2)
	check(report, "2 batteries entrent (4 <= 5)", first.ok, tostring(first.error))

	local overflow = Inventory.add(inv, "military_battery", 1)
	check(report, "la 3e est refusee (6 > 5)", not overflow.ok and overflow.error == "OVER_CAPACITY", tostring(overflow.error))
	check(report, "refus sans mutation : total inchange", Inventory.count(inv, "military_battery") == 2)
	check(report, "refus sans mutation : poids inchange", Inventory.weight(inv) == 4)

	-- Un lot entier qui ne passe pas ne doit pas entrer partiellement.
	local bulk = Inventory.new(5)
	local bulkResult = Inventory.add(bulk, "scrap_metal", 9)
	check(report, "lot trop lourd refuse en bloc", not bulkResult.ok and bulkResult.error == "OVER_CAPACITY")
	check(report, "aucun item n'est entre", #bulk.slots == 0, `{#bulk.slots} piles`)

	-- Pile exacte : 5 ferrailles pour 5 de capacite.
	local exact = Inventory.new(5)
	check(report, "remplissage exact accepte", Inventory.add(exact, "scrap_metal", 5).ok)
	check(report, "capacite libre = 0", Inventory.freeWeight(exact) == 0)
end

-- --------------------------------------------------- Quantites invalides ---

local function testInvalidQuantities(report: Report)
	table.insert(report.lines, "quantites invalides")

	local inv = Inventory.new(40)

	local cases: { { label: string, value: any } } = {
		{ label = "zero", value = 0 },
		{ label = "negatif", value = -3 },
		{ label = "decimal", value = 1.5 },
		{ label = "NaN", value = 0 / 0 },
		{ label = "infini", value = math.huge },
		{ label = "infini negatif", value = -math.huge },
		{ label = "chaine", value = "3" },
		{ label = "nil", value = nil },
		{ label = "table", value = {} },
		{ label = "booleen", value = true },
	}

	for _, case in cases do
		local result = Inventory.add(inv, "scrap_metal", case.value :: any)
		check(
			report,
			`ajout refuse : {case.label}`,
			not result.ok and result.error == "INVALID_QUANTITY",
			tostring(result.error)
		)
	end

	check(report, "aucun item n'est entre", #inv.slots == 0, `{#inv.slots} piles`)

	-- Meme filtre au retrait, sur un inventaire non vide cette fois.
	Inventory.add(inv, "scrap_metal", 5)
	local badRemove = Inventory.remove(inv, "scrap_metal", -1)
	check(report, "retrait negatif refuse", not badRemove.ok and badRemove.error == "INVALID_QUANTITY", tostring(badRemove.error))
	check(report, "stock intact apres refus", Inventory.count(inv, "scrap_metal") == 5)

	-- has() ne doit pas lever sur une quantite absurde.
	check(report, "has() faux sur quantite invalide", not Inventory.has(inv, "scrap_metal", -1))

	local unknownAdd = Inventory.add(inv, "item_qui_nexiste_pas", 1)
	check(report, "item inconnu refuse", not unknownAdd.ok and unknownAdd.error == "UNKNOWN_ITEM", tostring(unknownAdd.error))
end

-- ------------------------------------------------- Requetes dupliquees ---

local function testDuplicateRequests(report: Report)
	table.insert(report.lines, "requetes dupliquees")

	local guard = RequestGuard.new(4)

	check(report, "1re occurrence acceptee", RequestGuard.accept(guard, 1))
	check(report, "rejeu du meme id refuse", not RequestGuard.accept(guard, 1))
	check(report, "id different accepte", RequestGuard.accept(guard, 2))
	check(report, "rejeu du 2e refuse", not RequestGuard.accept(guard, 2))
	check(report, "NaN refuse", not RequestGuard.accept(guard, 0 / 0))

	-- Effet concret : deux fois la meme demande de retrait ne retire qu'une
	-- fois. C'est le comportement que le remote doit garantir.
	local inv = Inventory.new(40)
	Inventory.add(inv, "bandage", 5)

	local requestId = 99
	local applied = 0
	for _ = 1, 3 do
		if RequestGuard.accept(guard, requestId) then
			Inventory.remove(inv, "bandage", 1)
			applied += 1
		end
	end

	check(report, "3 envois, 1 seule application", applied == 1, `{applied} applications`)
	check(report, "stock retire une seule fois", Inventory.count(inv, "bandage") == 4, tostring(Inventory.count(inv, "bandage")))

	-- La fenetre glissante libere les plus anciens : au-dela de la limite,
	-- un vieil id redevient acceptable. C'est un compromis assume — memoire
	-- bornee contre protection infinie.
	local small = RequestGuard.new(2)
	RequestGuard.accept(small, 10)
	RequestGuard.accept(small, 11)
	RequestGuard.accept(small, 12)
	check(report, "fenetre glissante purge le plus ancien", RequestGuard.accept(small, 10))
end

-- ------------------------------------------------- Sac de raid / coffre ---

local function testRaidAndStash(report: Report)
	table.insert(report.lines, "sac de raid et coffre")

	local bag = Inventory.new(40)
	local stash = Inventory.new(600)

	Inventory.add(bag, "military_battery", 3)
	Inventory.add(bag, "gold_chain", 2)

	check(report, "le coffre ignore ce qui entre dans le sac", #stash.slots == 0)
	check(report, "valeur du sac", Inventory.value(bag) == 3 * 500 + 2 * 350, tostring(Inventory.value(bag)))

	-- Extraction : le sac se vide dans le coffre.
	local summary = Inventory.transfer(bag, stash)
	check(report, "tout est transfere", #summary.moved == 2, `{#summary.moved} piles`)
	check(report, "rien n'est laisse", #summary.leftBehind == 0)
	check(report, "sac vide apres extraction", #bag.slots == 0)
	check(report, "coffre credite", Inventory.count(stash, "military_battery") == 3)
	check(report, "valeur passee au coffre", Inventory.value(stash) == 3 * 500 + 2 * 350)
	check(report, "valeur du sac retombee a 0", Inventory.value(bag) == 0)

	-- Coffre presque plein : le surplus reste dans le sac plutot que de
	-- disparaitre.
	local small = Inventory.new(3)
	local full = Inventory.new(40)
	Inventory.add(full, "military_battery", 1)
	Inventory.add(full, "scrap_metal", 6)

	local partial = Inventory.transfer(full, small)
	check(report, "transfert partiel : quelque chose passe", #partial.moved >= 1, `{#partial.moved} deplacees`)
	check(report, "transfert partiel : le reste demeure", #partial.leftBehind >= 1, `{#partial.leftBehind} restantes`)
	check(report, "rien n'est detruit", (function()
		local before = 1 * 2 + 6 * 1
		return Inventory.weight(full) + Inventory.weight(small) == before
	end)(), `sac={Inventory.weight(full)} coffre={Inventory.weight(small)}`)

	-- Mort : le sac disparait, le coffre est intact.
	local deathBag = Inventory.new(40)
	local deathStash = Inventory.new(600)
	Inventory.add(deathStash, "black_box", 1)
	Inventory.add(deathBag, "graphics_card", 1)

	local lostValue = Inventory.value(deathBag)
	Inventory.clear(deathBag)

	check(report, "perte chiffree a la valeur du sac", lostValue == 1800, tostring(lostValue))
	check(report, "sac vide apres mort", #deathBag.slots == 0)
	check(report, "coffre intact apres mort", Inventory.count(deathStash, "black_box") == 1)
	check(report, "valeur du coffre preservee", Inventory.value(deathStash) == 6000)
end

-- ----------------------------------------------------------------- Run ---

function InventoryTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	check(report, "ItemDatabase peuplee", ItemDatabase.count() >= 8, `{ItemDatabase.count()} items`)
	check(report, "military_battery conforme a la spec", (function()
		local def = ItemDatabase.get("military_battery")
		return def ~= nil
			and def.rarity == "Rare"
			and def.value == 500
			and def.weight == 2
	end)())

	testAdding(report)
	testRemoving(report)
	testCapacity(report)
	testInvalidQuantities(report)
	testDuplicateRequests(report)
	testRaidAndStash(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return InventoryTests
