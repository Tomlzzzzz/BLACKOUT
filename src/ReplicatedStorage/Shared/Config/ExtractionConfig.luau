--!strict
local Types = require(script.Parent.Parent.Types)

type ExtractionZoneDef = Types.ExtractionZoneDef

local ExtractionConfig = {
	defaultHoldTime = 12,
	defaultRadius = 18,

	-- Nombre de zones ouvertes simultanement. Les autres restent fermees
	-- pour forcer la rotation entre parties.
	activeZonesPerRaid = 2,

	-- Delai avant que la moindre sortie s'ouvre, en secondes.
	--
	-- Le GDD raconte des Scavengers largues dans la zone : ils ne repartent
	-- pas quand ils veulent, l'entreprise vient les chercher a une heure
	-- convenue. Vingt minutes sur une fenetre de vingt-cinq laissent cinq
	-- minutes pour rejoindre une sortie — c'est court, et c'est le but : la
	-- pression de fin de contrat devient le sommet de la partie.
	--
	-- ATTENTION : ce delai est couple a Config.Match.windowDuration. Allonger
	-- l'un sans l'autre rend l'extraction impossible ou triviale.
	openAfter = 20 * 60,

	-- Cadence d'evaluation. Plus fin que ca ne change rien de perceptible
	-- et multiplie le cout serveur par joueur.
	tickRate = 0.25,

	-- Cadence de notification du client. Decorrelee du tick : la barre de
	-- progression n'a pas besoin de quatre mises a jour par seconde.
	progressInterval = 0.5,

	-- Indexe par le Name du modele pose dans Workspace.ExtractionZones.
	zones = {} :: { [string]: ExtractionZoneDef },

	-- Zones de secours, utilisees quand Workspace.ExtractionZones est vide.
	-- Meme logique que les spawns de butin : le systeme doit rester
	-- demontrable sur une carte nue.
	fallbackZones = {
		-- Noms affiches par le HUD, en anglais comme tout le HUD v2, et
		-- nommes comme des LIEUX plutot que comme des points cardinaux :
		-- « WEST TUNNEL » se retient, « Ouest » non.
		{ name = "NORTH GATE", position = Vector3.new(0, 3, -70), radius = 18, holdTime = 12 },
		{ name = "EAST DOCKS", position = Vector3.new(70, 3, 0), radius = 18, holdTime = 12 },
		{ name = "SOUTH YARD", position = Vector3.new(0, 3, 70), radius = 16, holdTime = 15 },
		{ name = "WEST TUNNEL", position = Vector3.new(-70, 3, 0), radius = 20, holdTime = 10 },
	},

	-- Ou le joueur atterrit apres extraction reussie.
	safePosition = Vector3.new(0, 200, 0),
}

-- ------------------------------------------------- Aspect des sorties ----
--
-- UNE SORTIE FERMEE NE DOIT PAS SE VOIR.
--
-- Premiere version : un disque de neon rouge de quarante studs de large,
-- opaque a 40 %, pose a plat sur le sol. Resultat en jeu — quatre soleils
-- rouges visibles d'un bout a l'autre de la carte, qui ecrasaient tout le
-- reste de l'image et annoncaient pendant vingt minutes des portes qu'on ne
-- pouvait pas franchir.
--
-- Le principe retenu : fermee, la sortie est une TACHE au sol qu'on ne
-- remarque qu'en marchant dessus. Ouverte, elle allume une balise verticale
-- — c'est elle qui se voit de loin, pas le disque.
ExtractionConfig.visual = {
	-- Dalle au sol.
	closedTransparency = 0.94,
	openTransparency = 0.82,
	closedColor = Color3.fromRGB(96, 52, 52),
	openColor = Color3.fromRGB(80, 220, 120),

	-- Balise verticale, allumee seulement quand la sortie est franchissable.
	-- Etroite et haute : on la lit comme un signal, pas comme un mur.
	beaconWidth = 2.2,
	beaconHeight = 90,
	beaconTransparency = 0.45,
}

return ExtractionConfig
