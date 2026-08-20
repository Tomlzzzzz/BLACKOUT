--!strict
-- Coeur d'inventaire, pur.
--
-- Aucune dependance a Player, a un service ou a un remote : ces fonctions
-- operent sur une table brute. C'est ce qui les rend testables sans lancer
-- de partie, et c'est pourquoi InventoryService n'est qu'une enveloppe
-- autour de ce module.
--
-- Invariants tenus par toutes les operations :
--   - une pile ne contient jamais 0 item (elle est retiree)
--   - la quantite d'une pile ne depasse jamais maxStack de sa definition
--   - le poids total ne depasse jamais la capacite
--   - une operation refusee ne modifie rien du tout

local Types = require(script.Parent.Types)
local Constants = require(script.Parent.Constants)
local ItemDatabase = require(script.Parent.ItemDatabase)

type Inventory = Types.Inventory
type InventoryError = Types.InventoryError
type InventoryResult = Types.InventoryResult
type ItemId = Types.ItemId
type ResolvedItem = Types.ResolvedItem

local Inventory = {}

local function succeed(): InventoryResult
	return { ok = true }
end

local function fail(code: InventoryError): InventoryResult
	return { ok = false, error = code }
end

-- Une quantite valide est un entier fini strictement positif.
--
-- NaN et l'infini sont refuses explicitement : ils traversent les
-- comparaisons naives (`quantity > 0` est vrai pour math.huge, faux pour
-- NaN sans lever) et corrompent le poids total en silence.
local function isValidQuantity(quantity: any): boolean
	if type(quantity) ~= "number" then
		return false
	end
	if quantity ~= quantity then
		return false
	end
	if quantity == math.huge or quantity == -math.huge then
		return false
	end
	if quantity <= 0 then
		return false
	end
	if quantity % 1 ~= 0 then
		return false
	end
	return true
end

function Inventory.new(capacity: number?): Inventory
	return {
		slots = {},
		capacity = capacity or Constants.BASE_CARRY_WEIGHT,
	}
end

function Inventory.weight(inv: Inventory): number
	local total = 0
	for _, stack in inv.slots do
		local def = ItemDatabase.get(stack.id)
		if def then
			total += def.weight * stack.quantity
		end
	end
	return total
end

function Inventory.freeWeight(inv: Inventory): number
	return math.max(0, inv.capacity - Inventory.weight(inv))
end

function Inventory.count(inv: Inventory, itemId: ItemId): number
	local total = 0
	for _, stack in inv.slots do
		if stack.id == itemId then
			total += stack.quantity
		end
	end
	return total
end

function Inventory.has(inv: Inventory, itemId: ItemId, quantity: number?): boolean
	local needed = quantity or 1
	if not isValidQuantity(needed) then
		return false
	end
	return Inventory.count(inv, itemId) >= needed
end

function Inventory.add(inv: Inventory, itemId: ItemId, quantity: number): InventoryResult
	local def = ItemDatabase.get(itemId)
	if not def then
		return fail("UNKNOWN_ITEM")
	end
	if not isValidQuantity(quantity) then
		return fail("INVALID_QUANTITY")
	end

	-- Capacite verifiee avant la moindre mutation. Un ajout partiel serait
	-- pire qu'un refus : il laisserait l'inventaire dans un etat que
	-- l'appelant n'a pas demande et ne sait pas defaire.
	if Inventory.weight(inv) + def.weight * quantity > inv.capacity then
		return fail("OVER_CAPACITY")
	end

	local remaining = quantity

	-- On complete d'abord les piles entamees, pour ne pas fragmenter.
	if def.stackable then
		for _, stack in inv.slots do
			if stack.id == itemId and stack.quantity < def.maxStack then
				local moved = math.min(def.maxStack - stack.quantity, remaining)
				stack.quantity += moved
				remaining -= moved
				if remaining == 0 then
					return succeed()
				end
			end
		end
	end

	local perStack = if def.stackable then def.maxStack else 1
	while remaining > 0 do
		local amount = math.min(perStack, remaining)
		table.insert(inv.slots, { id = itemId, quantity = amount })
		remaining -= amount
	end

	return succeed()
end

function Inventory.remove(inv: Inventory, itemId: ItemId, quantity: number): InventoryResult
	if not ItemDatabase.has(itemId) then
		return fail("UNKNOWN_ITEM")
	end
	if not isValidQuantity(quantity) then
		return fail("INVALID_QUANTITY")
	end
	if Inventory.count(inv, itemId) < quantity then
		return fail("NOT_ENOUGH")
	end

	local remaining = quantity

	-- Parcours a l'envers : table.remove pendant l'iteration decale les
	-- indices suivants, et seul le sens descendant y survit.
	for index = #inv.slots, 1, -1 do
		local stack = inv.slots[index]
		if stack.id == itemId then
			local taken = math.min(stack.quantity, remaining)
			stack.quantity -= taken
			remaining -= taken
			if stack.quantity == 0 then
				table.remove(inv.slots, index)
			end
			if remaining == 0 then
				break
			end
		end
	end

	return succeed()
end

-- Vue resolue, pour l'UI et les retours de remote. Les poids et valeurs sont
-- ceux de la pile entiere, pas de l'unite.
function Inventory.contents(inv: Inventory): { ResolvedItem }
	local out: { ResolvedItem } = {}
	for _, stack in inv.slots do
		local def = ItemDatabase.get(stack.id)
		if def then
			table.insert(out, {
				id = def.id,
				name = def.name,
				rarity = def.rarity,
				quantity = stack.quantity,
				weight = def.weight * stack.quantity,
				value = def.value * stack.quantity,
			})
		end
	end
	return out
end

-- Valeur marchande totale. Sert a chiffrer une extraction ou une perte.
function Inventory.value(inv: Inventory): number
	local total = 0
	for _, stack in inv.slots do
		local def = ItemDatabase.get(stack.id)
		if def then
			total += def.value * stack.quantity
		end
	end
	return total
end

-- Deverse `source` dans `destination`, pile par pile.
--
-- C'est l'operation de l'extraction : le sac de raid se vide dans le coffre.
-- Ce qui ne rentre pas reste dans la source — un coffre plein ne detruit
-- rien, il refuse. L'appelant lit `leftBehind` pour le signaler au joueur.
function Inventory.transfer(source: Inventory, destination: Inventory): Types.TransferSummary
	local moved: { Types.ItemStack } = {}
	local leftBehind: { Types.ItemStack } = {}

	-- Parcours descendant : on retire de `source` pendant l'iteration.
	for index = #source.slots, 1, -1 do
		local stack = source.slots[index]
		local result = Inventory.add(destination, stack.id, stack.quantity)
		if result.ok then
			table.insert(moved, { id = stack.id, quantity = stack.quantity })
			table.remove(source.slots, index)
		else
			table.insert(leftBehind, { id = stack.id, quantity = stack.quantity })
		end
	end

	return { moved = moved, leftBehind = leftBehind }
end

function Inventory.clear(inv: Inventory)
	table.clear(inv.slots)
end

return Inventory
