--!strict
-- Reglages du HUD partages client/serveur.
--
-- Tout ce qui est purement visuel (palette, corps de texte, positions) vit
-- dans Client/UI/HUD/Theme : c'est de la presentation, le serveur n'a rien a
-- en savoir. Ne restent ici que les valeurs dont les DEUX cotes ont besoin,
-- et les seuils de reponse qui doivent rester tunables sans toucher au code.

local HudConfig = {}

-- ------------------------------------------------ Retour de degats ------
--
-- La severite est classee SERVEUR, au moment ou les degats sont appliques :
-- lui seul connait le coup reellement encaisse. Le client recoit un verdict
-- et l'illustre. S'il classait lui-meme, il devrait redecouvrir la vie
-- d'avant le coup, qu'il n'a pas de facon fiable.
--
-- Seuils exprimes en fraction de la vie maximale perdue d'un seul coup.
HudConfig.damage = {
	heavyAbove = 0.12,
	criticalAbove = 0.25,

	-- Toute perte qui laisse le joueur sous ce ratio est critique, quelle que
	-- soit son ampleur : le dernier coup avant la mort doit se voir.
	criticalBelowHealth = 0.25,
}

-- --------------------------------------------------- Reactivite --------
--
-- Le HUD est evenementiel. Ces cadences ne concernent que ce qui doit etre
-- echantillonne faute d'evenement : la boussole suit la camera, la distance
-- de sortie suit le deplacement.
HudConfig.sampleRate = {
	compass = 0.05,
	derived = 0.4,
}

-- ------------------------------------------------- Responsive ----------
--
-- On ne reduit PAS le HUD entier sur petit ecran : on retire du secondaire.
-- Ces largeurs, en pixels, decident du profil applique.
--
--   full     tout est affiche
--   compact  boussole et bandeau de zone retires, panneaux resserres
--   minimal  ne restent que contrat, menace, vitaux, arme, interaction
HudConfig.breakpoints = {
	compactBelow = 1000,
	minimalBelow = 700,
}

-- Echelle de base par profil. Elle corrige la densite, elle ne remplace pas
-- le retrait d'information.
HudConfig.scale = {
	full = 1,
	compact = 0.94,
	minimal = 0.9,
}

-- Hauteur de reference pour l'echelle automatique. Un ecran deux fois plus
-- haut ne doit pas afficher un HUD deux fois plus petit.
HudConfig.referenceHeight = 1080

-- Facteur global applique par-dessus l'echelle automatique.
--
-- Un seul chiffre pour grossir ou reduire TOUT le HUD d'un coup, sans
-- retoucher une seule position. C'est LE reglage a bouger si l'ensemble
-- parait trop petit ou trop envahissant — et le seul : j'avais d'abord
-- touche aussi au plancher ci-dessous, et les deux effets se multipliaient
-- pour donner +38 % la ou on en voulait dix.
HudConfig.globalScale = 1.12

-- Bornes de l'echelle automatique. Le plancher protege les tres petites
-- fenetres ; il ne sert pas a regler la taille generale.
HudConfig.densityRange = { min = 0.75, max = 1.35 }

return HudConfig
