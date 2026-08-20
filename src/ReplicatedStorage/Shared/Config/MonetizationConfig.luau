--!strict
-- Catalogue des produits. Declaratif uniquement : ce fichier dit CE QUI est
-- vendu et CE QUE ca donne ; comment l'accorder appartient a
-- Server/Monetization/Grants.luau.
--
-- LES IDENTIFIANTS SONT A ZERO. Ce ne sont pas des valeurs inventees : un
-- identifiant Roblox se cree dans le tableau de bord du jeu, et en fabriquer
-- un ferait pointer un achat reel vers le produit de quelqu'un d'autre.
-- Remplace les zeros par les vrais identifiants une fois les produits crees
-- sur create.roblox.com. Tant qu'un identifiant vaut 0, le service refuse
-- de traiter le produit et le signale au demarrage.

local MonetizationConfig = {}

-- --------------------------------------------------------------- Regles ---
--
-- Ces regles sont APPLIQUEES a l'execution par Grants.luau, pas seulement
-- documentees. Un produit qui les enfreint est refuse au moment ou on tente
-- de l'accorder, et l'echec est journalise.
MonetizationConfig.rules = {
	-- Aucun produit ne peut deposer un objet dans un inventaire. Vendre du
	-- materiel dans un extraction shooter, c'est vendre de la puissance.
	allowItemGrants = false,

	-- Aucun produit ne peut modifier vie, degats, vitesse, portee ni
	-- capacite de detection.
	allowStatBoosts = false,

	-- Aucun produit n'agit pendant un raid en cours.
	allowInRaidEffects = false,

	-- Plafond du multiplicateur de credits. Un multiplicateur reste par
	-- nature une acceleration d'acces a l'equipement : le plafond limite
	-- l'ecart, il ne le supprime pas.
	maxCreditMultiplier = 1.5,

	-- Duree maximale d'un bonus temporaire, en secondes.
	maxBoostDuration = 7 * 24 * 3600,
}

-- ---------------------------------------------------- Produits developpeur ---
--
-- Consommables, achetables plusieurs fois. `grant` decrit l'effet de facon
-- declarative ; Grants.luau sait interpreter chaque `type`.
MonetizationConfig.developerProducts = {
	BlackTokens = {
		id = 0, -- <-- identifiant du produit developpeur
		displayName = "Black Tokens",
		description = "500 Black Tokens, la monnaie cosmetique.",
		grant = {
			type = "currency",
			currency = "BlackTokens",
			amount = 500,
		},
	},

	CreditBoost = {
		id = 0, -- <-- identifiant du produit developpeur
		displayName = "Credit Boost",
		description = "+50 % de credits gagnes pendant 24 h.",
		grant = {
			type = "boost",
			boostId = "credits",
			multiplier = 1.5,
			duration = 24 * 3600,
		},
	},

	CosmeticBundle = {
		id = 0, -- <-- identifiant du produit developpeur
		displayName = "Cosmetic Bundle",
		description = "Trois cosmetiques exclusifs.",
		grant = {
			type = "cosmetics",
			cosmeticIds = { "skin_urban", "patch_raven", "charm_dogtag" },
		},
	},
}

-- ------------------------------------------------------------ Gamepasses ---
--
-- Achat unique, avantage permanent. Verifies a la connexion.
MonetizationConfig.gamepasses = {
	StashExpansion = {
		id = 0, -- <-- identifiant du gamepass
		displayName = "Stash Expansion",
		description = "+300 de capacite de coffre.",
		-- Du rangement, pas de la puissance : ce que le joueur peut stocker
		-- entre deux raids ne change rien a ce qu'il emporte dedans, qui
		-- reste plafonne par BASE_CARRY_WEIGHT.
		grant = {
			type = "stashCapacity",
			bonus = 300,
		},
	},

	OperatorSkin = {
		id = 0, -- <-- identifiant du gamepass
		displayName = "Operator Skin",
		description = "Apparence exclusive.",
		grant = {
			type = "cosmetics",
			cosmeticIds = { "skin_operator" },
		},
	},
}

-- Nombre d'identifiants d'achat memorises par profil, pour l'idempotence
-- des recus. Roblox ne rejoue jamais un recu tres ancien ; borner evite que
-- le profil grossisse indefiniment.
MonetizationConfig.purchaseHistoryLimit = 200

return MonetizationConfig
