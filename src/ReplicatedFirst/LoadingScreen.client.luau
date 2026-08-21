--!strict
-- Ecran de mise en ligne — terminal de deploiement MERIDIAN.
--
-- CE QUE CET ECRAN EMPECHE
--
-- Ce n'est pas un habillage. Le personnage apparait des que le serveur le
-- demande, sans attendre que la carte soit arrivee chez le client : sur une
-- vraie carte, le joueur se retrouve quelques secondes dans le vide, tombe,
-- ou voit le decor se materialiser autour de lui. Cet ecran tient jusqu'a ce
-- que le sol existe REELLEMENT sous ses pieds.
--
-- LES QUATRE ETAPES SONT DES MESURES, PAS UNE ANIMATION
--
--   LIAISON      le moteur a fini de repliquer (`game:IsLoaded`)
--   SECTEUR      il y a du sol sous le point d'apparition (sonde verticale)
--   EQUIPEMENT   le HUD est monte et les canaux sont repliques
--   DEPLOIEMENT  le personnage est vivant et jouable
--
-- Une barre qui avance sans rien mesurer est pire que pas de barre : elle
-- apprend au joueur que l'affichage ment. Ici tout ce qui bouge vient d'une
-- lecture reelle — la profondeur affichee au journal est la distance rendue
-- par le raycast, la latence est celle du socket, la memoire est celle du
-- client.
--
-- CE QUE L'ECRAN RACONTE
--
-- Le joueur n'attend pas un chargement : il attend qu'une societe militaire
-- privee finisse de le mettre en ligne. La liaison se degrade toute seule
-- pendant l'attente — plus le chargement dure, plus le terminal decroche.
-- C'est la meme regle que le HUD (`Panic`) : l'appareil se degrade quand la
-- situation se degrade, ici la situation etant l'attente elle-meme.
--
-- Le pied de page recite le contrat. Ce sont les seules phrases de l'ecran
-- qui ne mesurent rien, et elles disent au joueur ce que le commanditaire
-- pense de lui avant meme qu'il ait touche le sol.
--
-- IL NE BLOQUE JAMAIS INDEFINIMENT
--
-- Chaque etape a un delai maximal. Passe ce delai on continue quand meme, en
-- le signalant dans la console : un joueur coince devant un ecran de
-- chargement parce qu'une sonde n'a pas abouti est un bug bien pire que
-- celui qu'on essaie d'eviter.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- On retire l'ecran Roblox par defaut le plus tot possible, avant meme de
-- construire le notre : sinon les deux se chevauchent une fraction de
-- seconde et le raccord se voit.
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

-- ------------------------------------------------------------ Reglages ---
--
-- Volontairement EN DUR ici, contrairement au reste du projet.
--
-- Ce script tourne avant que quoi que ce soit ne soit replique :
-- `ReplicatedStorage.Shared` n'existe pas encore quand il demarre. Aller y
-- chercher une config obligerait a attendre precisement ce qu'on est en
-- train d'attendre.

local STAGE_TIMEOUT = 20
local TOTAL_TIMEOUT = 45

-- DUREE PLANCHER D'UNE ETAPE, et respiration avant le cachet, en secondes.
--
-- Quand la carte est deja en cache, les quatre sondes aboutissent en moins
-- d'une demi-seconde : les quatre lignes basculent sur OK dans la meme image
-- et l'ecran passe en un clignement. Le joueur ne lit pas une mise en ligne,
-- il voit un defaut d'affichage.
--
-- Le plancher est POSE SUR CHAQUE ETAPE, pas en bloc a la fin. Une attente
-- ajoutee apres coup afficherait « pret » pendant deux secondes sans
-- deployer, ce qui est le contraire de ce que l'ecran raconte ; etalee, elle
-- laisse voir les quatre mesures se resoudre l'une apres l'autre — ce pour
-- quoi cet ecran existe.
--
-- Le plancher ne s'applique QU'EN CAS DE SUCCES : une etape qui vient de
-- consommer ses vingt secondes de delai n'a rien a prolonger.
local STAGE_FLOOR = 0.45
local TAIL_HOLD = 0.5

-- RELECTURE EN STUDIO.
--
-- Studio charge tout depuis le cache local : meme avec le plancher ci-dessus
-- l'ecran ne dure pas assez pour etre juge. On l'etire ici, et ici seulement
-- — `IsStudio` est faux dans une partie publiee, aucun joueur ne subit ces
-- valeurs.
--
-- Repasse-les a 0.45 / 0.5 quand tu testes autre chose que cet ecran.
if RunService:IsStudio() then
	STAGE_FLOOR = 3
	TAIL_HOLD = 2.5
end

-- Distance de la sonde de sol, en studs. Genereux : le personnage peut
-- apparaitre en hauteur sur une carte a etages.
local FLOOR_PROBE = 400

-- Palette reprise de `Theme.color`, dupliquee ici pour la meme raison que
-- les reglages. Si le HUD change de teinte, cette table change avec lui.
local COLOR = {
	void = Color3.fromRGB(8, 9, 10),
	panel = Color3.fromRGB(13, 14, 16),
	info = Color3.fromRGB(236, 237, 238),
	neutral = Color3.fromRGB(138, 145, 154),
	dim = Color3.fromRGB(92, 98, 106),
	faint = Color3.fromRGB(62, 67, 73),
	accent = Color3.fromRGB(232, 166, 62),
	done = Color3.fromRGB(74, 196, 118),
	danger = Color3.fromRGB(226, 58, 58),
}

local GLYPHS = "#%&@$*!/\\|=+<>~^"

local ICONS = { 105352149505029, 91714244327633, 116844880554266 }

-- Libelles. Le francais suit la meme regle que le reste du jeu, mais on ne
-- peut pas charger le module de localisation ici : on se limite donc a la
-- langue du client Roblox, lue directement.
local FRENCH = (function(): boolean
	local ok, id = pcall(function()
		return player.LocaleId
	end)
	return ok and typeof(id) == "string" and string.sub(id, 1, 2):lower() == "fr"
end)()

type Copy = {
	company: string,
	eyebrow: string,
	title: string,
	identity: { string },
	clearance: string,
	stages: { string },
	details: { string },
	waiting: string,
	probing: string,
	ready: string,
	failed: string,
	journalTitle: string,
	waveTitle: string,
	registerTitle: string,
	register: { string },
	sweepTitle: string,
	contacts: string,
	classified: string,
	link: string,
	memory: string,
	boot: { string },
	ambient: { string },
	events: { string },
	depth: string,
	contactFound: string,
	creed: { string },
	authorized: string,
	authorizedSub: string,
	late: string,
}

local TEXT: Copy = if FRENCH
	then {
		company = "MERIDIAN / SUPERVISION DES ACTIFS",
		eyebrow = "PROTOCOLE DE MISE EN LIGNE",
		title = "BLACKOUT",
		identity = { "OPERATEUR", "MATRICULE", "AUTORISATION" },
		clearance = "NIVEAU 3 — TERRAIN",
		stages = { "LIAISON", "SECTEUR", "EQUIPEMENT", "DEPLOIEMENT" },
		details = {
			"synchronisation du client",
			"sol confirme sous le point d'insertion",
			"interface de terrain et canaux",
			"signes vitaux du porteur",
		},
		waiting = "EN ATTENTE",
		probing = "ANALYSE",
		ready = "OK",
		failed = "DEFAUT",
		journalTitle = "JOURNAL DE LIAISON",
		waveTitle = "SIGNAL DE SECTEUR",
		registerTitle = "REGISTRE",
		register = { "SITE", "SESSION", "PORTEUR", "HORODATAGE", "CLIENT" },
		sweepTitle = "BALAYAGE THERMIQUE",
		contacts = "CONTACTS",
		classified = "MERIDIAN INTERNE — NE PAS ARCHIVER",
		link = "LIAISON",
		memory = "MEM",
		boot = { "liaison montante etablie", "authentification du porteur" },
		ambient = {
			"balayage thermique : 0 signature amie",
			"canal 2 : silence radio",
			"archive du secteur : consultation refusee",
			"derniere equipe : aucun retour",
			"pression atmospherique : instable",
			"relais orbital : 1 saut",
			"assurance de l'actif : non souscrite",
			"eclairage du secteur : hors service",
		},
		events = {
			"client synchronise",
			"secteur sonde",
			"interface de terrain en ligne",
			"signes vitaux nominaux",
		},
		depth = "sol confirme",
		contactFound = "CONTACT NON IDENTIFIE",
		creed = {
			"PERTE D'ACTIF ACCEPTABLE : 6 / 6",
			"AUCUNE EXTRACTION DE SECOURS N'EST PREVUE.",
			"LE CONTRAT SURVIT AU CONTRACTANT.",
			"EN CAS DE PERTE DE SIGNAL, LE SECTEUR EST CLOS.",
		},
		authorized = "DEPLOIEMENT AUTORISE",
		authorizedSub = "le secteur est ouvert",
		late = "LIAISON DEGRADEE — DEPLOIEMENT FORC\u{c9}",
	}
	else {
		company = "MERIDIAN / ASSET OVERSIGHT",
		eyebrow = "UPLINK PROTOCOL",
		title = "BLACKOUT",
		identity = { "OPERATOR", "TAG", "CLEARANCE" },
		clearance = "LEVEL 3 — FIELD",
		stages = { "UPLINK", "SECTOR", "EQUIPMENT", "DEPLOYMENT" },
		details = {
			"client synchronisation",
			"ground confirmed under insertion point",
			"field interface and channels",
			"carrier vital signs",
		},
		waiting = "STANDBY",
		probing = "PROBING",
		ready = "OK",
		failed = "FAULT",
		journalTitle = "UPLINK LOG",
		waveTitle = "SECTOR SIGNAL",
		registerTitle = "REGISTRY",
		register = { "SITE", "SESSION", "CARRIER", "TIMESTAMP", "CLIENT" },
		sweepTitle = "THERMAL SWEEP",
		contacts = "CONTACTS",
		classified = "MERIDIAN INTERNAL — DO NOT ARCHIVE",
		link = "UPLINK",
		memory = "MEM",
		boot = { "uplink established", "carrier authentication" },
		ambient = {
			"thermal sweep: 0 friendly signature",
			"channel 2: radio silence",
			"sector archive: access denied",
			"previous team: no return",
			"atmospheric pressure: unstable",
			"orbital relay: 1 hop",
			"asset insurance: not held",
			"sector lighting: offline",
		},
		events = {
			"client synchronised",
			"sector probed",
			"field interface online",
			"vital signs nominal",
		},
		depth = "ground confirmed",
		contactFound = "UNIDENTIFIED CONTACT",
		creed = {
			"ACCEPTABLE ASSET LOSS: 6 / 6",
			"NO RESCUE EXTRACTION IS PLANNED.",
			"THE CONTRACT OUTLIVES THE CONTRACTOR.",
			"ON SIGNAL LOSS, THE SECTOR IS SEALED.",
		},
		authorized = "DEPLOYMENT AUTHORISED",
		authorizedSub = "the sector is open",
		late = "UPLINK DEGRADED — DEPLOYMENT FORCED",
	}

-- ---------------------------------------------------------- Outillage ----

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(class)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Espacement de lettres. Roblox n'expose pas de `letter-spacing` : on
-- intercale des espaces. C'est la seule facon d'obtenir la chasse large des
-- en-tetes militaires.
-- INTERLETTRAGE — A EMPLOYER AVEC PARCIMONIE.
--
-- Il etait pose sur TOUS les libelles en capitales, et c'est ce qui donnait
-- a l'ecran son air de decor de science-fiction generique : quand tout est
-- traque, plus rien ne l'est, et il ne reste qu'un maniérisme. Un vrai
-- terminal n'espace pas ses libelles d'exploitation.
--
-- Il ne subsiste que sur les trois enonces INSTITUTIONNELS — la raison
-- sociale, le titre, le cachet d'autorisation. Ce sont les seuls endroits ou
-- la societe parle en son nom propre, et le contraste avec le reste, serre
-- et fonctionnel, fait justement la hierarchie.
local function spaced(text: string): string
	return (text:gsub(".", "%0 "):gsub("%s+$", ""))
end

-- Interlettrage large, pour le titre seul.
--
-- Oswald est TRES etroit : « BLACKOUT » a 150 px de corps ne mesure que 558
-- px de large, soit moins d'un tiers de la bande utile. Un titre qui n'occupe
-- pas sa ligne ne pese rien. Trois espaces entre chaque lettre le portent a
-- 883 px — la moitie de l'ecran — sans toucher a sa hauteur.
local function tracked(text: string): string
	return (text:gsub(".", "%0   "):gsub("%s+$", ""))
end

-- Brouillage : on remplace `count` caracteres non blancs au hasard. Meme
-- vocabulaire que `Components.scramble` du HUD, reimplemente ici parce que
-- `Shared` n'est pas encore replique.
local function scramble(text: string, count: number): string
	local chars = table.create(#text)
	for index = 1, #text do
		chars[index] = string.sub(text, index, index)
	end
	for _ = 1, count do
		local pick = math.random(1, math.max(1, #chars))
		if chars[pick] ~= " " then
			local glyph = math.random(1, #GLYPHS)
			chars[pick] = string.sub(GLYPHS, glyph, glyph)
		end
	end
	return table.concat(chars)
end

-- Matricule. MEME FORMULE que `Shared.Spectate.tag` : le joueur doit lire le
-- meme numero ici, sur le HUD, en vue spectateur et sur le rapport de fin.
-- Deux formules donneraient deux identites au meme homme.
local function tagFor(userId: number): string
	return string.format("SCAV-%04d", math.floor(math.abs(userId)) % 10000)
end

local function clockText(seconds: number): string
	local minutes = math.floor(seconds / 60)
	local rest = seconds - minutes * 60
	return string.format("T+%02d:%04.1f", minutes, rest)
end

-- ------------------------------------------------------------- Echelle ---
--
-- ON NE MESURE PLUS LA FENETRE : ON DESSINE DANS UN GABARIT.
--
-- Trois tentatives ont echoue, chacune pour une raison differente, et la
-- liste vaut d'etre gardee :
--
--   * repli code en dur — la mise en page partait sur un 1920x1080
--     imaginaire et le bas passait sous le bord d'une fenetre plus petite ;
--   * attente de la premiere valeur plausible — Studio passe par une taille
--     INTERMEDIAIRE (releve : 702 de haut avant de se poser sur 631) ;
--   * attente d'une valeur STABLE — mesure faite, `ViewportSize` reste 1x1
--     pendant plus de cinq secondes ici, et l'ecran repartait sur le repli.
--
-- On arrete de courir apres la fenetre. Tout le contenu est dessine dans un
-- GABARIT FIXE de 1920x1080, et un seul `UIScale`, reevalue a chaque image,
-- le met a la taille de l'ecran. Consequences :
--
--   * la mise en page ne peut plus etre fausse : elle ne depend de rien ;
--   * un joueur qui redimensionne pendant le chargement est suivi tout de
--     suite, sans rien reconstruire ;
--   * plus une seule image d'attente au demarrage.
--
-- Les couches d'ambiance — grille, balayage, roulement, vignette — restent
-- HORS du gabarit, en coordonnees relatives : elles couvrent l'ecran entier,
-- pas le document.

local SCREEN_W = 1920
local SCREEN_H = 1080

local S = 1
local function px(value: number): number
	return math.floor(value + 0.5)
end

local MARGIN = px(54)
local BAND_W = SCREEN_W - MARGIN * 2
local RIGHT_X = MARGIN + math.floor(BAND_W * 0.56)
local RIGHT_W = BAND_W - math.floor(BAND_W * 0.56)

-- ----------------------------------------------------------- Fondu -------
--
-- MEME PIEGE QUE LE RAPPORT DE FIN : si on relit la transparence courante
-- pour calculer un fondu, une seconde passe la lit deja fondue et l'element
-- ne revient jamais. On releve la reference une fois, a la creation, et on
-- la RE-RELEVE explicitement avant l'extinction.

type Fade = { object: any, background: number, text: number, image: number }

local fades: { Fade } = {}

local function fadeable(object: any)
	if not object:IsA("GuiObject") then
		return
	end
	table.insert(fades, {
		object = object,
		background = object.BackgroundTransparency,
		text = if object:IsA("TextLabel") then object.TextTransparency else 1,
		image = if object:IsA("ImageLabel") then object.ImageTransparency else 1,
	})
end

local function snapshot()
	for _, entry in fades do
		entry.background = entry.object.BackgroundTransparency
		if entry.object:IsA("TextLabel") then
			entry.text = entry.object.TextTransparency
		end
		if entry.object:IsA("ImageLabel") then
			entry.image = entry.object.ImageTransparency
		end
	end
end

-- `alpha` 0 = visible, 1 = efface.
local function applyAlpha(alpha: number)
	local a = math.clamp(alpha, 0, 1)
	for _, entry in fades do
		entry.object.BackgroundTransparency = entry.background + (1 - entry.background) * a
		if entry.object:IsA("TextLabel") then
			entry.object.TextTransparency = entry.text + (1 - entry.text) * a
		end
		if entry.object:IsA("ImageLabel") then
			entry.object.ImageTransparency = entry.image + (1 - entry.image) * a
		end
	end
end

-- ------------------------------------------------------------ Montage ----

local gui = new("ScreenGui", {
	Name = "BlackoutLoading",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 100,
}, playerGui)

-- Rideau : le noir de fond, et la DERNIERE chose a disparaitre. Il n'est pas
-- dans le registre de fondu, il a son propre cycle.
local curtain = new("Frame", {
	Name = "Curtain",
	BackgroundColor3 = COLOR.void,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 1,
}, gui)

local root = new("Frame", {
	Name = "Terminal",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 2,
}, gui)

local rootHome = UDim2.fromOffset(0, 0)

-- LE GABARIT. Taille fixe, centre, mis a l'echelle par `UIScale`.
--
-- `min` et non `max` : le contenu doit entrer ENTIEREMENT dans la fenetre.
-- Sur un format plus large que 16/9 il reste des marges laterales — elles ne
-- se lisent pas comme des bandes noires puisque les couches d'ambiance, qui
-- vivent en dehors du gabarit, couvrent l'ecran entier.
local canvas = new("Frame", {
	Name = "Canvas",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(SCREEN_W, SCREEN_H),
	ZIndex = 2,
}, root)

local canvasScale = new("UIScale", { Scale = 0.5 }, canvas)

local function fitCanvas()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local size = cam.ViewportSize
	if size.X < 2 or size.Y < 2 then
		return
	end
	canvasScale.Scale = math.min(size.X / SCREEN_W, size.Y / SCREEN_H)
end

fitCanvas()
local fitConnection = RunService.RenderStepped:Connect(fitCanvas)

local function frame(props: { [string]: any }, parent: Instance?): Frame
	local defaults: { [string]: any } = {
		BorderSizePixel = 0,
		BackgroundColor3 = COLOR.info,
		ZIndex = 5,
	}
	for key, value in props do
		defaults[key] = value
	end
	local object = new("Frame", defaults, parent or canvas)
	fadeable(object)
	return object
end

local function label(props: { [string]: any }, parent: Instance?): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.RobotoCondensed,
		TextColor3 = COLOR.info,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 6,
	}
	for key, value in props do
		defaults[key] = value
	end
	local object = new("TextLabel", defaults, parent or canvas)
	fadeable(object)
	return object
end

-- --- couches d'ambiance --------------------------------------------------
--
-- Quatre couches, de la plus lointaine a la plus proche : la grille de
-- visee, les lignes de balayage, la barre de roulement du tube, la vignette.
-- Ce sont elles qui font lire l'ecran comme un MONITEUR et non comme une
-- page. Le HUD, le rapport de fin et la vue spectateur portent deja les
-- deux premieres : le joueur reconnait l'appareil avant d'etre en jeu.

-- Elles sont parentees a `root`, PAS au gabarit : un moniteur fatigue l'est
-- sur toute sa dalle, pas seulement derriere le document.
local GRID_COLUMNS = 21
local GRID_ROWS = 12
for index = 1, GRID_COLUMNS - 1 do
	frame({
		BackgroundColor3 = COLOR.neutral,
		BackgroundTransparency = 0.94,
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.fromScale(index / GRID_COLUMNS, 0),
		ZIndex = 2,
	}, root)
end
for index = 1, GRID_ROWS - 1 do
	frame({
		BackgroundColor3 = COLOR.neutral,
		BackgroundTransparency = 0.94,
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.fromScale(0, index / GRID_ROWS),
		ZIndex = 2,
	}, root)
end

local SCANLINES = 30
local scanlines: { Frame } = {}
for index = 1, SCANLINES do
	table.insert(
		scanlines,
		frame({
			BackgroundColor3 = COLOR.neutral,
			BackgroundTransparency = 0.9,
			Size = UDim2.new(1, 0, 0, 2),
			Position = UDim2.fromScale(0, (index - 1) / SCANLINES),
			ZIndex = 3,
		}, root)
	)
end

-- UNE LIGNE MORTE.
--
-- Une seule ligne de balayage, plus claire que les autres, qui NE DEFILE
-- PAS. C'est le defaut d'un tube qui a trop servi, et c'est la seule chose
-- de cet ecran qui ne serve strictement a rien — raison pour laquelle elle y
-- est. Une interface sans un seul defaut n'a jamais ete fabriquee, seulement
-- dessinee.
frame({
	BackgroundColor3 = COLOR.neutral,
	BackgroundTransparency = 0.86,
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.fromScale(0, 0.372),
	ZIndex = 3,
}, root)

-- Barre de roulement : la bande claire qui descend lentement sur un tube mal
-- synchronise. Un seul objet, et c'est ce qui empeche l'ecran d'avoir l'air
-- fige pendant les longues attentes.
local roll = frame({
	BackgroundColor3 = COLOR.neutral,
	BackgroundTransparency = 0.9,
	Size = UDim2.fromScale(1, 0.14),
	Position = UDim2.fromScale(0, -0.14),
	ZIndex = 3,
}, root)
new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, roll)

-- Vignette : quatre bandes de bord. Convention de gradient du projet — le
-- point 0 est OPAQUE et se trouve au bord ; rotation 90 = haut, 270 = bas,
-- 0 = gauche, 180 = droite.
local function vignette(size: UDim2, position: UDim2, rotation: number)
	local band = frame({
		BackgroundColor3 = COLOR.void,
		BackgroundTransparency = 0,
		Size = size,
		Position = position,
		ZIndex = 4,
	}, root)
	new("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, band)
end

vignette(UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0), 90)
vignette(UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0.82), 270)
vignette(UDim2.fromScale(0.14, 1), UDim2.fromScale(0, 0), 0)
vignette(UDim2.fromScale(0.14, 1), UDim2.fromScale(0.86, 0), 180)

-- --- equerres d'ecran ----------------------------------------------------
--
-- Elles sont posees sur les COINS DE L'ECRAN, pas sur un panneau. C'est ce
-- qui fait passer l'image de « fenetre de chargement » a « ce que l'operateur
-- a devant les yeux ». Meme vocabulaire que les panneaux du HUD, a une
-- echelle differente.

local BRACKET = px(46)
local function bracket(x: number, y: number, dx: number, dy: number)
	frame({
		BackgroundColor3 = COLOR.dim,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(BRACKET, 1),
		Position = UDim2.fromOffset(if dx > 0 then x else x - BRACKET, y),
		ZIndex = 7,
	})
	frame({
		BackgroundColor3 = COLOR.dim,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(1, BRACKET),
		Position = UDim2.fromOffset(x, if dy > 0 then y else y - BRACKET),
		ZIndex = 7,
	})
end

local INSET = px(26)
bracket(INSET, INSET, 1, 1)
bracket(SCREEN_W - INSET, INSET, -1, 1)
bracket(INSET, SCREEN_H - INSET, 1, -1)
bracket(SCREEN_W - INSET, SCREEN_H - INSET, -1, -1)

-- --- rail d'en-tete ------------------------------------------------------

local headerLabel = label({
	Text = spaced(TEXT.company),
	TextSize = px(15),
	TextColor3 = COLOR.neutral,
	Size = UDim2.fromOffset(math.floor(BAND_W * 0.6), px(20)),
	Position = UDim2.fromOffset(MARGIN, MARGIN),
})

local linkDot = frame({
	BackgroundColor3 = COLOR.accent,
	Size = UDim2.fromOffset(px(6), px(6)),
	Position = UDim2.fromOffset(SCREEN_W - MARGIN - px(6), MARGIN + px(7)),
	ZIndex = 7,
})

local telemetry = label({
	Text = "",
	TextSize = px(13),
	Font = Enum.Font.RobotoMono,
	TextColor3 = COLOR.dim,
	TextXAlignment = Enum.TextXAlignment.Right,
	Size = UDim2.fromOffset(math.floor(BAND_W * 0.5), px(20)),
	Position = UDim2.fromOffset(SCREEN_W - MARGIN - px(18) - math.floor(BAND_W * 0.5), MARGIN),
})

frame({
	BackgroundColor3 = COLOR.neutral,
	BackgroundTransparency = 0.4,
	Size = UDim2.fromOffset(BAND_W, 1),
	Position = UDim2.fromOffset(MARGIN, MARGIN + px(26)),
	ZIndex = 6,
})

-- --- epine dorsale -------------------------------------------------------
--
-- Un trait vertical du filet d'en-tete jusqu'au pied, qui separe la colonne
-- d'exploitation de la colonne d'instruments.
--
-- L'ecran etait compose de blocs poses a intervalles reguliers sur une page
-- vide — la signature meme d'une maquette qui n'a pas ete pensee. Ce seul
-- trait lui donne une ARCHITECTURE : a gauche on agit, a droite on mesure,
-- et les deux moities n'ont plus besoin d'avoir la meme densite pour se
-- tenir. C'est ce desequilibre assume qui fait la difference entre une
-- composition et une grille.
frame({
	BackgroundColor3 = COLOR.neutral,
	BackgroundTransparency = 0.86,
	Size = UDim2.fromOffset(1, SCREEN_H - px(196) - px(39) - MARGIN - px(26)),
	Position = UDim2.fromOffset(RIGHT_X - px(30), MARGIN + px(26)),
	ZIndex = 5,
})

-- --- bande de danger -----------------------------------------------------
--
-- Les chevrons jaune et noir d'une zone reglementee. C'est le signe le plus
-- immediatement militaire qu'on puisse poser, et il ne coute qu'un cadre
-- ecreteur rempli de barres inclinees — Roblox ne sait pas biaiser un cadre,
-- mais il sait le faire tourner et rogner ce qui depasse.
local hazard = frame({
	BackgroundColor3 = COLOR.void,
	BackgroundTransparency = 0.3,
	ClipsDescendants = true,
	Size = UDim2.fromOffset(BAND_W, px(9)),
	Position = UDim2.fromOffset(MARGIN, MARGIN + px(32)),
	ZIndex = 6,
})

local HAZARD_PITCH = px(24)
for x = -px(24), BAND_W + px(24), HAZARD_PITCH do
	frame({
		BackgroundColor3 = COLOR.accent,
		BackgroundTransparency = 0.62,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		Size = UDim2.fromOffset(px(7), px(42)),
		Position = UDim2.fromOffset(x, px(5)),
		ZIndex = 7,
	}, hazard)
end

-- --- titre ---------------------------------------------------------------

local heroTop = math.floor(SCREEN_H * 0.115)

label({
	Text = TEXT.eyebrow,
	TextSize = px(13),
	TextColor3 = COLOR.dim,
	Size = UDim2.fromOffset(BAND_W, px(18)),
	Position = UDim2.fromOffset(MARGIN, heroTop),
})

-- Double d'impression du titre, en rouge, DERRIERE le vrai. Meme dispositif
-- que `Panic.ghostFor` : c'est l'ecart entre les deux canaux qui se lit
-- comme une transmission qui decroche, pas le brouillage seul.
local heroGhost = label({
	Text = tracked(TEXT.title),
	Font = Enum.Font.Oswald,
	TextSize = px(150),
	TextColor3 = COLOR.danger,
	TextTransparency = 1,
	Size = UDim2.fromOffset(BAND_W, px(170)),
	Position = UDim2.fromOffset(MARGIN + px(6), heroTop + px(26) + px(3)),
	ZIndex = 5,
})

local hero = label({
	Text = tracked(TEXT.title),
	Font = Enum.Font.Oswald,
	TextSize = px(150),
	TextColor3 = COLOR.info,
	Size = UDim2.fromOffset(BAND_W, px(170)),
	Position = UDim2.fromOffset(MARGIN, heroTop + px(26)),
	ZIndex = 6,
})

frame({
	BackgroundColor3 = COLOR.faint,
	Size = UDim2.fromOffset(px(500), 1),
	Position = UDim2.fromOffset(MARGIN, heroTop + px(206)),
	ZIndex = 6,
})

-- --- identite du porteur -------------------------------------------------
--
-- L'ecran s'adresse au joueur par son matricule avant de lui parler du
-- secteur. C'est la premiere fois de la partie qu'il voit son propre numero,
-- et c'est le meme qu'il portera en vue spectateur s'il meurt.

local identityValues = {
	player.DisplayName,
	tagFor(player.UserId),
	TEXT.clearance,
}

for index, name in TEXT.identity do
	local top = heroTop + px(222) + (index - 1) * px(24)
	label({
		Text = name,
		TextSize = px(11),
		TextColor3 = COLOR.faint,
		Size = UDim2.fromOffset(px(140), px(18)),
		Position = UDim2.fromOffset(MARGIN, top),
	})
	label({
		Text = identityValues[index],
		TextSize = px(15),
		Font = Enum.Font.RobotoMono,
		TextColor3 = if index == 2 then COLOR.accent else COLOR.neutral,
		Size = UDim2.fromOffset(px(420), px(18)),
		Position = UDim2.fromOffset(MARGIN + px(150), top),
	})
end

-- --- reticule de balayage ------------------------------------------------
--
-- Le tiers droit de l'ecran etait vide, et un vide au milieu d'un terminal
-- se lit comme une page inachevee. On y pose l'instrument qui manquait : un
-- balayage thermique du secteur, avec sa ligne qui tourne et ses CONTACTS.
--
-- Il ne mesure rien — c'est le seul element decoratif de l'ecran, et il est
-- assume : ce qu'il raconte, en revanche, est vrai dans la fiction du jeu.
-- Le journal ecrit deja « 0 signature amie ». Trois contacts s'allument au
-- passage du balayage. Aucun n'est ami.

local DIAL = px(310)
local dialX = RIGHT_X + RIGHT_W // 2
local dialY = math.floor(SCREEN_H * 0.255)

local dial = frame({
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(DIAL, DIAL),
	Position = UDim2.fromOffset(dialX, dialY),
	ZIndex = 5,
})

-- Anneaux concentriques. Un cadre transparent, un rayon d'angle a 50 % et un
-- contour : Roblox n'a pas de cercle, mais il a ca.
for _, ratio in { 1, 0.66, 0.32 } do
	local ring = frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(math.floor(DIAL * ratio), math.floor(DIAL * ratio)),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 5,
	}, dial)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	new("UIStroke", {
		Color = COLOR.neutral,
		Thickness = 1,
		Transparency = if ratio == 1 then 0.38 else 0.68,
	}, ring)
end

-- Croix de visee.
frame({
	BackgroundColor3 = COLOR.neutral,
	BackgroundTransparency = 0.84,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(DIAL, 1),
	Position = UDim2.fromScale(0.5, 0.5),
	ZIndex = 5,
}, dial)
frame({
	BackgroundColor3 = COLOR.neutral,
	BackgroundTransparency = 0.84,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(1, DIAL),
	Position = UDim2.fromScale(0.5, 0.5),
	ZIndex = 5,
}, dial)

-- Couronne graduee. Elle tourne LENTEMENT et a CONTRESENS du balayage : deux
-- mouvements de sens contraire font un instrument, un seul fait une roue.
local bezel = frame({
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(DIAL, DIAL),
	Position = UDim2.fromScale(0.5, 0.5),
	ZIndex = 5,
}, dial)

for index = 1, 24 do
	local angle = math.rad((index - 1) * 15)
	local radius = DIAL / 2 - px(7)
	local major = (index - 1) % 6 == 0
	frame({
		BackgroundColor3 = COLOR.neutral,
		BackgroundTransparency = if major then 0.3 else 0.66,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = math.deg(angle),
		Size = UDim2.fromOffset(1, if major then px(11) else px(5)),
		Position = UDim2.new(0.5, math.floor(math.sin(angle) * radius), 0.5, math.floor(-math.cos(angle) * radius)),
		ZIndex = 5,
	}, bezel)
end

-- LE BALAYAGE.
--
-- Il tournait A COTE du cadran. La barre etait ancree a gauche et posee au
-- centre — ce qui suppose que Roblox pivote autour du point d'ancrage. La
-- documentation et l'usage se contredisent la-dessus, et je n'ai pas pu
-- trancher par la mesure : `AbsolutePosition` IGNORE la rotation, donc
-- aucune sonde ne renvoie la position reellement affichee.
--
-- Alors on ne tranche pas. La barre fait maintenant TOUT le diametre et son
-- centre coincide avec celui du cadran, point d'ancrage compris : les deux
-- pivots possibles sont au meme endroit, et la forme est juste quelle que
-- soit la convention.
--
-- C'est le degrade qui fait le rayon — il efface la moitie gauche. Un trait
-- qui traverse serait une aiguille de compas, pas un balayage.
local sweep = frame({
	BackgroundColor3 = COLOR.accent,
	BackgroundTransparency = 0.22,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(DIAL, 1),
	Position = UDim2.fromScale(0.5, 0.5),
	ZIndex = 6,
}, dial)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(0.53, 0.05),
		NumberSequenceKeypoint.new(1, 0.62),
	}),
}, sweep)

-- CONTACTS. Angles et distances tires une fois, puis figes : un contact qui
-- se deplacerait entre deux passages serait un bug d'affichage, pas une
-- presence.
type Contact = { dot: Frame, angle: number, charge: number, found: boolean }

local contacts: { Contact } = {}
for _ = 1, 3 do
	local angle = math.random(0, 359)
	local radius = (0.34 + math.random() * 0.58) * (DIAL / 2)
	table.insert(contacts, {
		angle = angle,
		charge = 0,
		found = false,
		dot = frame({
			BackgroundColor3 = COLOR.danger,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(px(5), px(5)),
			Position = UDim2.new(
				0.5,
				math.floor(math.sin(math.rad(angle)) * radius),
				0.5,
				math.floor(-math.cos(math.rad(angle)) * radius)
			),
			ZIndex = 7,
		}, dial),
	})
end

label({
	Text = TEXT.sweepTitle,
	TextSize = px(11),
	TextColor3 = COLOR.faint,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromOffset(RIGHT_W, px(16)),
	Position = UDim2.fromOffset(dialX - RIGHT_W // 2, dialY + DIAL // 2 + px(10)),
})

local contactsFound = 0

local contactLabel = label({
	Text = string.format("%s %02d", TEXT.contacts, contactsFound),
	TextSize = px(13),
	Font = Enum.Font.RobotoMono,
	TextColor3 = COLOR.danger,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromOffset(RIGHT_W, px(18)),
	Position = UDim2.fromOffset(dialX - RIGHT_W // 2, dialY + DIAL // 2 + px(24)),
})

-- --- mention de classement -----------------------------------------------
--
-- Le long du bord droit, a la verticale, comme le tampon d'un dossier qu'on
-- n'aurait pas du sortir.
local classification = frame({
	BackgroundColor3 = COLOR.danger,
	BackgroundTransparency = 0.94,
	AnchorPoint = Vector2.new(1, 0),
	Size = UDim2.fromOffset(px(330), px(24)),
	Position = UDim2.fromOffset(SCREEN_W - MARGIN, MARGIN + px(52)),
	ZIndex = 6,
})
new("UIStroke", { Color = COLOR.danger, Thickness = 1, Transparency = 0.55 }, classification)

label({
	Text = TEXT.classified,
	TextSize = px(11),
	TextColor3 = COLOR.danger,
	TextTransparency = 0.25,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 7,
}, classification)

-- --- etapes --------------------------------------------------------------

type Row = {
	tick: Frame,
	index: TextLabel,
	name: TextLabel,
	detail: TextLabel,
	state: TextLabel,
	rule: Frame,
	-- Le filet qui court du nom d'etape jusqu'a son etat. Sans lui les deux
	-- flottent aux extremites de la ligne sans se rapporter l'un a l'autre.
	leader: Frame,
	-- Segment clair qui court le long du filet pendant que la sonde tourne.
	-- Il ne dit pas « x pour cent » — il n'y a rien a pourcenter, une sonde
	-- repond ou ne repond pas. Il dit « ca travaille ».
	scan: Frame,
	active: boolean,
}

local ROW_TOP = math.floor(SCREEN_H * 0.44)
local ROW_STEP = px(52)
local ROW_W = math.floor(BAND_W * 0.46)

local rows: { Row } = {}
for index, name in TEXT.stages do
	local top = ROW_TOP + (index - 1) * ROW_STEP

	table.insert(rows, {
		active = false,
		tick = frame({
			BackgroundColor3 = COLOR.faint,
			Size = UDim2.fromOffset(px(5), px(5)),
			Position = UDim2.fromOffset(MARGIN, top + px(9)),
			ZIndex = 7,
		}),
		index = label({
			Text = string.format("%02d", index),
			TextSize = px(12),
			Font = Enum.Font.RobotoMono,
			TextColor3 = COLOR.faint,
			Size = UDim2.fromOffset(px(30), px(18)),
			Position = UDim2.fromOffset(MARGIN + px(18), top),
		}),
		name = label({
			Text = name,
			TextSize = px(21),
			TextColor3 = COLOR.dim,
			Size = UDim2.fromOffset(px(340), px(20)),
			Position = UDim2.fromOffset(MARGIN + px(56), top),
		}),
		detail = label({
			Text = TEXT.details[index],
			TextSize = px(12),
			TextColor3 = COLOR.faint,
			Size = UDim2.fromOffset(px(420), px(16)),
			Position = UDim2.fromOffset(MARGIN + px(56), top + px(20)),
		}),
		state = label({
			Text = TEXT.waiting,
			TextSize = px(13),
			Font = Enum.Font.RobotoMono,
			TextColor3 = COLOR.faint,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(px(160), px(18)),
			Position = UDim2.fromOffset(MARGIN + ROW_W - px(160), top),
		}),
		rule = frame({
			BackgroundColor3 = COLOR.neutral,
			BackgroundTransparency = 0.9,
			Size = UDim2.fromOffset(ROW_W, 1),
			Position = UDim2.fromOffset(MARGIN, top + px(42)),
			ZIndex = 6,
		}),
		leader = frame({
			BackgroundColor3 = COLOR.neutral,
			BackgroundTransparency = 0.9,
			Size = UDim2.fromOffset(ROW_W - px(250) - px(175), 1),
			Position = UDim2.fromOffset(MARGIN + px(250), top + px(11)),
			ZIndex = 5,
		}),
		scan = frame({
			BackgroundColor3 = COLOR.accent,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(px(90), 1),
			Position = UDim2.fromOffset(MARGIN, top + px(42)),
			ZIndex = 7,
		}),
	})
end

-- --- registre -----------------------------------------------------------
--
-- Un bloc serre de chiffres, sous les etapes, dans la colonne de gauche.
--
-- C'est le contraire de tout le reste de l'ecran, et c'est voulu. Une
-- interface technique credible n'est pas aeree partout : elle est vide la ou
-- il n'y a rien a dire, et DENSE la ou la machine deballe ce qu'elle sait.
-- Une page ou tout respire au meme rythme se lit comme une decoration.
--
-- Aucune de ces valeurs n'est inventee. Identifiant du lieu, identifiant de
-- session, matricule du porteur, horodatage UTC, version du client : ce sont
-- les cinq choses qu'un vrai journal d'incident demanderait, et elles sont
-- toutes lisibles ici.
local REGISTER_TOP = ROW_TOP + #TEXT.stages * ROW_STEP + px(30)

label({
	Text = TEXT.registerTitle,
	TextSize = px(11),
	TextColor3 = COLOR.dim,
	Size = UDim2.fromOffset(px(300), px(16)),
	Position = UDim2.fromOffset(MARGIN, REGISTER_TOP),
})

frame({
	BackgroundColor3 = COLOR.neutral,
	BackgroundTransparency = 0.82,
	Size = UDim2.fromOffset(px(440), 1),
	Position = UDim2.fromOffset(MARGIN, REGISTER_TOP + px(18)),
	ZIndex = 6,
})

local function safely(fallback: string, read: () -> string): string
	local ok, value = pcall(read)
	return if ok and typeof(value) == "string" and #value > 0 then value else fallback
end

local registerRows = {
	{
		TEXT.register[1],
		safely("—", function()
			return tostring(game.PlaceId)
		end),
	},
	{
		TEXT.register[2],
		safely("LOCAL", function()
			return string.upper(string.sub(game.JobId, 1, 8))
		end),
	},
	{ TEXT.register[3], tostring(player.UserId) },
	{
		TEXT.register[4],
		safely("—", function()
			return os.date("!%Y-%m-%d %H:%M:%SZ") :: string
		end),
	},
	{
		TEXT.register[5],
		safely("—", function()
			return version()
		end),
	},
}

for index, row in registerRows do
	local top = REGISTER_TOP + px(26) + (index - 1) * px(19)
	label({
		Text = row[1],
		TextSize = px(11),
		TextColor3 = COLOR.faint,
		Size = UDim2.fromOffset(px(110), px(15)),
		Position = UDim2.fromOffset(MARGIN, top),
	})
	label({
		Text = row[2],
		TextSize = px(12),
		Font = Enum.Font.RobotoMono,
		TextColor3 = COLOR.dim,
		Size = UDim2.fromOffset(px(330), px(15)),
		Position = UDim2.fromOffset(MARGIN + px(112), top),
	})
end

-- --- journal de liaison --------------------------------------------------

label({
	Text = TEXT.journalTitle,
	TextSize = px(11),
	TextColor3 = COLOR.dim,
	Size = UDim2.fromOffset(RIGHT_W, px(16)),
	Position = UDim2.fromOffset(RIGHT_X, ROW_TOP),
})

frame({
	BackgroundColor3 = COLOR.faint,
	Size = UDim2.fromOffset(px(330), 1),
	Position = UDim2.fromOffset(RIGHT_X, ROW_TOP + px(18)),
	ZIndex = 6,
})

local JOURNAL_STEP = px(21)
local JOURNAL_LINES = math.clamp(math.floor((SCREEN_H * 0.30) / JOURNAL_STEP), 6, 13)

local journal: { TextLabel } = {}
for index = 1, JOURNAL_LINES do
	table.insert(
		journal,
		label({
			Text = "",
			TextSize = px(12),
			Font = Enum.Font.RobotoMono,
			TextColor3 = COLOR.faint,
			Size = UDim2.fromOffset(RIGHT_W, px(16)),
			Position = UDim2.fromOffset(RIGHT_X, ROW_TOP + px(30) + (index - 1) * JOURNAL_STEP),
		})
	)
end

local startedAt = os.clock()

-- Le journal defile vers le HAUT : la ligne la plus recente est en bas, comme
-- sur un terminal. Les lignes anciennes s'eteignent progressivement — on lit
-- ce qui vient d'arriver, le reste est du contexte.
local journalCount = 0

local function log(text: string, color: Color3?)
	if journalCount < JOURNAL_LINES then
		journalCount += 1
	else
		for index = 1, JOURNAL_LINES - 1 do
			journal[index].Text = journal[index + 1].Text
			journal[index].TextColor3 = journal[index + 1].TextColor3
		end
	end

	local last = journal[journalCount]
	last.Text = string.format("%6.2f  %s", os.clock() - startedAt, text)
	last.TextColor3 = color or COLOR.dim

	-- Les lignes anciennes s'eteignent : on lit ce qui vient d'arriver, le
	-- reste est du contexte.
	for index = 1, journalCount do
		local depth = (journalCount - index) / math.max(1, journalCount)
		journal[index].TextTransparency = math.min(0.72, depth * 1.1)
	end
end

-- --- signal de secteur ---------------------------------------------------
--
-- Ce n'est pas un decor : l'amplitude monte a chaque evenement reel — etape
-- franchie, decrochage de liaison, delai depasse. C'est le seul endroit de
-- l'ecran ou l'on VOIT la liaison souffrir.

local WAVE_H = px(58)
local WAVE_Y = SCREEN_H - px(196)

label({
	Text = TEXT.waveTitle,
	TextSize = px(11),
	TextColor3 = COLOR.faint,
	Size = UDim2.fromOffset(px(300), px(16)),
	Position = UDim2.fromOffset(MARGIN, WAVE_Y - px(22)),
})

local WAVE_BARS = 96
local WAVE_PITCH = BAND_W / WAVE_BARS
local bars: { Frame } = {}
for index = 1, WAVE_BARS do
	table.insert(
		bars,
		frame({
			BackgroundColor3 = COLOR.accent,
			BackgroundTransparency = 0.62,
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(math.max(1, math.floor(WAVE_PITCH) - px(11)), px(3)),
			Position = UDim2.fromOffset(MARGIN + math.floor((index - 1) * WAVE_PITCH), WAVE_Y + WAVE_H // 2),
			ZIndex = 6,
		})
	)
end

-- --- bande de progression ------------------------------------------------

local STRIP_Y = SCREEN_H - px(96)
local segments: { Frame } = {}
for index = 1, #TEXT.stages do
	local width = BAND_W / #TEXT.stages
	table.insert(
		segments,
		frame({
			BackgroundColor3 = COLOR.faint,
			BackgroundTransparency = 0.62,
			Size = UDim2.fromOffset(math.floor(width) - px(4), px(3)),
			Position = UDim2.fromOffset(MARGIN + math.floor((index - 1) * width), STRIP_Y),
			ZIndex = 6,
		})
	)
end

-- --- rail de pied --------------------------------------------------------

local creed = label({
	Text = TEXT.creed[1],
	TextSize = px(13),
	TextColor3 = COLOR.dim,
	Size = UDim2.fromOffset(math.floor(BAND_W * 0.7), px(18)),
	Position = UDim2.fromOffset(MARGIN, SCREEN_H - px(70)),
})

local elapsed = label({
	Text = clockText(0),
	TextSize = px(13),
	Font = Enum.Font.RobotoMono,
	TextColor3 = COLOR.faint,
	TextXAlignment = Enum.TextXAlignment.Right,
	Size = UDim2.fromOffset(px(220), px(18)),
	Position = UDim2.fromOffset(SCREEN_W - MARGIN - px(220), SCREEN_H - px(70)),
})

-- --- couches d'evenement -------------------------------------------------
--
-- Posees une fois, invisibles au repos : creer un objet au moment du
-- decrochage ferait sauter une image sur les machines lentes.

local dip = frame({
	BackgroundColor3 = COLOR.void,
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 20,
}, root)

local tear = frame({
	BackgroundColor3 = COLOR.info,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 3),
	Position = UDim2.fromScale(0, 0),
	ZIndex = 21,
}, root)

-- ------------------------------------------------------------ Allumage ---
--
-- Mise sous tension d'un tube : un trait horizontal qui s'ouvre, puis la
-- hauteur qui se deploie. L'ecran ne s'affiche pas, il S'ALLUME — et c'est
-- ce meme geste, joue a l'envers, qui le coupera au moment du deploiement.

applyAlpha(1)

local beam = new("Frame", {
	BackgroundColor3 = COLOR.info,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 0, 0, 2),
	ZIndex = 30,
}, gui)

local function tween(duration: number, step: (t: number) -> ())
	local from = os.clock()
	while true do
		local t = math.clamp((os.clock() - from) / duration, 0, 1)
		step(t)
		if t >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

tween(0.16, function(t)
	beam.Size = UDim2.new(t, 0, 0, 2)
end)

tween(0.26, function(t)
	local eased = t * t
	beam.Size = UDim2.new(1, 0, eased, 2)
	beam.BackgroundTransparency = 0.15 + t * 0.85
	applyAlpha(1 - t)
end)

beam:Destroy()
applyAlpha(0)

print(
	`[Chargement] terminal monte — gabarit {SCREEN_W}x{SCREEN_H}`
		.. `, {#canvas:GetDescendants()} elements`
		.. `, {#hazard:GetChildren()} chevrons`
		.. `, {#contacts} contacts`
)

log(TEXT.boot[1])
log(TEXT.boot[2])

-- ---------------------------------------------------------- Animation ----

local clock = 0
local waveSpike = 0
local glitchIn = 1.1
local ambientIn = 1.2
local creedIn = 2.4
local creedIndex = 1
local headerRestore = 0
local ghostUntil = 0
local dipUntil = 0
local tearUntil = 0
local stageBusy = 0
local quiet = false

local heartbeat = RunService.Heartbeat:Connect(function(dt)
	clock += dt
	local waited = os.clock() - startedAt


	-- Balayage et roulement.
	for index, line in scanlines do
		line.Position = UDim2.fromScale(0, ((index - 1) / SCANLINES + clock * 0.045) % 1)
	end
	roll.Position = UDim2.fromScale(0, (clock * 0.14) % 1.25 - 0.12)

	-- Telemetrie. Trois lectures reelles ; aucune n'est inventee.
	elapsed.Text = clockText(waited)
	if math.floor(clock * 2) % 2 == 0 then
		local ping = 0
		pcall(function()
			ping = player:GetNetworkPing() * 1000
		end)
		local memory = 0
		pcall(function()
			memory = Stats:GetTotalMemoryUsageMb()
		end)
		telemetry.Text = string.format("%s %3d ms   %s %4d Mo", TEXT.link, math.floor(ping), TEXT.memory, math.floor(memory))
	end

	-- Le temoin de liaison bat. Il ne dit pas « ca charge », il dit « la
	-- ligne tient encore ».
	linkDot.BackgroundTransparency = 0.1 + (0.5 + math.sin(clock * 3.4) * 0.5) * 0.7

	-- Le point de l'etape en cours respire, les autres restent eteints, et un
	-- segment court le long de son filet.
	for _, row in rows do
		if row.active then
			row.tick.BackgroundTransparency = (0.5 + math.sin(clock * 5.2) * 0.5) * 0.75
			local travel = (clock * 0.55) % 1
			row.scan.Position = UDim2.fromOffset(
				MARGIN + math.floor((ROW_W - px(90)) * travel),
				row.rule.Position.Y.Offset
			)
			row.scan.BackgroundTransparency = 0.25
		elseif row.scan.BackgroundTransparency < 1 then
			row.scan.BackgroundTransparency = 1
		end
	end

	-- BALAYAGE THERMIQUE.
	--
	-- La ligne tourne, la couronne graduee tourne a contresens plus lentement.
	-- Un contact ne s'allume QU'AU PASSAGE de la ligne, puis s'eteint tout
	-- seul : c'est ce delai qui le fait lire comme une detection et non comme
	-- une decoration qui clignote.
	local sweepAngle = (clock * 46) % 360
	sweep.Rotation = sweepAngle
	bezel.Rotation = -clock * 5

	local litContacts = 0
	for _, contact in contacts do
		local delta = (sweepAngle - contact.angle) % 360
		if delta < 7 then
			contact.charge = 1
			if not contact.found then
				contact.found = true
				contactsFound += 1
				contactLabel.Text = string.format("%s %02d", TEXT.contacts, contactsFound)
				log(TEXT.contactFound, COLOR.danger)
			end
		end
		contact.charge = math.max(0, contact.charge - dt * 0.55)
		contact.dot.BackgroundTransparency = 1 - contact.charge * 0.92
		if contact.charge > 0.35 then
			litContacts += 1
		end
	end
	contactLabel.TextTransparency = if litContacts > 0 then 0 else 0.55

	-- Signal de secteur.
	waveSpike = math.max(0, waveSpike - dt * 1.9)
	local amplitude = 0.16 + waveSpike * 0.9 + math.min(0.22, waited / 90)
	local tint = COLOR.accent:Lerp(COLOR.danger, math.min(1, waveSpike))
	for index, bar in bars do
		local a = math.noise(index * 0.17, clock * 0.9)
		local b = math.noise(index * 0.53, clock * 2.7 + 40)
		local height = WAVE_H * amplitude * (a * 1.9 + b * 0.8)
		bar.Size = UDim2.fromOffset(bar.Size.X.Offset, math.clamp(math.abs(math.floor(height)), px(2), WAVE_H))
		bar.BackgroundColor3 = tint
	end

	-- Retombees des evenements de decrochage.
	if headerRestore > 0 and clock >= headerRestore then
		headerRestore = 0
		headerLabel.Text = spaced(TEXT.company)
		headerLabel.TextColor3 = COLOR.neutral
	end
	if ghostUntil > 0 and clock >= ghostUntil then
		ghostUntil = 0
		hero.Text = tracked(TEXT.title)
		heroGhost.TextTransparency = 1
		root.Position = rootHome
	end
	if dipUntil > 0 and clock >= dipUntil then
		dipUntil = 0
		dip.BackgroundTransparency = 1
	end
	if tearUntil > 0 and clock >= tearUntil then
		tearUntil = 0
		tear.BackgroundTransparency = 1
	end

	if quiet then
		return
	end

	-- DECROCHAGE DE LIAISON.
	--
	-- La cadence s'accelere avec l'attente : un chargement de deux secondes
	-- ne montre presque rien, un chargement de trente secondes montre un
	-- terminal qui lache. La degradation MESURE l'attente, comme le reste de
	-- l'ecran mesure le monde.
	glitchIn -= dt
	if glitchIn <= 0 then
		local pressure = math.min(1, waited / 24)
		glitchIn = (2.6 - pressure * 1.7) + math.random() * (2.4 - pressure * 1.6)

		local kind = math.random(1, 4)
		if kind == 1 then
			headerLabel.Text = scramble(spaced(TEXT.company), 4 + math.random(0, 4))
			headerLabel.TextColor3 = COLOR.danger
			headerRestore = clock + 0.13
		elseif kind == 2 then
			hero.Text = tracked(scramble(TEXT.title, 2))
			heroGhost.TextTransparency = 0.45
			root.Position = UDim2.fromOffset(math.random(-2, 2), math.random(-1, 1))
			ghostUntil = clock + 0.11
		elseif kind == 3 then
			dip.BackgroundTransparency = 0.42
			dipUntil = clock + 0.05
		else
			tear.Position = UDim2.fromScale(0, math.random())
			tear.BackgroundTransparency = 0.72
			tearUntil = clock + 0.06
		end
		waveSpike = math.max(waveSpike, 0.35 + pressure * 0.4)
	end

	-- Lignes d'ambiance. Elles n'annoncent aucune etape : elles disent ce que
	-- le terminal capte pendant qu'on attend, et ce qu'il capte n'est pas
	-- rassurant.
	ambientIn -= dt
	if ambientIn <= 0 and stageBusy > 0 then
		ambientIn = 2.2 + math.random() * 2.6
		log(TEXT.ambient[math.random(1, #TEXT.ambient)], COLOR.faint)
	end

	-- Le contrat se recite. Une phrase toutes les cinq secondes, brouillee au
	-- changement — la machine ne relit pas, elle re-transmet.
	creedIn -= dt
	if creedIn <= 0 then
		creedIn = 4
		creedIndex = creedIndex % #TEXT.creed + 1
		creed.Text = scramble(TEXT.creed[creedIndex], 6)
		creed.TextColor3 = COLOR.faint
		task.delay(0.14, function()
			if creed.Parent then
				creed.Text = TEXT.creed[creedIndex]
				creed.TextColor3 = COLOR.dim
			end
		end)
	end
end)

-- ------------------------------------------------------------ Etapes -----

local function beginStage(index: number)
	local row = rows[index]
	if not row then
		return
	end
	stageBusy = index
	row.active = true
	row.name.TextColor3 = COLOR.info
	row.detail.TextColor3 = COLOR.dim
	row.state.Text = TEXT.probing
	row.state.TextColor3 = COLOR.accent
	row.tick.BackgroundColor3 = COLOR.accent
	row.rule.BackgroundTransparency = 0.78
end

local function completeStage(index: number, ok: boolean)
	local row = rows[index]
	if row then
		row.active = false
		row.state.Text = if ok then TEXT.ready else TEXT.failed
		row.state.TextColor3 = if ok then COLOR.done else COLOR.danger
		row.tick.BackgroundColor3 = if ok then COLOR.done else COLOR.danger
		row.tick.BackgroundTransparency = 0
		row.name.TextColor3 = COLOR.neutral
		row.detail.TextColor3 = COLOR.faint
		row.rule.BackgroundTransparency = 0.9
	end
	local segment = segments[index]
	if segment then
		segment.BackgroundColor3 = if ok then COLOR.done else COLOR.danger
		segment.BackgroundTransparency = 0.05
	end
	waveSpike = 1
end

-- Attend qu'une condition soit vraie. Renvoie false sur delai depasse — et
-- l'appelant CONTINUE quand meme.
local function await(index: number, predicate: () -> boolean): boolean
	beginStage(index)

	local began = os.clock()
	local deadline = began + STAGE_TIMEOUT
	while os.clock() < deadline do
		if os.clock() - startedAt > TOTAL_TIMEOUT then
			break
		end
		local ok, result = pcall(predicate)
		if ok and result then
			-- La sonde a repondu ; on laisse la ligne se lire avant de la
			-- basculer.
			while os.clock() - began < STAGE_FLOOR do
				task.wait()
			end
			completeStage(index, true)
			log(TEXT.events[index], COLOR.neutral)
			return true
		end
		task.wait(0.1)
	end

	completeStage(index, false)
	log(`{TEXT.stages[index]}: timeout`, COLOR.danger)
	warn(`[Chargement] etape {index} ({TEXT.stages[index]}) : delai depasse, on continue`)
	return false
end

-- --- 1. liaison ----------------------------------------------------------

await(1, function()
	return game:IsLoaded()
end)

-- --- 2. secteur ----------------------------------------------------------
--
-- LE COEUR DE L'ECRAN. On ne compte pas des instances : on sonde verticale-
-- ment sous le personnage pour verifier qu'il y a quelque chose sur quoi se
-- poser. C'est ce test-la qui empeche d'apparaitre dans le vide pendant que
-- la carte finit d'arriver.

local floorDepth: number? = nil

await(2, function()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { character :: Instance }

	local hit = Workspace:Raycast(rootPart.Position + Vector3.new(0, 8, 0), Vector3.new(0, -FLOOR_PROBE, 0), parameters)
	if not hit then
		return false
	end
	floorDepth = hit.Distance - 8
	return true
end)

-- La profondeur affichee est celle que le raycast a rendue. C'est un detail
-- d'ambiance ET une trace de diagnostic : un chiffre absurde ici designe un
-- point d'apparition mal pose sur la carte.
if floorDepth then
	log(string.format("%s  -%.1f m", TEXT.depth, floorDepth), COLOR.neutral)
end

-- --- 3. equipement -------------------------------------------------------

await(3, function()
	if not playerGui:FindFirstChild("BlackoutHud") then
		return false
	end
	if not ReplicatedStorage:FindFirstChild("Remotes") then
		return false
	end
	return true
end)

-- Prechargement des pictogrammes. Hors de la condition d'etape : un asset
-- modere ou retire ne doit pas retenir le joueur devant l'ecran.
task.spawn(function()
	local assets = {}
	for _, id in ICONS do
		table.insert(assets, `rbxassetid://{id}`)
	end
	pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)
end)

-- --- 4. deploiement ------------------------------------------------------

local forced = not await(4, function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and (humanoid :: Humanoid).Health > 0
end)

-- ------------------------------------------------------- Autorisation ----
--
-- LE SILENCE D'ABORD. Tous les decrochages s'arretent net, le signal se
-- calme, l'ecran redevient propre — puis le cachet tombe. Un ecran qui
-- tremble encore pendant qu'il autorise le deploiement dirait que la societe
-- n'est pas sure d'elle ; elle l'est.

task.wait(TAIL_HOLD)

quiet = true
hero.Text = tracked(TEXT.title)
headerLabel.Text = spaced(TEXT.company)
headerLabel.TextColor3 = COLOR.neutral
heroGhost.TextTransparency = 1
dip.BackgroundTransparency = 1
tear.BackgroundTransparency = 1
root.Position = rootHome

task.wait(0.25)

local stampColor = if forced then COLOR.danger else COLOR.done

local stamp = frame({
	BackgroundColor3 = COLOR.void,
	BackgroundTransparency = 0.25,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(px(700), px(122)),
	ZIndex = 24,
})
new("UIStroke", { Color = stampColor, Thickness = px(2), Transparency = 0.2 }, stamp)

label({
	Text = if forced then TEXT.late else spaced(TEXT.authorized),
	Font = Enum.Font.Oswald,
	TextSize = if forced then px(22) else px(26),
	TextColor3 = stampColor,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, px(44)),
	Position = UDim2.fromOffset(0, px(26)),
	ZIndex = 25,
}, stamp)

label({
	Text = if forced then "" else TEXT.authorizedSub,
	TextSize = px(14),
	TextColor3 = COLOR.dim,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, px(20)),
	Position = UDim2.fromOffset(0, px(70)),
	ZIndex = 25,
}, stamp)

if forced then
	warn("[Chargement] deploiement force : au moins une etape n'a pas abouti")
end

-- Coup de contact : une nappe claire d'une image et demie. C'est le seul
-- moment de tout l'ecran ou quelque chose FRAPPE, et il tombe sur le cachet.
dip.BackgroundColor3 = COLOR.info
dip.BackgroundTransparency = 0.72
task.wait(0.06)
dip.BackgroundTransparency = 1
dip.BackgroundColor3 = COLOR.void

waveSpike = 1
task.wait(1.05)

-- ------------------------------------------------------------ Coupure ----
--
-- L'allumage joue a l'envers. Le terminal ne se ferme pas en fondu : il est
-- COUPE, l'image s'effondre sur une ligne, la ligne s'eteint. Le joueur est
-- lache dans le secteur au moment ou le tube s'eteint, pas avant.

heartbeat:Disconnect()
snapshot()

local off = new("Frame", {
	BackgroundColor3 = COLOR.info,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 30,
}, gui)

tween(0.18, function(t)
	applyAlpha(t)
	off.Size = UDim2.new(1, 0, 1 - t, 2)
	off.BackgroundTransparency = 0.86 - t * 0.61
end)

root.Visible = false

tween(0.2, function(t)
	off.Size = UDim2.new(1 - t * t, 0, 0, 2)
	off.BackgroundTransparency = 0.25 + t * 0.75
end)

print(
	`[Chargement] termine en {string.format("%.1f", os.clock() - startedAt)} s`
		.. ` — echelle finale {string.format("%.3f", canvasScale.Scale)}`
		.. (if forced then ", deploiement force" else "")
)

off:Destroy()
fitConnection:Disconnect()
task.wait(0.18)

-- Le rideau part en fondu, pas en coupure : le HUD joue sa propre sequence
-- d'allumage juste derriere, et un raccord net entre les deux ferait
-- clignoter l'ecran.
tween(0.55, function(t)
	curtain.BackgroundTransparency = t
end)

gui:Destroy()
