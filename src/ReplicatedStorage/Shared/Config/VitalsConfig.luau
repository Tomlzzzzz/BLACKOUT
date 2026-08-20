--!strict
-- Armure et batterie.
--
-- Deux constantes du HUD v2 qui n'avaient aucune existence dans le jeu. La
-- maquette les affiche toutes les deux ; les brancher sur du vide aurait
-- donne deux jauges decoratives, exactement le genre d'affichage qui apprend
-- au joueur a ne plus lire son interface.
--
-- Les deux sont donc de vraies ressources, serveur, avec un cout et une
-- source de recharge.

local VitalsConfig = {}

-- ------------------------------------------------------------- Armure ----
--
-- L'armure encaisse AVANT la vie et se consomme en le faisant. Elle ne
-- reduit pas les degats en pourcentage : elle les absorbe point pour point
-- jusqu'a rupture. C'est plus lisible pour le joueur — la jauge descend
-- exactement de ce qu'il vient d'encaisser.
VitalsConfig.armor = {
	max = 100,

	-- Fraction des degats detournee vers l'armure tant qu'elle tient. A 0.75,
	-- un coup de 20 retire 15 a l'armure et 5 a la vie : l'armure protege
	-- beaucoup sans rendre invulnerable, et le joueur voit sa vie descendre,
	-- donc il sait qu'il se fait toucher.
	absorption = 0.75,

	-- Armure au deploiement. Zero : c'est un objet a trouver, pas un acquis.
	startingValue = 0,

	-- Points rendus par une plaque ramassee.
	perPlate = 50,

	-- Item qui recharge l'armure. Une plaque ramassee est posee tout de
	-- suite si l'armure n'est pas pleine, et disparait du sac. Pleine, elle
	-- reste du butin ordinaire et se revend — le joueur ne perd jamais rien
	-- a en ramasser une.
	plateItem = "armor_plate",
}

-- ----------------------------------------------------------- Batterie ----
--
-- La ville est en blackout permanent : la lampe est la ressource qui rend
-- ce postulat jouable. Elle se vide toute seule, et l'item qui la recharge
-- est justement celui que le commanditaire reclame le plus souvent.
--
-- C'est la tension que le GDD demande, exprimee en une seule jauge : garder
-- la batterie pour voir, ou la rendre pour la prime.
VitalsConfig.battery = {
	max = 100,

	-- Consommation par seconde, lampe allumee.
	--
	-- La cellule alimente DEUX choses : la lampe et la camera embarquee — ce
	-- que le joueur voit. Elle doit donc tenir bien au-dela d'une partie :
	-- 0.027/s vide une charge pleine en 3700 s, soit un peu plus d'une heure.
	--
	-- Historique du reglage : 0.28/s vidait en six minutes (contrainte de
	-- survie deguisee en jauge), puis 0.05/s en trente-trois minutes. Une
	-- heure est le plancher demande.
	drainPerSecond = 0.027,

	-- Consommation de veille, lampe eteinte : la camera reste alimentee.
	idleDrainPerSecond = 0.005,

	startingValue = 100,

	-- Points rendus par une batterie ramassee.
	perCell = 45,
	cellItem = "military_battery",

	-- Sous ce seuil la jauge passe en ambre, puis en rouge.
	warnBelow = 30,
	criticalBelow = 12,
}

-- ------------------------------------------------------------- Soins ----
--
-- Points de vie rendus par consommable. L'emplacement MEDICAL de la barre
-- pioche dans cette table : un item qui n'y figure pas n'est pas utilisable,
-- ce qui evite qu'ajouter un objet au catalogue le rende soignant par
-- accident.
VitalsConfig.healing = {
	bandage = 25,
	painkillers = 40,
	medkit = 75,
} :: { [string]: number }

-- Cadence de diffusion des vitaux au client. Quatre fois par seconde suffit
-- pour une jauge : la faire suivre l'image coute du reseau pour un pixel.
VitalsConfig.pushRate = 0.25

return VitalsConfig
