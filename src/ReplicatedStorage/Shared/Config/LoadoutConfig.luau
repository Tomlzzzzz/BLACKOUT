--!strict
-- Barre d'equipement a cinq emplacements.
--
-- La maquette impose l'ordre : arme principale, arme de poing, medical,
-- grenade, utilitaire. Ce n'est pas un inventaire — c'est une VUE sur le sac
-- de raid, filtree par categorie.
--
-- Consequence importante : aucun etat de slot n'est stocke cote client, et
-- rien n'est duplique. LoadoutService relit le sac (InventoryService, seul
-- proprietaire) et projette son contenu sur ces cinq cases. Un joueur qui
-- perd son sac perd sa barre, sans qu'aucun code n'ait a s'en occuper.

local LoadoutConfig = {}

-- `accepts` liste les items qui peuvent occuper l'emplacement, dans l'ordre
-- de preference : le premier present dans le sac gagne la case.
--
-- `counter` decide de ce qui s'affiche sous l'icone :
--   ammo      munitions du chargeur sur reserve, pour les armes
--   quantity  nombre d'exemplaires, prefixe x
--   percent   pourcentage, pour la batterie
LoadoutConfig.slots = {
	{
		index = 1,
		key = "primary",
		label = "PRIMARY",
		counter = "ammo",
		accepts = { "rifle_ak" },
	},
	{
		index = 2,
		key = "secondary",
		label = "SECONDARY",
		counter = "ammo",
		accepts = { "pistol_mk1" },
	},
	{
		index = 3,
		key = "medical",
		label = "MEDICAL",
		counter = "quantity",
		accepts = { "medkit", "bandage", "painkillers" },
	},
	{
		index = 4,
		key = "grenade",
		label = "GRENADE",
		counter = "quantity",
		-- Aucune grenade au catalogue pour l'instant. L'emplacement existe et
		-- reste vide : la maquette le montre, et une case vide est une
		-- information honnete la ou une case masquee serait un trou.
		accepts = {},
	},
	{
		index = 5,
		key = "utility",
		label = "UTILITY",
		counter = "percent",
		accepts = { "military_battery", "keycard_blue" },
	},
}

-- Seuls ces emplacements peuvent devenir l'arme active. Demander a equiper
-- une trousse de soin ne doit pas vider les mains du joueur.
LoadoutConfig.equippable = { primary = true, secondary = true }

-- Anti-rafale sur RequestSlot, en secondes. Un client qui maintient une
-- touche enverrait sinon soixante demandes par seconde.
LoadoutConfig.requestCooldown = 0.12

return LoadoutConfig
