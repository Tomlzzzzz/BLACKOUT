--!strict
-- Registre des items : source unique de verite pour rarete, poids et valeur.
--
-- Un inventaire ne stocke qu'un id et une quantite. Tout le reste se resout
-- ici, cote serveur, ce qui rend structurellement impossible qu'un client
-- annonce une batterie pesant zero ou valant un million.

local Types = require(script.Parent.Types)

type ItemDef = Types.ItemDef
type ItemId = Types.ItemId

local ItemDatabase = {}

local ITEMS: { [ItemId]: ItemDef } = {
	military_battery = {
		id = "military_battery",
		name = "Batterie militaire",
		rarity = "Rare",
		value = 500,
		weight = 2,
		stackable = true,
		maxStack = 4,
	},

	scrap_metal = {
		id = "scrap_metal",
		name = "Ferraille",
		rarity = "Common",
		value = 25,
		weight = 1,
		stackable = true,
		maxStack = 20,
	},

	bandage = {
		id = "bandage",
		name = "Bandage",
		rarity = "Common",
		value = 40,
		weight = 0.5,
		stackable = true,
		maxStack = 10,
	},

	painkillers = {
		id = "painkillers",
		name = "Antidouleurs",
		rarity = "Uncommon",
		value = 120,
		weight = 0.3,
		stackable = true,
		maxStack = 6,
	},

	gold_chain = {
		id = "gold_chain",
		name = "Chaine en or",
		rarity = "Uncommon",
		value = 350,
		weight = 0.2,
		stackable = true,
		maxStack = 8,
	},

	graphics_card = {
		id = "graphics_card",
		name = "Carte graphique",
		rarity = "Epic",
		value = 1800,
		weight = 1,
		stackable = true,
		maxStack = 2,
	},

	-- Non empilable : chaque exemplaire occupe sa propre pile, meme si le
	-- poids total resterait sous la capacite.
	keycard_blue = {
		id = "keycard_blue",
		name = "Carte d'acces bleue",
		rarity = "Rare",
		value = 0,
		weight = 0.1,
		stackable = false,
		maxStack = 1,
	},

	black_box = {
		id = "black_box",
		name = "Boite noire",
		rarity = "Legendary",
		value = 6000,
		weight = 3,
		stackable = false,
		maxStack = 1,
	},

	medkit = {
		id = "medkit",
		name = "Trousse de soin",
		rarity = "Rare",
		value = 600,
		weight = 1.5,
		stackable = true,
		maxStack = 3,
	},

	ammo_762 = {
		id = "ammo_762",
		name = "Munitions 7.62",
		rarity = "Common",
		value = 8,
		weight = 0.02,
		stackable = true,
		maxStack = 120,
	},

	armor_plate = {
		id = "armor_plate",
		name = "Plaque balistique",
		rarity = "Uncommon",
		value = 200,
		weight = 3,
		stackable = true,
		maxStack = 3,
	},

	weapon_parts = {
		id = "weapon_parts",
		name = "Pieces d'armurerie",
		rarity = "Uncommon",
		value = 220,
		weight = 0.8,
		stackable = true,
		maxStack = 6,
	},

	-- Armes. Ce sont des items comme les autres : c'est l'emplacement
	-- equipe de l'inventaire qui determine ce que le joueur tire.
	pistol_mk1 = {
		id = "pistol_mk1",
		name = "Pistolet MK1",
		rarity = "Common",
		value = 180,
		weight = 1.2,
		stackable = false,
		maxStack = 1,
	},

	rifle_ak = {
		id = "rifle_ak",
		name = "Fusil 7.62",
		rarity = "Rare",
		value = 1400,
		weight = 3.5,
		stackable = false,
		maxStack = 1,
	},

	ammo_9mm = {
		id = "ammo_9mm",
		name = "Munitions 9mm",
		rarity = "Common",
		value = 5,
		weight = 0.01,
		stackable = true,
		maxStack = 150,
	},

	-- Seul item Mythic : sans lui, le palier ne serait qu'une etiquette.
	prototype_core = {
		id = "prototype_core",
		name = "Noyau prototype",
		rarity = "Mythic",
		value = 25000,
		weight = 1,
		stackable = false,
		maxStack = 1,
	},
}

-- Gel profond : une definition modifiee a chaud fausserait tous les calculs
-- de poids deja effectues, sans laisser de trace.
for _, def in ITEMS do
	table.freeze(def)
end
table.freeze(ITEMS)

function ItemDatabase.get(id: ItemId): ItemDef?
	if type(id) ~= "string" then
		return nil
	end
	return ITEMS[id]
end

function ItemDatabase.has(id: ItemId): boolean
	return ItemDatabase.get(id) ~= nil
end

function ItemDatabase.all(): { [ItemId]: ItemDef }
	return ITEMS
end

function ItemDatabase.count(): number
	local total = 0
	for _ in ITEMS do
		total += 1
	end
	return total
end

return ItemDatabase
