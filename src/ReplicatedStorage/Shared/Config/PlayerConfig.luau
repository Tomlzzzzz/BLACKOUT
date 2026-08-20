--!strict
-- Configuration du joueur : endurance et etat courant.

local PlayerConfig = {}

PlayerConfig.stamina = {
	max = 100,

	-- Consommation en SPRINT, par seconde. 8/s = douze secondes de course a
	-- pleine charge, de quoi rompre un contact sans traverser la carte.
	drainPerSecond = 8,

	-- Recuperation au repos, par seconde. Plus lente que la consommation :
	-- courir doit se payer.
	regenPerSecond = 7,

	-- Delai apres le dernier effort avant que la recuperation reprenne.
	regenDelay = 1.2,

	-- Vitesse au-dela de laquelle on considere qu'il y a effort. Mesuree sur
	-- la velocite reelle du personnage cote serveur, jamais sur une
	-- declaration du client : un client modifie annoncerait qu'il marche en
	-- sprintant.
	--
	-- DOIT RESTER AU-DESSUS DE `walkSpeed`. Il valait 12 pour une marche a
	-- 16 : le simple fait d'avancer comptait comme un effort, la barre se
	-- vidait en permanence et le sprint n'existait pas. C'est ce qui donnait
	-- l'impression d'une endurance qui fond.
	moveThreshold = 14,

	-- Vitesse au-dela de laquelle on considere que le joueur SE DEPLACE.
	--
	-- Rien a voir avec `moveThreshold` : ce seuil-la separait l'effort de
	-- la marche quand la consommation se decidait sur la vitesse mesuree.
	-- Celui-ci ne sert plus qu'a distinguer « je cours » de « je tiens la
	-- touche de course sans avancer ». Volontairement tres bas.
	movingAt = 1,

	-- Vitesse imposee a bout de souffle.
	exhaustedSpeed = 6,

	-- Seuil sous lequel on est considere epuise.
	exhaustedBelow = 5,

	tickRate = 0.25,
}

-- ------------------------------------------------------------ Sprint ----
--
-- Le sprint n'existait pas : l'endurance se vidait toute seule en marchant,
-- sans qu'aucune touche ne la depense. Elle mesurait donc le temps passe
-- debout, pas un choix du joueur.
--
-- Maintenant c'est une DECISION : on court plus vite, on se fatigue, et on
-- fait du bruit. Trois consequences pour une touche.
PlayerConfig.sprint = {
	-- VITESSES.
	--
	-- 16 est la valeur par defaut de Roblox, pensee pour des jeux ou l'on
	-- traverse une carte vite. Ici elle donnait une marche de personnage
	-- presse, ce qui va contre tout le reste : on est cense avancer dans le
	-- noir en ecoutant, pas arpenter.
	--
	-- 12 pour la marche, 19 pour la course. Le rapport de 1.6 compte autant
	-- que les valeurs : c'est lui qui fait que sprinter se SENT, sans que la
	-- marche devienne penible.
	--
	-- `moveThreshold` (14) reste entre les deux : c'est ce qui distingue
	-- l'effort de la marche pour l'endurance. Le deplacer sans le regarder
	-- casse l'endurance en silence — c'est deja arrive.
	walkSpeed = 12,
	sprintSpeed = 19,
}

-- ------------------------------------------------------------- Accroupi --
--
-- S'accroupir doit COUTER et RAPPORTER, sinon c'est une pose.
--
-- Ce qu'on perd : la moitie de la vitesse. Traverser une zone accroupi prend
-- deux fois plus longtemps, et le temps est la ressource que la fenetre de
-- contrat rationne.
--
-- Ce qu'on gagne : les creatures reperent de bien plus pres, et le bruit
-- fait monter la menace deux fois moins vite. C'est ce qui en fait une
-- decision — avancer vite en se faisant voir, ou passer lentement.
PlayerConfig.crouch = {
	speed = 5.5,

	-- Abaissement de la camera, en studs.
	cameraDrop = 1.7,

	-- Portee de detection des creatures, multipliee. 0.5 = repere a moitie
	-- moins loin.
	detectionMultiplier = 0.5,

	-- Menace generee, multipliee. On ne l'annule pas : rester tapi ne rend
	-- pas invisible, ca ralentit seulement l'attention.
	threatMultiplier = 0.4,

	-- Menace ajoutee par seconde de course. Courir en zone hostile s'entend.
	threatPerSecond = 0.25,
}

return PlayerConfig
