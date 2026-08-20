--!strict
-- Generation de butin, pure.
--
-- Comme le coeur d'inventaire : aucune dependance au monde, aucun Instance,
-- aucun Player. On passe un Random explicite, ce qui rend les tirages
-- reproductibles et donc testables.
--
-- Deux etages de ponderation :
--   poids_effectif = entry.weight * rarityWeights[def.rarity]
-- Le poids local dose l'item dans sa table, le poids de rarete s'applique
-- par-dessus. Une entree dont l'item est inconnu de l'ItemDatabase pese
-- zero — elle ne peut pas sortir, mais elle ne casse pas la table non plus.

local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)
local ItemDatabase = require(script.Parent.ItemDatabase)
local WeightedRandom = require(script.Parent.Utils.WeightedRandom)

type ItemStack = Types.ItemStack
type LootEntry = Types.LootEntry

local Loot = {}

-- Poids reel d'une entree, rarete comprise. Zero si l'item n'existe pas ou
-- si sa rarete n'a pas de poids configure.
function Loot.effectiveWeight(entry: LootEntry): number
	local def = ItemDatabase.get(entry.id)
	if not def then
		return 0
	end

	local rarityWeight = Config.Loot.rarityWeights[def.rarity]
	if not rarityWeight or rarityWeight <= 0 then
		return 0
	end

	return entry.weight * rarityWeight
end

-- Un tirage dans une table. Retourne nil si la table est inconnue, vide, ou
-- ne contient que des entrees de poids nul.
function Loot.rollOne(tableId: string, rng: Random?): ItemStack?
	local entries = Config.Loot.tables[tableId]
	if not entries or #entries == 0 then
		return nil
	end

	-- WeightedRandom lit un champ `weight` : on lui donne une vue ponderee
	-- par rarete plutot que les poids bruts de la table.
	local weighted = {}
	for _, entry in entries do
		table.insert(weighted, {
			entry = entry,
			weight = Loot.effectiveWeight(entry),
		})
	end

	local picked = WeightedRandom.pick(weighted, rng)
	if not picked then
		return nil
	end

	local entry = picked.entry
	local low = math.min(entry.min, entry.max)
	local high = math.max(entry.min, entry.max)
	local quantity = if rng then rng:NextInteger(low, high) else math.random(low, high)

	return { id = entry.id, quantity = quantity }
end

-- Plusieurs tirages, fusionnes par item pour ne pas rendre trois piles
-- separees de la meme chose.
function Loot.rollMany(tableId: string, count: number, rng: Random?): { ItemStack }
	local merged: { [string]: number } = {}
	local order: { string } = {}

	for _ = 1, math.max(0, count) do
		local stack = Loot.rollOne(tableId, rng)
		if stack then
			if not merged[stack.id] then
				merged[stack.id] = 0
				table.insert(order, stack.id)
			end
			merged[stack.id] += stack.quantity
		end
	end

	local out: { ItemStack } = {}
	for _, id in order do
		table.insert(out, { id = id, quantity = merged[id] })
	end
	return out
end

-- Contenu complet d'un conteneur, selon son type.
function Loot.rollContainer(kindId: string, rng: Random?): { ItemStack }
	local kind = Config.Loot.containers[kindId]
	if not kind then
		return {}
	end

	local low = math.min(kind.rolls.min, kind.rolls.max)
	local high = math.max(kind.rolls.min, kind.rolls.max)
	local rolls = if rng then rng:NextInteger(low, high) else math.random(low, high)

	return Loot.rollMany(kind.tableId, rolls, rng)
end

function Loot.getContainerKind(kindId: string)
	return Config.Loot.containers[kindId]
end

function Loot.hasTable(tableId: string): boolean
	return Config.Loot.tables[tableId] ~= nil
end

return Loot
