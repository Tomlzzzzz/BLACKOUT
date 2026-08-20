--!strict
-- Rapport de fin de raid.
--
-- L'ecran le plus important du jeu. Le commanditaire vous a envoye, vous a
-- regarde travailler, et il classe maintenant l'operation. Le document a un
-- en-tete, un bandeau de classement, un numero de dossier, un manifeste
-- chiffre et une EVALUATION. Le joueur n'est pas felicite : il est note.
--
-- LES TROIS ISSUES PARTAGENT CE DOCUMENT
--
-- Mort, extrait, ou lache par la fermeture de la fenetre : meme formulaire,
-- memes colonnes. Un ecran de defaite bricole a cote d'un bel ecran de
-- victoire dirait que l'echec compte moins, alors que c'est l'issue la plus
-- frequente.
--
-- OU VIT L'HORREUR
--
-- Pas dans le texte — le texte reste administratif, c'est ce qui le rend
-- froid. Elle vit dans L'ETAT DU DOCUMENT : le meme formulaire sort d'une
-- machine qui va bien pour une extraction, et d'une machine dont la liaison
-- se degrade pour une perte d'actif. Balayage plus marque, bords qui
-- noircissent, tremblement a l'ouverture, verdict mal imprime — tout cela
-- vient de `Theme.debrief.grain`, une ligne par issue. Voir aussi la
-- desynchronisation d'impression du verdict, plus bas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemDatabase = require(Shared.ItemDatabase)
local Locale = require(Shared.Locale)
local Types = require(Shared.Types)

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local DebriefWidget = {}

type RaidReport = Types.RaidReport

-- Une apparition differee. `at` est la date, en secondes depuis l'ouverture,
-- a laquelle l'element commence a se reveler ; `slide` son decalage initial
-- en pixels, qui donne l'impression que la ligne arrive par la gauche.
type Reveal = {
	instances: { GuiObject },
	at: number,
	slide: number,
	progress: number,
	basePosition: { [GuiObject]: UDim2 },
	baseAlpha: { [GuiObject]: number },
}

-- Un nombre qui defile. Le montant verse ne se pose pas : il compte.
type Roll = {
	label: TextLabel,
	target: number,
	shown: number,
}

type Row = {
	root: Frame,
	quantity: TextLabel,
	name: TextLabel,
	value: TextLabel,
}

type LogEntry = {
	root: Frame,
	label: TextLabel,
	value: TextLabel,
}

export type Widget = {
	gui: ScreenGui,
	scrim: Frame,
	card: Frame,
	scale: UIScale,
	stroke: UIStroke,
	accentRule: Frame,
	scanlines: { Frame },
	vignette: { Frame },
	brackets: { Frame },
	sprockets: { Frame },

	company: TextLabel,
	subheader: TextLabel,
	dossier: TextLabel,
	archived: TextLabel,
	classChip: Frame,
	classLabel: TextLabel,

	outcome: TextLabel,
	outcomeGhost: TextLabel,
	cause: TextLabel,

	stamp: Frame,
	stampStroke: UIStroke,
	stampLabel: TextLabel,

	manifestTitle: TextLabel,
	rows: { Row },
	manifestRule: Frame,
	totalLabel: TextLabel,
	totalValue: TextLabel,
	leftBehind: TextLabel,

	logTitle: TextLabel,
	entries: { LogEntry },
	contractLabel: TextLabel,

	balanceRule: Frame,
	cargoLabel: TextLabel,
	bonusLabel: TextLabel,
	paidCaption: TextLabel,
	paidValue: TextLabel,
	accountLabel: TextLabel,
	xpLabel: TextLabel,

	closing: TextLabel,
	dismiss: TextLabel,

	reveals: { Reveal },
	-- Position ET opacite d'origine, relevees une seule fois. Les relire a
	-- chaque ouverture les prendrait dans l'etat laisse par la fermeture
	-- precedente — voir le commentaire de `reveal`.
	origins: { [GuiObject]: UDim2 },
	alphas: { [GuiObject]: number },
	rolls: { Roll },

	open: boolean,
	clock: number,
	hold: number,
	remaining: number,
	scanOffset: number,
	glitch: number,
	outcomeText: string,
	grain: { scanline: number, vignette: number, jitter: number, decay: number },
	report: RaidReport?,
}

local PADDING = 26
local ROW_STEP = 27
local ROW_HEIGHT = 22
local LEFT_WIDTH = 470
local RIGHT_OFFSET = 520
local RIGHT_WIDTH = 334

-- Ordonnees de reference, en pixels de document. Rassemblees pour que la
-- mise en page se relise d'un coup au lieu d'etre dispersee dans trois cents
-- lignes de fabrique.
local Y = {
	company = 14,
	subheader = 36,
	dossier = 16,
	archived = 34,
	classChip = 52,
	headerRule = 78,
	verdict = 90,
	cause = 148,
	stamp = 124,
	columnTitle = 186,
	rowsTop = 212,
	logTop = 214,
	logStep = 32,
	contract = 388,
	balanceRule = 470,
	cargo = 486,
	bonus = 512,
	account = 538,
	paidCaption = 476,
	paid = 494,
	xp = 572,
	footerRule = 602,
	footer = 618,
}

-- --------------------------------------------------------------- Outils --

local function mmss(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Applique une opacite a n'importe quel type d'element.
--
-- Les widgets melangent TextLabel, Frame et UIStroke ; sans ce guichet
-- unique, chaque animation devrait connaitre le type de ce qu'elle anime, et
-- les contours resteraient figes pendant que le texte s'efface.
local function setAlpha(instance: GuiObject, base: number, alpha: number)
	local value = 1 - (1 - base) * alpha

	if instance:IsA("TextLabel") then
		instance.TextTransparency = value
		local stroke = instance:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = value
		end
	else
		instance.BackgroundTransparency = value
	end
end

local function baseAlphaOf(instance: GuiObject): number
	if instance:IsA("TextLabel") then
		return instance.TextTransparency
	end
	return instance.BackgroundTransparency
end

-- ------------------------------------------------------------ Fabrique ---

local function label(props: Components.LabelProps, parent: Instance): TextLabel
	props.zIndex = props.zIndex or 22
	return Components.label(props, parent)
end

local function rule(parent: Instance, position: UDim2, size: UDim2, color: Color3): Frame
	return Components.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		ZIndex = 22,
	}, parent) :: Frame
end

-- Equerres d'angle, quatre coins, deux barres chacune.
--
-- Reprises du vocabulaire des panneaux du HUD. C'est le detail qui fait lire
-- un cadre comme un instrument plutot que comme une boite — et qui rattache
-- le rapport au reste de l'interface au lieu d'en faire un ecran a part.
local function buildBrackets(card: Frame): { Frame }
	local out: { Frame } = {}
	local length = Theme.debrief.bracketLength
	local thickness = Theme.debrief.bracketThickness

	for _, corner in {
		{ x = 0, y = 0 },
		{ x = 1, y = 0 },
		{ x = 0, y = 1 },
		{ x = 1, y = 1 },
	} do
		local anchor = Vector2.new(corner.x, corner.y)
		local position = UDim2.fromScale(corner.x, corner.y)

		for _, size in { UDim2.fromOffset(length, thickness), UDim2.fromOffset(thickness, length) } do
			table.insert(
				out,
				Components.new("Frame", {
					BackgroundColor3 = Theme.color.extraction,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AnchorPoint = anchor,
					Position = position,
					Size = size,
					ZIndex = 27,
				}, card) :: Frame
			)
		end
	end

	return out
end

-- Perforations le long du bord gauche, comme une bande sortie d'imprimante.
local function buildSprockets(card: Frame): { Frame }
	local out: { Frame } = {}
	local spacing = Theme.debrief.sprocketSpacing

	for offset = spacing, Theme.debrief.height - spacing, spacing do
		table.insert(
			out,
			Components.new("Frame", {
				BackgroundColor3 = Theme.color.separator,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(9, offset),
				Size = UDim2.fromOffset(4, 4),
				ZIndex = 23,
			}, card) :: Frame
		)
	end

	return out
end

-- Noircissement des bords interieurs.
--
-- Quatre bandes en degrade plutot qu'une image : aucun asset a televerser, et
-- l'intensite se pilote par l'opacite depuis `step`.
local function buildVignette(card: Frame): { Frame }
	local out: { Frame } = {}

	-- SENS DU DEGRADE, a ne pas se tromper.
	--
	-- Le premier point d'arret (0) est du cote d'ou part la rotation. Il doit
	-- porter l'opacite PLEINE, cote bord ; le second (1) est transparent, cote
	-- interieur. Inverses, les quatre bandes assombrissent le MILIEU du
	-- document : on obtient deux barres horizontales en travers de la page et
	-- des bords parfaitement nets — exactement l'inverse d'une vignette.
	--
	-- La rotation designe donc le bord concerne : 90 = haut, 270 = bas,
	-- 0 = gauche, 180 = droite.
	--
	-- Les bandes restent COURTES a dessein. Une vignette qui mord jusqu'au
	-- texte degrade la lisibilite, et ce document porte des chiffres dont
	-- depend une decision de jeu.
	local edges = {
		{ size = UDim2.new(1, 0, 0, 44), position = UDim2.fromScale(0, 0), anchor = Vector2.new(0, 0), rotation = 90 },
		{ size = UDim2.new(1, 0, 0, 44), position = UDim2.fromScale(0, 1), anchor = Vector2.new(0, 1), rotation = 270 },
		{ size = UDim2.new(0, 56, 1, 0), position = UDim2.fromScale(0, 0), anchor = Vector2.new(0, 0), rotation = 0 },
		{ size = UDim2.new(0, 56, 1, 0), position = UDim2.fromScale(1, 0), anchor = Vector2.new(1, 0), rotation = 180 },
	}

	for _, edge in edges do
		local frame = Components.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = edge.anchor,
			Position = edge.position,
			Size = edge.size,
			ZIndex = 26,
		}, card) :: Frame

		Components.new("UIGradient", {
			Rotation = edge.rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, frame)

		table.insert(out, frame)
	end

	return out
end

function DebriefWidget.create(playerGui: PlayerGui): Widget
	local existing = playerGui:FindFirstChild("BlackoutDebrief")
	if existing then
		existing:Destroy()
	end

	-- ScreenGui distinct du HUD, au-dessus de lui. Le rapport COUVRE le jeu.
	local gui = Components.new("ScreenGui", {
		Name = "BlackoutDebrief",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Enabled = false,
	}, playerGui) :: ScreenGui

	local scrim = Components.new("Frame", {
		Name = "Scrim",
		BackgroundColor3 = Theme.color.void,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
	}, gui) :: Frame

	local card = Components.new("Frame", {
		Name = "Report",
		BackgroundColor3 = Theme.color.panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.debrief.width, Theme.debrief.height),
		ClipsDescendants = true,
		ZIndex = 21,
	}, gui) :: Frame

	-- Le document a une taille en PIXELS, pas en fraction d'ecran : sa mise
	-- en page (deux colonnes, sept lignes de manifeste) ne survivrait pas a
	-- un etirement. C'est donc l'echelle qui l'adapte, jamais la mise en
	-- page — et elle est bornee pour qu'il tienne dans la fenetre.
	local scale = Components.new("UIScale", { Scale = 1 }, card) :: UIScale

	Components.new("UICorner", { CornerRadius = UDim.new(0, Theme.panel.corner) }, card)
	local stroke = Components.new("UIStroke", {
		Color = Theme.color.border,
		Thickness = 1,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, card) :: UIStroke

	-- Filet d'accent en tete de document. C'est lui qui porte la couleur de
	-- l'issue : le reste du rapport reste neutre, comme un formulaire.
	local accentRule = Components.new("Frame", {
		BackgroundColor3 = Theme.color.extraction,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 3),
		ZIndex = 24,
	}, card) :: Frame

	local sprockets = buildSprockets(card)
	local brackets = buildBrackets(card)
	local vignette = buildVignette(card)

	local scanlines: { Frame } = {}
	for index = 1, Theme.debrief.scanlines do
		table.insert(
			scanlines,
			Components.new("Frame", {
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, (index - 1) / Theme.debrief.scanlines),
				Size = UDim2.new(1, 0, 0, 1),
				ZIndex = 30,
			}, card) :: Frame
		)
	end

	-- --- en-tete ---------------------------------------------------------

	local company = label({
		text = Components.spaced(Locale.t("debrief.header")),
		size = Theme.debrief.type.company,
		color = Theme.color.neutral,
		sizeUDim = UDim2.new(0, 470, 0, 20),
		position = UDim2.fromOffset(PADDING, Y.company),
	}, card)

	local subheader = label({
		text = Components.spaced(Locale.t("debrief.subheader")),
		size = Theme.debrief.type.subheader,
		color = Theme.color.dim,
		sizeUDim = UDim2.new(0, 470, 0, 16),
		position = UDim2.fromOffset(PADDING, Y.subheader),
	}, card)

	local dossier = label({
		text = "",
		size = Theme.debrief.type.dossier,
		font = Theme.font.mono,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Right,
		sizeUDim = UDim2.new(0, 340, 0, 18),
		position = UDim2.new(1, -PADDING - 340, 0, Y.dossier),
	}, card)

	-- Bandeau de classement : petite pastille pleine, texte sombre dessus.
	-- Un formulaire d'entreprise se lit d'abord a son tampon de categorie ;
	-- c'est aussi ce qui nomme l'issue AVANT que le verdict ne s'affiche.
	-- ATTENTION : la pastille nait a son opacite FINALE, pas a 1.
	-- `reveal` releve l'opacite de reference a la premiere apparition ;
	-- une pastille creee transparente aurait 1 pour reference et ne
	-- pourrait jamais apparaitre. C'est le meme piege qui rendait le
	-- deuxieme rapport entierement vide.
	local classChip = Components.new("Frame", {
		BackgroundColor3 = Theme.color.extraction,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PADDING, 0, Y.classChip),
		Size = UDim2.fromOffset(210, 18),
		ZIndex = 23,
	}, card) :: Frame

	local classLabel = label({
		text = "",
		size = Theme.debrief.type.classification,
		color = Theme.color.void,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.fromScale(1, 1),
		zIndex = 24,
	}, classChip)

	local archived = label({
		text = Components.spaced(Locale.t("debrief.archived")),
		size = Theme.debrief.type.subheader,
		color = Theme.color.faint,
		align = Enum.TextXAlignment.Right,
		sizeUDim = UDim2.new(0, 340, 0, 16),
		position = UDim2.new(1, -PADDING - 340, 0, Y.archived),
	}, card)

	rule(
		card,
		UDim2.fromOffset(PADDING, Y.headerRule),
		UDim2.new(1, -PADDING * 2, 0, 1),
		Theme.color.separator
	)

	-- --- verdict ---------------------------------------------------------

	-- DESYNCHRONISATION D'IMPRESSION.
	--
	-- Un double du verdict, decale de trois pixels, dans la couleur de
	-- l'issue. Les canaux d'une mauvaise impression ne se superposent pas
	-- exactement ; c'est ce leger dedoublement qui fait qu'on lit une page
	-- sortie d'une machine fatiguee plutot qu'un titre pose au propre.
	--
	-- Il est cree AVANT le verdict lui-meme pour rester derriere.
	local outcomeGhost = label({
		text = "",
		size = Theme.debrief.type.verdict,
		font = Theme.font.hero,
		color = Theme.color.danger,
		transparency = 0.74,
		sizeUDim = UDim2.new(0, 560, 0, 52),
		position = UDim2.fromOffset(PADDING + 3, Y.verdict + 2),
		zIndex = 21,
	}, card)

	local outcome = label({
		text = "",
		size = Theme.debrief.type.verdict,
		font = Theme.font.hero,
		color = Theme.color.info,
		sizeUDim = UDim2.new(0, 560, 0, 52),
		position = UDim2.fromOffset(PADDING, Y.verdict),
	}, card)

	local cause = label({
		text = "",
		size = Theme.debrief.type.cause,
		color = Theme.color.neutral,
		sizeUDim = UDim2.new(0, 560, 0, 20),
		position = UDim2.fromOffset(PADDING, Y.cause),
	}, card)

	-- Le tampon d'evaluation. Legerement de travers, parce qu'un tampon pose
	-- a la main ne l'est jamais droit — et c'est ce detail qui fait passer le
	-- bloc de « libelle colore » a « document tamponne ».
	local stamp = Components.new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -PADDING, 0, Y.stamp),
		Size = UDim2.fromOffset(252, 56),
		Rotation = -4,
		ZIndex = 23,
	}, card) :: Frame

	local stampStroke = Components.new("UIStroke", {
		Color = Theme.color.extraction,
		Thickness = 3,
		Transparency = 1,
	}, stamp) :: UIStroke

	local stampLabel = label({
		text = "",
		size = Theme.debrief.type.stamp,
		font = Theme.font.hero,
		color = Theme.color.extraction,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.fromScale(1, 1),
		zIndex = 24,
	}, stamp)

	-- --- colonne gauche : manifeste --------------------------------------

	local manifestTitle = label({
		text = "",
		size = Theme.debrief.type.columnTitle,
		color = Theme.color.dim,
		sizeUDim = UDim2.new(0, LEFT_WIDTH, 0, 16),
		position = UDim2.fromOffset(PADDING, Y.columnTitle),
	}, card)

	local rows: { Row } = {}
	for index = 1, Config.Debrief.manifestLimit + 1 do
		local top = Y.rowsTop + (index - 1) * ROW_STEP

		local root = Components.new("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(PADDING, top),
			Size = UDim2.fromOffset(LEFT_WIDTH, ROW_HEIGHT),
			Visible = false,
			ZIndex = 22,
		}, card) :: Frame

		table.insert(rows, {
			root = root,
			quantity = label({
				text = "",
				size = Theme.debrief.type.rowQuantity,
				font = Theme.font.mono,
				color = Theme.color.dim,
				sizeUDim = UDim2.fromOffset(46, ROW_HEIGHT),
			}, root),
			name = label({
				text = "",
				size = Theme.debrief.type.rowName,
				color = Theme.color.info,
				sizeUDim = UDim2.fromOffset(288, ROW_HEIGHT),
				position = UDim2.fromOffset(52, 0),
			}, root),
			-- Aligne a droite, donc deja en colonne : la chasse fixe
			-- n'apporterait rien et ferait disparaitre le separateur de
			-- milliers, que RobotoMono ne rend pas.
			value = label({
				text = "",
				size = Theme.debrief.type.rowValue,
				color = Theme.color.amber,
				align = Enum.TextXAlignment.Right,
				sizeUDim = UDim2.fromOffset(126, ROW_HEIGHT),
				position = UDim2.fromOffset(LEFT_WIDTH - 126, 0),
			}, root),
		})
	end

	local manifestRuleY = Y.rowsTop + (Config.Debrief.manifestLimit + 1) * ROW_STEP + 6
	local manifestRule = rule(
		card,
		UDim2.fromOffset(PADDING, manifestRuleY),
		UDim2.fromOffset(LEFT_WIDTH, 1),
		Theme.color.separator
	)

	local totalTop = manifestRuleY + 12

	local totalLabel = label({
		text = Components.spaced(Locale.t("debrief.manifest.total")),
		size = Theme.debrief.type.totalLabel,
		color = Theme.color.neutral,
		sizeUDim = UDim2.fromOffset(240, 26),
		position = UDim2.fromOffset(PADDING, totalTop),
	}, card)

	local totalValue = label({
		text = "0",
		size = Theme.debrief.type.totalValue,
		font = Theme.font.hero,
		color = Theme.color.amber,
		align = Enum.TextXAlignment.Right,
		sizeUDim = UDim2.fromOffset(220, 26),
		position = UDim2.fromOffset(PADDING + LEFT_WIDTH - 220, totalTop - 3),
	}, card)

	local leftBehind = label({
		text = "",
		size = Theme.debrief.type.subheader,
		color = Theme.color.danger,
		sizeUDim = UDim2.fromOffset(LEFT_WIDTH, 16),
		position = UDim2.fromOffset(PADDING, totalTop + 30),
	}, card)

	-- --- colonne droite : releve -----------------------------------------
	--
	-- Le libelle prend 224 des 334 pixels de la colonne. Ce partage est
	-- dicte par le FRANCAIS : espace lettre a lettre, « ELIMINATIONS » et
	-- « PIC DE MENACE » sont nettement plus longs que leurs equivalents
	-- anglais, alors que les valeurs restent des nombres a trois chiffres.
	local logTitle = label({
		text = Components.spaced(Locale.t("debrief.log.title")),
		size = Theme.debrief.type.columnTitle,
		color = Theme.color.dim,
		sizeUDim = UDim2.new(0, RIGHT_WIDTH, 0, 16),
		position = UDim2.fromOffset(RIGHT_OFFSET, Y.columnTitle),
	}, card)

	local entries: { LogEntry } = {}
	for index = 1, 5 do
		local top = Y.logTop + (index - 1) * Y.logStep

		local root = Components.new("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(RIGHT_OFFSET, top),
			Size = UDim2.fromOffset(RIGHT_WIDTH, 26),
			ZIndex = 22,
		}, card) :: Frame

		table.insert(entries, {
			root = root,
			label = label({
				text = "",
				size = Theme.debrief.type.logLabel,
				color = Theme.color.dim,
				sizeUDim = UDim2.fromOffset(224, 26),
			}, root),
			value = label({
				text = "",
				size = Theme.debrief.type.logValue,
				font = Theme.font.hero,
				color = Theme.color.info,
				align = Enum.TextXAlignment.Right,
				sizeUDim = UDim2.fromOffset(104, 26),
				position = UDim2.fromOffset(230, 0),
			}, root),
		})
	end

	local contractLabel = label({
		text = "",
		size = Theme.debrief.type.logLabel,
		color = Theme.color.neutral,
		sizeUDim = UDim2.fromOffset(RIGHT_WIDTH, 20),
		position = UDim2.fromOffset(RIGHT_OFFSET, Y.contract),
	}, card)

	-- --- bilan -----------------------------------------------------------
	--
	-- Les libelles de gauche n'utilisent PAS la police a chasse fixe,
	-- contrairement aux releves techniques : RobotoMono ne rend pas l'espace
	-- fine insecable de Components.group, et « 40 135 » s'affichait « 40135 »
	-- a cote d'un total correctement groupe.
	local balanceRule = rule(
		card,
		UDim2.fromOffset(PADDING, Y.balanceRule),
		UDim2.new(1, -PADDING * 2, 0, 1),
		Theme.color.separator
	)

	local cargoLabel = label({
		text = "",
		size = Theme.debrief.type.balance,
		color = Theme.color.neutral,
		sizeUDim = UDim2.fromOffset(470, 22),
		position = UDim2.fromOffset(PADDING, Y.cargo),
	}, card)

	local bonusLabel = label({
		text = "",
		size = Theme.debrief.type.balance,
		color = Theme.color.neutral,
		sizeUDim = UDim2.fromOffset(470, 22),
		position = UDim2.fromOffset(PADDING, Y.bonus),
	}, card)

	local accountLabel = label({
		text = "",
		size = Theme.debrief.type.balance,
		color = Theme.color.dim,
		sizeUDim = UDim2.fromOffset(470, 22),
		position = UDim2.fromOffset(PADDING, Y.account),
	}, card)

	local paidCaption = label({
		text = "",
		size = Theme.debrief.type.paidCaption,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Right,
		sizeUDim = UDim2.fromOffset(340, 16),
		position = UDim2.new(1, -PADDING - 340, 0, Y.paidCaption),
	}, card)

	local paidValue = label({
		text = "0",
		size = Theme.debrief.type.paid,
		font = Theme.font.hero,
		color = Theme.color.extraction,
		align = Enum.TextXAlignment.Right,
		sizeUDim = UDim2.fromOffset(340, 72),
		position = UDim2.new(1, -PADDING - 340, 0, Y.paid),
	}, card)

	local xpLabel = label({
		text = "",
		size = Theme.debrief.type.balance,
		color = Theme.color.cyan,
		align = Enum.TextXAlignment.Right,
		sizeUDim = UDim2.fromOffset(340, 22),
		position = UDim2.new(1, -PADDING - 340, 0, Y.xp),
	}, card)

	-- --- pied de page ----------------------------------------------------

	rule(
		card,
		UDim2.fromOffset(PADDING, Y.footerRule),
		UDim2.new(1, -PADDING * 2, 0, 1),
		Theme.color.separator
	)

	local closing = label({
		text = "",
		size = Theme.debrief.type.closing,
		color = Theme.color.neutral,
		sizeUDim = UDim2.new(0, 560, 0, 24),
		position = UDim2.fromOffset(PADDING, Y.footer),
	}, card)

	local dismiss = label({
		text = "",
		size = Theme.debrief.type.dismiss,
		font = Theme.font.mono,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Right,
		sizeUDim = UDim2.fromOffset(260, 24),
		position = UDim2.new(1, -PADDING - 260, 0, Y.footer),
	}, card)

	return {
		gui = gui,
		scrim = scrim,
		card = card,
		scale = scale,
		stroke = stroke,
		accentRule = accentRule,
		scanlines = scanlines,
		vignette = vignette,
		brackets = brackets,
		sprockets = sprockets,

		company = company,
		subheader = subheader,
		dossier = dossier,
		archived = archived,
		classChip = classChip,
		classLabel = classLabel,

		outcome = outcome,
		outcomeGhost = outcomeGhost,
		cause = cause,

		stamp = stamp,
		stampStroke = stampStroke,
		stampLabel = stampLabel,

		manifestTitle = manifestTitle,
		rows = rows,
		manifestRule = manifestRule,
		totalLabel = totalLabel,
		totalValue = totalValue,
		leftBehind = leftBehind,

		logTitle = logTitle,
		entries = entries,
		contractLabel = contractLabel,

		balanceRule = balanceRule,
		cargoLabel = cargoLabel,
		bonusLabel = bonusLabel,
		paidCaption = paidCaption,
		paidValue = paidValue,
		accountLabel = accountLabel,
		xpLabel = xpLabel,

		closing = closing,
		dismiss = dismiss,

		reveals = {},
		origins = {},
		alphas = {},
		rolls = {},

		open = false,
		clock = 0,
		hold = 0,
		remaining = 0,
		scanOffset = 0,
		glitch = 0,
		outcomeText = "",
		grain = Theme.debrief.grain.EXTRACTED,
		report = nil,
	}
end

-- ------------------------------------------------------------ Ouverture --

local function reveal(widget: Widget, instances: { GuiObject }, at: number, slide: number)
	local basePosition: { [GuiObject]: UDim2 } = {}
	local baseAlpha: { [GuiObject]: number } = {}

	for _, instance in instances do
		-- Position ET opacite d'origine sont relevees ENSEMBLE, une seule
		-- fois, a la premiere apparition de l'element.
		--
		-- Les relire a chaque ouverture les prendrait dans l'etat laisse par
		-- la fermeture precedente, c'est-a-dire invisible : l'opacite de
		-- reference deviendrait 1, et `setAlpha` calculerait alors
		-- 1 - (1 - 1) * alpha = 1 quel que soit l'avancement. Le deuxieme
		-- rapport de la partie s'ouvrait entierement VIDE — cadre, filet
		-- d'accent et tampon presents, pas une ligne de texte.
		if widget.origins[instance] == nil then
			widget.origins[instance] = instance.Position
			widget.alphas[instance] = baseAlphaOf(instance)
		end
		instance.Position = widget.origins[instance]
		basePosition[instance] = widget.origins[instance]
		baseAlpha[instance] = widget.alphas[instance]
		setAlpha(instance, baseAlpha[instance], 0)
	end

	table.insert(widget.reveals, {
		instances = instances,
		at = at,
		slide = slide,
		progress = 0,
		basePosition = basePosition,
		baseAlpha = baseAlpha,
	})
end

local function roll(widget: Widget, target: TextLabel, value: number)
	-- Remise a zero du libelle : sans elle, un rapport ou rien n'est verse
	-- garderait a l'ecran le montant du rapport precedent, faute de
	-- defilement pour l'ecraser.
	target.Text = "0"
	table.insert(widget.rolls, { label = target, target = value, shown = 0 })
end

local function itemName(itemId: string): string
	local translated = Locale.maybe(`item.{itemId}`)
	if translated then
		return translated
	end
	local definition = ItemDatabase.get(itemId)
	return if definition then definition.name else itemId
end

-- Ajuste l'echelle du document a la fenetre.
--
-- Deux contraintes qui ne vont pas dans le meme sens : la DENSITE, pour
-- qu'un ecran 4K n'affiche pas un rapport minuscule, et l'ENCOMBREMENT, pour
-- qu'un telephone n'en affiche pas un rapport coupe. On garde la plus petite
-- des deux : mieux vaut un document un peu tasse qu'un document dont le
-- bilan sort de l'ecran.
local function fit(widget: Widget)
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)

	-- Une fenetre Studio non rendue annonce 1x1. On ne recalcule pas sur une
	-- mesure pareille, sinon l'echelle tombe a son plancher.
	if viewport.X < 2 or viewport.Y < 2 then
		return
	end

	local density = math.clamp(
		viewport.Y / Config.Hud.referenceHeight,
		Config.Hud.densityRange.min,
		Config.Hud.densityRange.max
	) * Config.Hud.globalScale

	local margin = 32
	local room = math.min(
		(viewport.X - margin) / Theme.debrief.width,
		(viewport.Y - margin) / Theme.debrief.height
	)

	local wanted = math.max(0.35, math.min(density, room))
	if math.abs(widget.scale.Scale - wanted) > 0.001 then
		widget.scale.Scale = wanted
	end
end

function DebriefWidget.show(widget: Widget, report: RaidReport)
	fit(widget)
	table.clear(widget.reveals)
	table.clear(widget.rolls)

	widget.report = report
	widget.open = true
	widget.clock = 0
	widget.glitch = 0
	widget.hold = Theme.debrief.holdTime[report.outcome] or 16
	widget.remaining = widget.hold
	widget.grain = Theme.debrief.grain[report.outcome] or Theme.debrief.grain.EXTRACTED

	local accent = Theme.debrief.accent[report.outcome] or Theme.color.info
	local extracted = report.outcome == "EXTRACTED"
	local timing = Theme.debrief.timing

	widget.accentRule.BackgroundColor3 = accent
	widget.classChip.BackgroundColor3 = accent
	widget.stampStroke.Color = accent
	widget.stampLabel.TextColor3 = accent
	widget.outcome.TextColor3 = if extracted then Theme.color.info else accent
	widget.outcomeGhost.TextColor3 = accent
	widget.paidValue.TextColor3 = if extracted then accent else Theme.color.faint

	for _, bracket in widget.brackets do
		bracket.BackgroundColor3 = accent
	end

	-- --- textes ----------------------------------------------------------

	widget.dossier.Text = `{Locale.t("debrief.dossier")}  {report.reference}`
	widget.classLabel.Text = Locale.t(`debrief.class.{report.outcome}`)

	widget.outcomeText = Locale.t(`debrief.outcome.{report.outcome}`)
	widget.outcome.Text = widget.outcomeText
	widget.outcomeGhost.Text = widget.outcomeText

	local zoneName = if report.zone then (Locale.maybe(`zone.{report.zone}`) or report.zone) else ""
	widget.cause.Text = Locale.t(`debrief.cause.{report.outcome}`, {
		zone = zoneName,
		duration = mmss(report.duration),
	})

	widget.stampLabel.Text = Locale.t(`debrief.rating.{report.rating}`)

	widget.manifestTitle.Text = Components.spaced(
		Locale.t(if extracted then "debrief.manifest.recovered" else "debrief.manifest.lost")
	)

	-- --- manifeste -------------------------------------------------------

	local rowTime = timing.rowFirst
	local shownRows = 0

	for index, row in widget.rows do
		local line = report.manifest[index]
		if line then
			shownRows = index
			row.root.Visible = true
			row.quantity.Text = `{line.quantity}x`
			row.name.Text = itemName(line.id)
			row.value.Text = Components.group(line.value)
			row.value.TextColor3 = if extracted then Theme.color.amber else Theme.color.dangerDeep
			row.name.TextColor3 = if extracted then Theme.color.info else Theme.color.neutral

			reveal(widget, { row.quantity, row.name, row.value }, rowTime, 16)
			rowTime += timing.rowStep
		else
			row.root.Visible = false
		end
	end

	-- Ligne d'agregation. Elle occupe la case suivante, ce qui la place
	-- naturellement sous la derniere ligne detaillee sans calcul de position.
	if report.overflowCount > 0 then
		local slot = widget.rows[math.min(shownRows + 1, #widget.rows)]
		if slot then
			slot.root.Visible = true
			slot.quantity.Text = ""
			slot.name.Text = Locale.t("debrief.manifest.overflow", { count = report.overflowCount })
			slot.name.TextColor3 = Theme.color.dim
			slot.value.Text = Components.group(report.overflowValue)
			slot.value.TextColor3 = Theme.color.dim
			reveal(widget, { slot.quantity, slot.name, slot.value }, rowTime, 16)
			rowTime += timing.rowStep
		end
	elseif #report.manifest == 0 then
		local slot = widget.rows[1]
		if slot then
			slot.root.Visible = true
			slot.quantity.Text = ""
			slot.name.Text = Locale.t("debrief.manifest.empty")
			slot.name.TextColor3 = Theme.color.faint
			slot.value.Text = ""
			reveal(widget, { slot.quantity, slot.name, slot.value }, rowTime, 16)
			rowTime += timing.rowStep
		end
	end

	widget.totalValue.TextColor3 = if extracted then Theme.color.amber else Theme.color.dangerDeep
	roll(widget, widget.totalValue, report.manifestValue)

	widget.leftBehind.Text = if report.leftBehind > 0
		then Locale.t("debrief.manifest.leftBehind", { count = report.leftBehind })
		else ""

	-- --- releve ----------------------------------------------------------

	local logValues = {
		{ key = "debrief.log.kills", text = tostring(report.kills) },
		{ key = "debrief.log.damage", text = tostring(report.damageTaken) },
		{ key = "debrief.log.peak", text = tostring(report.peakThreat) },
		{ key = "debrief.log.objectives", text = `{report.objectivesDone}/{report.objectivesTotal}` },
		{ key = "debrief.log.duration", text = mmss(report.duration) },
	}

	for index, entry in widget.entries do
		local source = logValues[index]
		entry.label.Text = Components.spaced(Locale.t(source.key))
		entry.value.Text = source.text
	end

	-- Le pic de menace se colore : c'est le seul releve qui raconte un danger
	-- plutot qu'un compte.
	local peakBand = "SAFE"
	if report.peakThreat >= 86 then
		peakBand = "CRITICAL"
	elseif report.peakThreat >= 61 then
		peakBand = "SEVERE"
	elseif report.peakThreat >= 31 then
		peakBand = "DANGER"
	elseif report.peakThreat >= 11 then
		peakBand = "ALERT"
	end
	widget.entries[3].value.TextColor3 = Theme.threat.color[peakBand]

	if report.objectivesTotal > 0 then
		widget.contractLabel.Text = Locale.t(
			if report.contractComplete then "debrief.contract.complete" else "debrief.contract.failed"
		)
		widget.contractLabel.TextColor3 = if report.contractComplete
			then Theme.color.extraction
			else Theme.color.dim
	else
		widget.contractLabel.Text = ""
	end

	-- --- bilan -----------------------------------------------------------

	widget.cargoLabel.Text = `{Locale.t("debrief.balance.cargo")}   {Components.group(report.manifestValue)}`
	-- Poste NON SERVI plutot que ligne absente. Un trou dans le bilan se
	-- lit comme un oubli de mise en page ; un tiret se lit comme une
	-- case que le commanditaire a laissee vide, ce qui est le sujet.
	widget.bonusLabel.Text = if extracted
		then `{Locale.t("debrief.balance.bonus")}   {Components.group(report.bonus)}`
		else `{Locale.t("debrief.balance.bonus")}   —`
	widget.bonusLabel.TextColor3 = if extracted then Theme.color.neutral else Theme.color.faint
	widget.cargoLabel.TextColor3 = if extracted then Theme.color.neutral else Theme.color.faint

	widget.paidCaption.Text = Components.spaced(
		Locale.t(if extracted then "debrief.balance.paid" else "debrief.balance.nothing")
	)
	roll(widget, widget.paidValue, report.credits)

	widget.accountLabel.Text = `{Locale.t("debrief.balance.account")}   {Components.group(report.balance)}`

	if report.leveledUp then
		widget.xpLabel.Text = Locale.t("debrief.balance.levelUp", { level = report.level })
		widget.xpLabel.TextColor3 = Theme.color.extraction
	elseif report.xpGained > 0 then
		widget.xpLabel.Text = `{Locale.t("debrief.balance.xp")}  +{report.xpGained}    `
			.. Locale.t("debrief.balance.level", { level = report.level })
		widget.xpLabel.TextColor3 = Theme.color.cyan
	else
		widget.xpLabel.Text = Locale.t("debrief.balance.level", { level = report.level })
		widget.xpLabel.TextColor3 = Theme.color.dim
	end

	widget.closing.Text = Locale.t(`debrief.closing.{report.outcome}`)

	-- --- calendrier d'impression -----------------------------------------

	reveal(widget, { widget.company, widget.subheader, widget.archived, widget.dossier }, timing.header, 12)
	reveal(widget, { widget.classChip, widget.classLabel }, timing.header + 0.12, 0)
	reveal(widget, { widget.outcome, widget.outcomeGhost, widget.cause }, timing.verdict, 20)
	reveal(widget, { widget.stampLabel }, timing.verdict + 0.25, 0)
	reveal(widget, { widget.manifestTitle, widget.logTitle }, timing.rowFirst - 0.12, 10)

	for index, entry in widget.entries do
		reveal(widget, { entry.label, entry.value }, timing.rowFirst + (index - 1) * timing.rowStep, 14)
	end

	reveal(widget, { widget.contractLabel }, rowTime, 10)

	local footerAt = rowTime + timing.footer
	reveal(widget, { widget.manifestRule, widget.totalLabel, widget.totalValue, widget.leftBehind }, footerAt, 0)
	reveal(widget, {
		widget.balanceRule,
		widget.cargoLabel,
		widget.bonusLabel,
		widget.paidCaption,
		widget.paidValue,
		widget.accountLabel,
		widget.xpLabel,
	}, footerAt + 0.14, 0)
	reveal(widget, { widget.closing, widget.dismiss }, footerAt + 0.32, 0)

	-- Le tampon se pose, il n'arrive pas en glissant.
	widget.stamp.Rotation = -4
	widget.gui.Enabled = true
end

function DebriefWidget.isOpen(widget: Widget): boolean
	return widget.open
end

function DebriefWidget.hide(widget: Widget)
	widget.open = false
end

-- --------------------------------------------------------------- Boucle --

function DebriefWidget.step(widget: Widget, dt: number)
	if not widget.gui.Enabled then
		return
	end

	local timing = Theme.debrief.timing

	-- Fermeture : on laisse le document se retirer avant de couper le
	-- ScreenGui, sinon la disparition est un clignotement.
	if not widget.open then
		local alpha = math.clamp(dt * 6, 0, 1)
		widget.card.BackgroundTransparency += (1 - widget.card.BackgroundTransparency) * alpha
		widget.scrim.BackgroundTransparency += (1 - widget.scrim.BackgroundTransparency) * alpha
		widget.stroke.Transparency += (1 - widget.stroke.Transparency) * alpha
		widget.stampStroke.Transparency += (1 - widget.stampStroke.Transparency) * alpha
		widget.accentRule.BackgroundTransparency += (1 - widget.accentRule.BackgroundTransparency) * alpha

		for _, group in { widget.brackets, widget.sprockets, widget.vignette } do
			for _, frame in group do
				frame.BackgroundTransparency += (1 - frame.BackgroundTransparency) * alpha
			end
		end

		for _, entry in widget.reveals do
			entry.progress = math.max(0, entry.progress - dt * 6)
			for _, instance in entry.instances do
				setAlpha(instance, entry.baseAlpha[instance], entry.progress)
			end
		end

		if widget.scrim.BackgroundTransparency > 0.985 then
			widget.gui.Enabled = false
		end
		return
	end

	fit(widget)

	widget.clock += dt
	widget.remaining = math.max(0, widget.remaining - dt)

	-- Ouverture du cadre. La carte s'ouvre en HAUTEUR depuis le centre : le
	-- document se deroule, il ne grossit pas.
	local openAlpha = math.clamp(widget.clock / timing.open, 0, 1)
	local eased = 1 - (1 - openAlpha) * (1 - openAlpha)

	-- TREMBLEMENT D'OUVERTURE.
	--
	-- La carte est ancree au centre ; on lui ajoute un decalage en pixels qui
	-- s'eteint. Nul pour une extraction, marque pour une perte d'actif : la
	-- machine qui imprime ce rapport-la ne tient pas droit.
	local jitterX, jitterY = 0, 0
	if widget.grain.jitter > 0 and widget.clock < widget.grain.decay then
		local fade = 1 - widget.clock / widget.grain.decay
		local amplitude = widget.grain.jitter * fade * fade
		jitterX = (math.random() - 0.5) * 2 * amplitude
		jitterY = (math.random() - 0.5) * 2 * amplitude
	end
	widget.card.Position = UDim2.new(0.5, jitterX, 0.5, jitterY)

	widget.card.Size = UDim2.fromOffset(Theme.debrief.width, math.floor(Theme.debrief.height * eased))
	widget.card.BackgroundTransparency = 0.05 + (1 - 0.05) * (1 - eased)
	widget.stroke.Transparency = 0.15 + (1 - 0.15) * (1 - eased)
	widget.accentRule.BackgroundTransparency = 1 - eased
	widget.scrim.BackgroundTransparency = Theme.debrief.scrimTransparency
		+ (1 - Theme.debrief.scrimTransparency) * (1 - math.clamp(widget.clock / 0.5, 0, 1))

	-- Equerres et perforations suivent l'ouverture du cadre : elles font
	-- partie du support, pas du contenu.
	for _, bracket in widget.brackets do
		bracket.BackgroundTransparency = 0.15 + 0.85 * (1 - eased)
	end
	for _, sprocket in widget.sprockets do
		sprocket.BackgroundTransparency = 0.45 + 0.55 * (1 - eased)
	end
	for _, edge in widget.vignette do
		edge.BackgroundTransparency = 1 - widget.grain.vignette * eased
	end

	-- Apparitions differees.
	for _, entry in widget.reveals do
		local target = if widget.clock >= entry.at then 1 else 0
		if entry.progress ~= target then
			entry.progress = math.clamp(entry.progress + (target - entry.progress) * math.clamp(dt * 11, 0, 1), 0, 1)
			if math.abs(target - entry.progress) < 0.004 then
				entry.progress = target
			end

			for _, instance in entry.instances do
				setAlpha(instance, entry.baseAlpha[instance], entry.progress)
				if entry.slide > 0 then
					local base = entry.basePosition[instance]
					local shift = entry.slide * (1 - entry.progress)
					instance.Position = UDim2.new(
						base.X.Scale,
						base.X.Offset - shift,
						base.Y.Scale,
						base.Y.Offset
					)
				end
			end
		end
	end

	-- Le tampon : contour qui apparait d'un coup, puis se redresse un peu.
	local stampAt = timing.verdict + 0.25
	if widget.clock >= stampAt then
		local settle = math.clamp((widget.clock - stampAt) / 0.35, 0, 1)
		widget.stampStroke.Transparency = 0.08 + 0.92 * (1 - settle)
		widget.stamp.Rotation = -10 + 6 * settle
	end

	-- Nombres qui defilent.
	for _, entry in widget.rolls do
		if entry.shown < entry.target then
			local speed = math.max(entry.target / Theme.debrief.rollDuration, 40)
			entry.shown = math.min(entry.target, entry.shown + speed * dt)
			entry.label.Text = Components.group(math.floor(entry.shown))
		end
	end

	-- Balayage lent, d'autant plus marque que le document est degrade.
	widget.scanOffset = (widget.scanOffset + dt * Theme.monitor.scanlineSpeed) % 1
	for index, line in widget.scanlines do
		local offset = ((index - 1) / #widget.scanlines + widget.scanOffset) % 1
		line.Position = UDim2.fromScale(0, offset)
		line.BackgroundTransparency = widget.grain.scanline
	end

	-- Perturbation du verdict quand l'actif est perdu. Le document lui-meme a
	-- du mal a ecrire le mot : c'est la seule licence prise sur le ton
	-- administratif, et elle ne dure pas.
	local report = widget.report
	if report and report.outcome == "KIA" and widget.clock < timing.verdict + 2.4 then
		widget.glitch -= dt
		if widget.glitch <= 0 then
			widget.glitch = 0.09
			local source = widget.outcomeText
			if #source > 0 and math.random() < 0.55 then
				local at = math.random(1, #source)
				local pick = math.random(1, #Theme.glitchGlyphs)
				local glyph = string.sub(Theme.glitchGlyphs, pick, pick)
				widget.outcome.Text = string.sub(source, 1, at - 1) .. glyph .. string.sub(source, at + 1)
			else
				widget.outcome.Text = source
			end
		end

		-- Le double d'impression se decale pendant la perturbation : les deux
		-- passages ne sont plus du tout alignes.
		widget.outcomeGhost.Position = UDim2.fromOffset(
			PADDING + 3 + math.random(-3, 3),
			Y.verdict + 2 + math.random(-1, 1)
		)
	else
		if widget.outcome.Text ~= widget.outcomeText then
			widget.outcome.Text = widget.outcomeText
		end
		-- Le double reprend son decalage nominal : sans ce retour, il
		-- resterait fige sur le dernier ecart aleatoire de la
		-- perturbation, et le verdict garderait une ombre de travers
		-- pendant les quinze secondes suivantes.
		local resting = UDim2.fromOffset(PADDING + 3, Y.verdict + 2)
		if widget.outcomeGhost.Position ~= resting then
			widget.outcomeGhost.Position = resting
		end
	end

	-- Pied de page : compte a rebours d'acquittement.
	widget.dismiss.Text = `{Locale.t("debrief.dismiss")}  [E]   {math.ceil(widget.remaining)}`

	if widget.remaining <= 0 then
		DebriefWidget.hide(widget)
	end
end

function DebriefWidget.destroy(widget: Widget)
	widget.gui:Destroy()
end

return DebriefWidget
