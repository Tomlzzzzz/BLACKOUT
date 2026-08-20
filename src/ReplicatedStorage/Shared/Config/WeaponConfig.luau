--!strict
-- Armes et regles de tir.
--
-- Les armes sont indexees par identifiant d'item : ce que le joueur equipe
-- dans son inventaire determine ce qu'il tire. Un item absent d'ici n'est
-- pas une arme, point.

local WeaponConfig = {}

WeaponConfig.weapons = {
	pistol_mk1 = {
		displayName = "Pistolet MK1",
		damage = 22,
		-- Secondes entre deux tirs.
		fireRate = 0.28,
		range = 180,
		magazine = 12,
		reloadTime = 1.6,
		ammoId = "ammo_9mm",
		-- Affichage seul : le HUD v2 montre le calibre et le mode de tir.
		-- Aucune regle de jeu ne les lit.
		caliber = "9x19mm",
		fireMode = "SEMI-AUTO",
		-- Dispersion en degres, appliquee PAR LE SERVEUR : laisser le
		-- client tirer au hasard reviendrait a le laisser choisir de ne pas
		-- disperser du tout.
		spread = 1.2,
	},

	rifle_ak = {
		displayName = "Fusil 7.62",
		damage = 34,
		fireRate = 0.12,
		range = 300,
		magazine = 30,
		reloadTime = 2.6,
		ammoId = "ammo_762",
		caliber = "7.62x39mm",
		fireMode = "FULL-AUTO",
		spread = 2.4,
	},
}

-- Validation des tirs entrants. Toutes ces valeurs sont des garde-fous
-- serveur : elles n'ameliorent pas le jeu, elles empechent de le tricher.
WeaponConfig.validation = {
	-- Ecart tolere entre l'origine annoncee par le client et la position
	-- reelle de son personnage. Couvre la latence et l'interpolation, pas
	-- un tir depuis l'autre bout de la carte.
	maxOriginDrift = 14,

	-- Plafond absolu de tirs par seconde, toutes armes confondues. La
	-- cadence de l'arme est deja verifiee ; ceci borne le cas ou une arme
	-- serait mal configuree.
	maxShotsPerSecond = 20,

	-- Nombre d'identifiants de tir memorises contre le rejeu.
	requestHistory = 64,
}

-- Arme donnee au joueur qui n'a rien, pour qu'il ne soit jamais totalement
-- desarme. Nil pour desactiver.
WeaponConfig.defaultWeapon = "pistol_mk1"

return WeaponConfig
