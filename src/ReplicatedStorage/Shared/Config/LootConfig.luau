--!strict
-- Configuration du butin. Tout se regle ici : aucune valeur de loot ne doit
-- apparaitre en dur dans LootService.

local Types = require(script.Parent.Parent.Types)

type ItemId = Types.ItemId
type LootEntry = Types.LootEntry
type Rarity = Types.Rarity

local LootConfig = {}

-- Poids global par rarete. Ce sont des poids relatifs, pas des pourcentages.
-- Un item Mythic est mille fois moins probable qu'un Common a poids local
-- egal : c'est ce rapport qui fait exister les paliers, pas leur nom.
LootConfig.rarityWeights = {
	Common = 1000,
	Uncommon = 400,
	Rare = 120,
	Epic = 30,
	Legendary = 6,
	Mythic = 1,
} :: { [Rarity]: number }

-- Tables de butin. Le poids d'une entree dose l'item *a l'interieur* de sa
-- table ; le poids de rarete s'applique par-dessus. Poids effectif :
--   entry.weight * rarityWeights[def.rarity]
LootConfig.tables = {
	Medical = {
		{ id = "bandage", weight = 10, min = 1, max = 3 },
		{ id = "painkillers", weight = 6, min = 1, max = 2 },
		{ id = "medkit", weight = 4, min = 1, max = 1 },
	} :: { LootEntry },

	Scrap = {
		{ id = "scrap_metal", weight = 12, min = 2, max = 6 },
		{ id = "weapon_parts", weight = 5, min = 1, max = 2 },
		{ id = "armor_plate", weight = 4, min = 1, max = 1 },
		{ id = "bandage", weight = 3, min = 1, max = 1 },
		{ id = "ammo_9mm", weight = 8, min = 10, max = 30 },
		{ id = "pistol_mk1", weight = 2, min = 1, max = 1 },
	} :: { LootEntry },

	Valuables = {
		{ id = "gold_chain", weight = 8, min = 1, max = 2 },
		{ id = "graphics_card", weight = 6, min = 1, max = 1 },
		{ id = "black_box", weight = 4, min = 1, max = 1 },
		{ id = "prototype_core", weight = 2, min = 1, max = 1 },
	} :: { LootEntry },

	Military = {
		{ id = "ammo_762", weight = 14, min = 15, max = 45 },
		{ id = "military_battery", weight = 7, min = 1, max = 2 },
		{ id = "keycard_blue", weight = 3, min = 1, max = 1 },
		{ id = "weapon_parts", weight = 6, min = 1, max = 3 },
		{ id = "rifle_ak", weight = 5, min = 1, max = 1 },
		{ id = "ammo_9mm", weight = 6, min = 20, max = 50 },
	} :: { LootEntry },
}

-- Types de conteneurs physiques.
--   rolls    : nombre de tirages a l'ouverture
--   cooldown : secondes avant re-remplissage, apres avoir ete vide
--   range    : distance max autorisee, revalidee serveur
--   size     : dimensions de la piece posee dans le monde
LootConfig.containers = {
	Crate = {
		tableId = "Scrap",
		rolls = { min = 1, max = 3 },
		cooldown = 90,
		range = 12,
		size = Vector3.new(3, 2, 2),
		color = Color3.fromRGB(120, 90, 55),
		label = "Caisse",
		-- Cle de localisation, lue par le ProximityPrompt.
		labelKey = "prompt.crate",
	},

	MedBox = {
		tableId = "Medical",
		rolls = { min = 1, max = 2 },
		cooldown = 120,
		range = 10,
		size = Vector3.new(2, 1.5, 1.5),
		color = Color3.fromRGB(200, 60, 60),
		label = "Trousse de secours",
		-- Cle de localisation, lue par le ProximityPrompt.
		labelKey = "prompt.medical",
	},

	Safe = {
		tableId = "Valuables",
		rolls = { min = 1, max = 2 },
		cooldown = 300,
		range = 8,
		size = Vector3.new(2, 2, 2),
		color = Color3.fromRGB(70, 70, 80),
		label = "Coffre",
		-- Cle de localisation, lue par le ProximityPrompt.
		labelKey = "prompt.safe",
	},

	Armory = {
		tableId = "Military",
		rolls = { min = 2, max = 4 },
		cooldown = 240,
		range = 10,
		size = Vector3.new(4, 2.5, 2),
		color = Color3.fromRGB(60, 80, 60),
		label = "Casier militaire",
		-- Cle de localisation, lue par le ProximityPrompt.
		labelKey = "prompt.armory",
	},
}

-- Points de spawn de secours, utilises quand Workspace.LootSpawns ne
-- contient aucun marqueur. Ils rendent le systeme demontrable sur une carte
-- vide ; une vraie carte remplacera ca par des marqueurs poses a la main.
LootConfig.fallbackSpawns = {
	{ kind = "Crate", position = Vector3.new(12, 3, 0) },
	{ kind = "Crate", position = Vector3.new(-12, 3, 6) },
	{ kind = "MedBox", position = Vector3.new(0, 3, 14) },
	{ kind = "Safe", position = Vector3.new(18, 3, -10) },
	{ kind = "Armory", position = Vector3.new(-18, 3, -14) },
}

-- Attribut lu sur les marqueurs de Workspace.LootSpawns pour choisir le
-- type de conteneur. Absent ou inconnu -> defaultKind.
LootConfig.kindAttribute = "LootKind"
LootConfig.defaultKind = "Crate"

return LootConfig
