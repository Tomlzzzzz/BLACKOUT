--!strict
-- Direction artistique du HUD v2.
--
-- Reference : docs/BLACKOUT_HUD_REFERENCE.png. Toutes les valeurs de ce
-- fichier sont relevees sur cette maquette. Si une couleur ou un corps de
-- texte doit changer, c'est ici et nulle part ailleurs — aucun widget ne
-- declare de couleur en dur.
--
-- Le code couleur de la maquette est explicite et se respecte a la lettre :
--
--   BLANC   information generale, valeurs neutres
--   AMBRE   objectifs et butin
--   VERT    extraction, etats acheves, securite
--   ROUGE   menace, danger, etats critiques
--   GRIS    inactif, secondaire, metadonnees
--   CYAN    information technique rare uniquement
--
-- Une couleur employee hors de son role rend le HUD illisible en une
-- semaine : le joueur apprend le code, puis on le lui casse.

local Theme = {}

-- ------------------------------------------------------------ Palette ---

Theme.color = {
	-- Fonds. La maquette est presque noire, jamais grise : le contraste vient
	-- du fond, pas du texte.
	void = Color3.fromRGB(8, 9, 10),
	panel = Color3.fromRGB(13, 14, 16),
	raised = Color3.fromRGB(20, 22, 25),

	-- Bordures techniques d'un pixel.
	border = Color3.fromRGB(46, 50, 56),
	borderBright = Color3.fromRGB(86, 92, 100),
	separator = Color3.fromRGB(32, 35, 39),

	-- Textes.
	info = Color3.fromRGB(236, 237, 238),
	neutral = Color3.fromRGB(138, 145, 154),
	dim = Color3.fromRGB(92, 98, 106),
	faint = Color3.fromRGB(62, 67, 73),

	-- Roles.
	danger = Color3.fromRGB(226, 58, 58),
	dangerDeep = Color3.fromRGB(140, 24, 24),
	amber = Color3.fromRGB(232, 166, 62),
	extraction = Color3.fromRGB(74, 196, 118),
	cyan = Color3.fromRGB(96, 164, 178),

	-- Jauges de vitaux. La maquette differencie les quatre.
	health = Color3.fromRGB(226, 228, 230),
	armor = Color3.fromRGB(150, 158, 168),
	stamina = Color3.fromRGB(74, 196, 118),
	battery = Color3.fromRGB(206, 196, 86),
}

-- ------------------------------------------------------- Typographie ----
--
-- La maquette utilise une sans-serif technique condensee. RobotoCondensed
-- est l'equivalent Roblox le plus proche pour les libelles ; les grands
-- nombres passent en Oswald, plus etroit et plus affirme, ce qui reproduit
-- le contraste de graisse du visuel.
--
-- RobotoMono est reserve aux relevés strictement techniques (calibre,
-- horodatage) : sa chasse fixe empeche les chiffres de danser.
Theme.font = {
	label = Enum.Font.RobotoCondensed,
	value = Enum.Font.RobotoCondensed,
	hero = Enum.Font.Oswald,
	mono = Enum.Font.RobotoMono,
}

-- Corps de texte, en pixels a la hauteur de reference (1080p).
Theme.size = {
	micro = 11,
	label = 13,
	body = 15,
	value = 20,
	large = 30,
	hero = 58,
}

-- ------------------------------------------------------------ Espaces ---

Theme.space = {
	panelPadding = 12,
	rowGap = 8,
	tight = 4,
}

-- Les panneaux de la maquette n'ont pas de coins arrondis marques : ce sont
-- des cadres techniques. Un rayon de 2 px suffit a casser l'angle vif sans
-- donner l'air d'une carte Roblox.
Theme.panel = {
	background = 0.22,
	border = 1,
	corner = 2,

	-- Equerres d'angle. Presentes sur les panneaux de contrat et de vitaux
	-- dans la maquette : c'est le detail qui les fait lire comme des
	-- instruments plutot que comme des boites.
	bracketLength = 14,
	bracketThickness = 1,
}

-- --------------------------------------------------------- Jauges -------
--
-- Les jauges de la maquette sont SEGMENTEES, pas continues. C'est un choix
-- de lisibilite : on lit « il me reste sept blocs » d'un coup d'oeil, la ou
-- une barre pleine demande d'estimer une longueur.
Theme.bar = {
	segments = 10,
	height = 6,
	gap = 2,
	emptyTransparency = 0.82,
}

-- --------------------------------------------------------- Menace -------
--
-- Cinq etats affiches pour six paliers internes : ALERT et DANGER partagent
-- ELEVATED dans la maquette. Le systeme garde sa granularite, l'affichage
-- reste lisible.
Theme.threat = {
	label = {
		SAFE = "SAFE",
		ALERT = "ELEVATED",
		DANGER = "ELEVATED",
		SEVERE = "HIGH",
		CRITICAL = "CRITICAL",
		HUNT = "THE HUNT",
	},

	color = {
		SAFE = Color3.fromRGB(138, 145, 154),
		ALERT = Color3.fromRGB(232, 166, 62),
		DANGER = Color3.fromRGB(232, 128, 48),
		SEVERE = Color3.fromRGB(226, 58, 58),
		CRITICAL = Color3.fromRGB(240, 40, 40),
		HUNT = Color3.fromRGB(255, 32, 32),
	},

	-- Intensite des effets plein ecran par palier.
	--   vignette  opacite du halo de bord
	--   pulse     vitesse de respiration, en cycles par seconde
	--   flicker   probabilite de scintillement par seconde
	--   scan      opacite des lignes de balayage
	escalation = {
		SAFE = { vignette = 0, pulse = 0, flicker = 0, scan = 0 },
		ALERT = { vignette = 0.06, pulse = 0.5, flicker = 0, scan = 0 },
		DANGER = { vignette = 0.16, pulse = 0.8, flicker = 0, scan = 0 },
		SEVERE = { vignette = 0.3, pulse = 1.2, flicker = 0.3, scan = 0.98 },
		CRITICAL = { vignette = 0.48, pulse = 1.9, flicker = 1.1, scan = 0.965 },
		HUNT = { vignette = 0.72, pulse = 2.8, flicker = 2.6, scan = 0.94 },
	},
}

-- ---------------------------------------------------- Retour de degats --
--
-- La maquette montre trois intensites distinctes. Le rouge ne couvre jamais
-- l'ecran : il mord les bords et se retire vite.
Theme.damage = {
	light = { intensity = 0.34, duration = 0.3 },
	heavy = { intensity = 0.62, duration = 0.45 },
	critical = { intensity = 0.9, duration = 0.7 },

	-- OPACITE MAXIMALE DU HALO, tous apports confondus.
	--
	-- Il valait 0.55 sur des bandes larges, et les deux couches — ambiance de
	-- menace et coup encaisse — s'ADDITIONNAIENT. Sur une scene sombre, le
	-- resultat n'etait pas un halo mais un voile brun-rouge sur toute l'image,
	-- exactement ce que la consigne interdit.
	--
	-- Deux corrections : ce plafond, et une composition en ECRAN plutot qu'en
	-- somme (voir DamageFeedback.step).
	maxEdge = 0.46,

	-- Eclair d'impact : une nappe plein ecran tres breve et tres faible. Elle
	-- ne colore pas l'image, elle la FRAPPE. C'est ce qui manquait — les
	-- bandes de bord montent trop lentement pour se lire comme un choc.
	flash = { intensity = 0.13, duration = 0.11 },

	-- Battement cardiaque sous ce ratio de vie.
	heartbeatBelow = 0.3,
}

-- --------------------------------------------------- Pictogrammes -------
--
-- IDENTIFIANTS D'IMAGES, A RENSEIGNER.
--
-- Tant qu'une entree vaut 0, le pictogramme est DESSINE au trait par
-- Components.icon. Des qu'un identifiant valide est pose, l'image le remplace
-- sans autre changement : c'est le seul endroit a modifier.
--
-- Le repli n'est pas une precaution de style — il garantit qu'un asset
-- retire, modere ou mal renseigne laisse un symbole lisible au lieu d'un
-- carre vide.
--
-- Format attendu : l'identifiant numerique seul (Theme y ajoute le prefixe),
-- une image carree, de preference blanche sur fond transparent pour que la
-- teinte d'etat s'applique.
Theme.iconAssets = {
	-- Rendus chrome fournis par xrod_off2, televerses depuis
	-- assets/icons/. La batterie garde son dessin au trait : elle etait
	-- deja bonne, et un boitier qu'on remplit se lit mieux qu'un rendu.
	health = 105352149505029,
	armor = 91714244327633,
	stamina = 116844880554266,
	battery = 0,
	rifle = 0,
	pistol = 0,
	medkit = 0,
	grenade = 0,
	utility = 0,
} :: { [string]: number }

-- -------------------------------------------------- Moniteur vital ------
--
-- Le bloc de vitaux n'est pas un tableau de bord propre : c'est un appareil
-- de terrain qui a vecu. Trois couches le disent — le balayage d'un tube
-- cathodique, la grille d'un moniteur medical, et une degradation qui
-- s'aggrave avec l'etat du porteur.
--
-- C'est cette DEGRADATION qui porte l'horreur. Un HUD qui reste impeccable
-- pendant que le joueur agonise raconte que rien n'est grave.
Theme.monitor = {
	-- Lignes de balayage sur toute la plaque.
	scanlines = 8,
	scanlineTransparency = 0.93,
	scanlineSpeed = 0.04,

	-- Grille derriere le trace, comme un papier millimetre de moniteur.
	gridColumns = 9,
	gridRows = 4,
	gridTransparency = 0.9,

	-- Sous cette fraction de vie, l'appareil commence a lacher : brouillage
	-- des libelles et bruit sur le signal.
	degradeBelow = 0.35,
	glitchBelow = 0.25,
	glitchPerSecond = 2.4,

	-- Amplitude du bruit ajoute au trace, en pixels, a degradation maximale.
	noisePixels = 3,
}

-- ------------------------------------------------------ Transmissions ---

Theme.transmission = {
	tone = {
		neutral = Theme.color.info,
		technical = Theme.color.cyan,
		warning = Theme.color.amber,
		danger = Theme.color.danger,
	},
	rate = 46,
	hold = 7,
	fadeIn = 9,
	fadeOut = 2.6,
}

-- ------------------------------------------------------- Animations ----
--
-- Rapides et sobres. Une interface tactique ne rebondit pas.
Theme.motion = {
	fade = 8,
	slide = 10,
	pulse = 2.4,
}

-- --------------------------------------------------- Rapport de sortie --
--
-- Le debrief n'est pas un ecran de score : c'est un DOCUMENT que le
-- commanditaire produit sur le joueur. Toute la direction artistique
-- decoule de ca — un formulaire d'entreprise, imprime sur un terminal
-- fatigue, pas une banniere de victoire.
--
-- Consequence concrete : le rapport s'IMPRIME ligne a ligne au lieu
-- d'apparaitre. C'est ce qui le fait lire comme une machine qui redige, et
-- c'est aussi ce qui laisse le temps de lire chaque poste.
Theme.debrief = {
	width = 880,
	height = 664,

	-- Corps de texte PROPRES au rapport.
	--
	-- Ils ne reprennent pas l'echelle du HUD et c'est voulu : le HUD se lit du
	-- coin de l'oeil pendant qu'on joue, il doit rester discret. Le rapport se
	-- lit de face, sans rien d'autre a l'ecran, et il porte des chiffres dont
	-- depend la decision de repartir ou non. Un document qu'on doit plisser les
	-- yeux pour lire n'est pas un document.
	type = {
		company = 17,
		subheader = 12,
		dossier = 13,
		classification = 12,
		verdict = 44,
		cause = 16,
		stamp = 27,
		columnTitle = 13,
		rowQuantity = 15,
		rowName = 18,
		rowValue = 18,
		logLabel = 15,
		logValue = 25,
		totalLabel = 16,
		totalValue = 29,
		balance = 16,
		paidCaption = 13,
		paid = 64,
		closing = 18,
		dismiss = 15,
	},

	-- Duree d'affichage avant fermeture automatique, par issue. La reussite
	-- dure plus longtemps : il y a un manifeste a lire.
	holdTime = {
		EXTRACTED = 22,
		KIA = 16,
		EXPIRED = 16,
	},

	-- Couleur d'accent par issue. C'est le seul endroit ou l'issue devient
	-- une couleur ; le widget n'en connait aucune.
	accent = {
		EXTRACTED = Theme.color.extraction,
		KIA = Theme.color.danger,
		EXPIRED = Theme.color.amber,
	},

	-- ETAT DU DOCUMENT selon l'issue.
	--
	-- C'est ici que vit l'horreur. Un rapport de reussite sort d'une machine
	-- qui fonctionne ; un rapport de perte d'actif sort de la meme machine
	-- pendant que la liaison se degrade. Trois reglages suffisent a le dire
	-- sans une ligne de texte de plus :
	--
	--   scanline  opacite des lignes de balayage (plus bas = plus marque)
	--   vignette  noircissement des bords interieurs du document
	--   jitter    amplitude du tremblement, en pixels, a l'ouverture
	--   decay     duree du tremblement, en secondes
	grain = {
		EXTRACTED = { scanline = 0.955, vignette = 0.2, jitter = 0, decay = 0 },
		EXPIRED = { scanline = 0.935, vignette = 0.34, jitter = 1.5, decay = 0.8 },
		KIA = { scanline = 0.895, vignette = 0.5, jitter = 5, decay = 1.6 },
	},

	-- Cadences d'impression, en secondes.
	timing = {
		open = 0.34,
		header = 0.22,
		verdict = 0.55,
		rowFirst = 0.95,
		rowStep = 0.075,
		footer = 0.28,
	},

	-- Duree du defilement des grands nombres. Un total qui monte se lit
	-- comme un comptage ; un total pose se lit comme un acquis.
	rollDuration = 0.9,

	-- Lignes de balayage sur le document, comme sur le moniteur vital : les
	-- deux surfaces appartiennent au meme materiel.
	scanlines = 20,

	-- Equerres d'angle, reprises du vocabulaire des panneaux du HUD. Elles
	-- font lire le rapport comme un instrument et non comme une boite.
	bracketLength = 24,
	bracketThickness = 2,

	-- Perforations le long du bord gauche. Detail d'imprimante : c'est ce qui
	-- fait passer le document de « fenetre » a « bande sortie d'une machine ».
	sprocketSpacing = 26,

	-- Assombrissement du jeu derriere le rapport. Pas un noir complet : on
	-- doit continuer a voir la zone ou l'on se trouve.
	scrimTransparency = 0.16,
}

-- ------------------------------------------------------------ Panique ----
--
-- Degradation appliquee a TOUT le HUD quand le rythme cardiaque monte. Le
-- bloc de vitaux tremblait deja tout seul ; ces valeurs propagent le meme
-- etat au reste de l'equipement, depuis la meme source.
Theme.panic = {
	-- Rythme normalise en dessous duquel RIEN ne bouge. Au repos le HUD est
	-- parfaitement stable : la panique doit rester un evenement.
	startsAt = 0.34,

	-- Amplitude du tremblement des panneaux, en pixels, a l'affolement.
	-- Trois pixels suffisent — au-dela on ne lit plus les chiffres, et un
	-- HUD illisible au pire moment punit deux fois.
	maxOffset = 3,

	-- Tirages de position par seconde, au repos du seuil puis a plein.
	-- Reechantillonner a chaque image donnerait du bruit blanc, pas un
	-- tremblement.
	rerollBase = 5,
	rerollGain = 16,

	-- Decrochages de libelle par seconde, et duree d'un decrochage.
	glitchBase = 0.4,
	glitchGain = 2.8,
	glitchHold = 0.09,
}

Theme.glitchGlyphs = "#%&@$*!/\\|=+<>~^"

return Theme
