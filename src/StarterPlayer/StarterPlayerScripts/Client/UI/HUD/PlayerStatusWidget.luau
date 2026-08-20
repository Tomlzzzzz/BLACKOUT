--!strict
-- Moniteur vital, en bas a gauche.
--
-- Ce n'est pas un tableau de bord : c'est un APPAREIL DE TERRAIN sangle sur
-- un homme, et il a vecu.
--
-- QUATRE PARTIS PRIS
--
-- 1. LE TRACE BALAIE, IL NE DEFILE PAS. Un vrai moniteur garde son image
--    fixe et fait courir une tete d'ecriture qui efface devant elle. C'est
--    beaucoup plus vivant qu'un ruban qui glisse, et surtout c'est ce que
--    l'oeil reconnait comme « moniteur medical ».
--
-- 2. RIEN NE SAUTE. Jauges, chiffres, couleurs : tout rejoint sa cible en
--    glissant. Une jauge qui passe de 80 a 14 d'une image a l'autre ne dit
--    pas au joueur qu'il vient d'encaisser — elle est juste differente.
--    Une couche fantome retient l'ancienne valeur et la rattrape avec du
--    retard : on voit COMBIEN on a perdu.
--
-- 3. L'APPAREIL SE DEGRADE AVEC SON PORTEUR. Bruit sur le signal sous 35 %
--    de vie, brouillage et tremblement sous 25 %, coupures d'alimentation
--    quand la batterie meurt. Un HUD impeccable pendant que le joueur
--    agonise raconte que rien n'est grave.
--
-- 4. RIEN N'EST DEMANDE AU SERVEUR. Le rythme se derive de quatre pressions
--    deja repliquees. C'est de la lecture, pas de la decision.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local PlayerStatusWidget = {}

type Row = {
	root: Frame,
	icon: Frame,
	label: TextLabel,
	labelText: string,
	bar: Components.Bar,
	value: TextLabel,
	color: Color3,

	-- Animation. `shown` suit `target` de pres, `ghost` traine derriere.
	target: number,
	shown: number,
	ghost: number,
	ghostHold: number,
	flash: number,
	current: number,
	displayed: number,
	maximum: number,
	suffix: string?,
}

-- Un segment relie deux points consecutifs. C'est LUI qu'on dessine ; les
-- points, eux, ne sont que des nombres.
type Segment = {
	frame: Frame,
	age: number,
}

export type Widget = {
	panel: Components.Panel,
	rows: { [string]: Row },
	order: { string },

	header: TextLabel,
	tag: TextLabel,
	headerDot: Frame,
	brownout: Frame,

	scanlines: { Frame },
	trace: Frame,
	points: { number },
	segments: { Segment },
	head: Frame,
	traceLabel: TextLabel,

	bpmValue: TextLabel,
	bpmCaption: TextLabel,
	bpmDot: Frame,

	healthFraction: number,
	staminaFraction: number,
	batteryFraction: number,
	band: string,
	startle: number,

	bpm: number,
	heat: number,
	sprinting: boolean,
	proximity: number,
	decay: number,
	shownBpm: number,
	phase: number,
	lastWrite: number,
	cursor: number,
	clock: number,
	glitchIn: number,
	glitchUntil: number,
	glitchRow: string?,
	flickerUntil: number,
	flickerIn: number,
	basePosition: UDim2,
}

local ROW_HEIGHT = 26
local ROWS = 4
local HEADER_HEIGHT = 14
-- Le trace occupe TOUTE la largeur du corps et gagne en hauteur.
--
-- L'ancienne version l'etranglait sur 180 px pour loger le rythme a cote, et
-- le cardiogramme n'etait qu'une frisure rouge. Le chiffre passe donc PAR
-- DESSUS le champ, comme sur un vrai moniteur ou la valeur est incrustee sur
-- la courbe : le trace recupere ses 64 pixels et respire.
local TRACE_HEIGHT = 62

-- POLYLIGNE, PAS HISTOGRAMME.
--
-- La version precedente dessinait un rectangle vertical par echantillon,
-- allant du minimum au maximum de l'intervalle. Resultat : des blocs
-- nettement visibles, surtout sur les portions plates. Un cardiogramme est
-- une LIGNE — on stocke donc un point par abscisse et on relie les points par
-- des segments inclines, ce qui donne une courbe continue.
--
-- 123 points espaces de 2 px : l'espacement en phase (1.8/123 = 0.0146
-- battement) passe SOUS la largeur du pic R (0.016). Le pic est donc
-- echantillonne naturellement, sans artifice.
local POINTS = 123
local POINT_SPACING = 2
local TRACE_WIDTH = (POINTS - 1) * POINT_SPACING
local LINE_THICKNESS = 2

-- Battements affiches simultanement. Moins il y en a, plus le complexe QRS
-- est etale et lisible.
local BEATS_ON_SCREEN = 1.8

-- Duree d'un balayage complet, en secondes. Constante, comme la vitesse de
-- papier d'un vrai appareil : c'est le NOMBRE de battements visibles qui
-- change avec le rythme, pas la vitesse du trace.
local SWEEP_SECONDS = 2.0

-- Largeur du vide efface devant la tete, en fraction de la bande.
local ERASE_GAP = 0.05

-- ------------------------------------------------------------ Rythme ----
local BPM_REST = 58
local BPM_MIN = 48
local BPM_MAX = 186

local BPM_FROM_WOUND = 58
local BPM_FROM_EFFORT = 20
local BPM_FROM_STARTLE = 34

-- COURSE. L'effort passait uniquement par l'endurance consommee, donc avec
-- du retard : on sprintait trois secondes avant que le coeur ne bouge. La
-- course elle-meme compte desormais, immediatement.
local BPM_FROM_SPRINT = 26

-- PROXIMITE D'UNE CREATURE.
--
-- Le meilleur des cinq apports, et le seul qui parle AVANT que le joueur ne
-- sache. La menace monte quand on se fait reperer ; le coeur, lui, s'affole
-- des qu'une chose est pres — meme dans le dos, meme sans l'avoir vue.
-- C'est le HUD qui trahit ce que le corps sait deja.
local BPM_FROM_PROXIMITY = 40

-- La menace pese meme sans blessure : c'est la peur, pas l'effort.
local BPM_FROM_THREAT: { [string]: number } = {
	SAFE = 0,
	ALERT = 6,
	DANGER = 14,
	SEVERE = 24,
	CRITICAL = 34,
	HUNT = 46,
}

-- --------------------------------------------------------- Forme d'onde --
--
-- Complexe PQRST approche par cinq gaussiennes. Une sinusoide ne
-- ressemblerait a rien : c'est le pic R brutal encadre de creux qui fait lire
-- « cardiogramme » au premier coup d'oeil.
local function waveform(t: number): number
	local phase = t % 1
	local function bump(center: number, width: number, height: number): number
		local d = (phase - center) / width
		return height * math.exp(-d * d)
	end

	return bump(0.14, 0.035, 0.12) -- P
		- bump(0.27, 0.013, 0.10) -- Q
		+ bump(0.30, 0.016, 1.00) -- R
		- bump(0.345, 0.020, 0.30) -- S
		+ bump(0.55, 0.05, 0.22) -- T
end

-- Table precalculee.
--
-- INDISPENSABLE : le pic R dure 0.016 en phase, et une case du trace n'est
-- ecrite qu'une fois toutes les quelques images. Prendre la valeur
-- instantanee au moment de l'ecriture ferait RATER le pic la plupart du
-- temps. On releve donc les extremes sur tout l'intervalle ecoule depuis la
-- derniere ecriture, ce que la table rend gratuit.
local LUT_SIZE = 512
local LUT = table.create(LUT_SIZE)
for index = 1, LUT_SIZE do
	LUT[index] = waveform((index - 1) / LUT_SIZE)
end

local function extremes(t0: number, t1: number): (number, number)
	local start = math.floor((t0 % 1) * LUT_SIZE)
	local stop = math.floor((t1 % 1) * LUT_SIZE)
	local steps = math.min((stop - start) % LUT_SIZE, LUT_SIZE - 1)

	local low, high = math.huge, -math.huge
	for offset = 0, steps do
		local value = LUT[((start + offset) % LUT_SIZE) + 1]
		if value < low then
			low = value
		end
		if value > high then
			high = value
		end
	end
	return low, high
end

-- Le brouillage vit dans Components : le reste du HUD doit se degrader
-- EXACTEMENT comme ce bloc, pas approximativement.
local scramble = Components.scramble

-- ------------------------------------------------------------ Montage ----

function PlayerStatusWidget.create(parent: Instance): Widget
	local traceTop = HEADER_HEIGHT + ROW_HEIGHT * ROWS + 6
	local bodyHeight = traceTop + TRACE_HEIGHT
	local basePosition = UDim2.new(0, 24, 1, -24)

	local panel = Components.panel({
		Name = "PlayerStatus",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(268, bodyHeight + 16),
		Position = basePosition,
		Visible = true,
	}, parent, Theme.color.borderBright)

	-- ------------------------------------------------------ Bandeau ----
	--
	-- Nommer l'appareil et son porteur. De l'annotation technique que personne
	-- ne lit vraiment — et c'est precisement ce qui fait « vrai materiel »
	-- plutot que « interface de jeu ».
	--
	-- Pas de filet sous ce bandeau : le separateur y coupait le bloc en deux
	-- et cassait la lecture d'un seul appareil.
	local headerDot = Components.new("Frame", {
		BackgroundColor3 = Theme.color.extraction,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(4, 4),
		Position = UDim2.new(0, 0, 0, 6),
		ZIndex = 3,
	}, panel.body) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(1, 0) }, headerDot)

	local header = Components.label({
		text = Components.spaced("VITALS"),
		size = Theme.size.micro,
		color = Theme.color.neutral,
		sizeUDim = UDim2.fromOffset(120, 12),
		position = UDim2.fromOffset(10, 0),
	}, panel.body)

	local tag = Components.label({
		text = "",
		font = Theme.font.mono,
		size = Theme.size.micro,
		color = Theme.color.faint,
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		sizeUDim = UDim2.fromOffset(120, 12),
		position = UDim2.new(1, 0, 0, 0),
	}, panel.body)

	-- -------------------------------------------------- Constantes ----

	local specs = {
		{ key = "health", icon = "health", labelKey = "hud.vitals.health", color = Theme.color.health },
		{ key = "armor", icon = "armor", labelKey = "hud.vitals.armor", color = Theme.color.armor },
		{ key = "stamina", icon = "stamina", labelKey = "hud.vitals.stamina", color = Theme.color.stamina },
		{ key = "battery", icon = "battery", labelKey = "hud.vitals.battery", color = Theme.color.battery },
	}

	local rows: { [string]: Row } = {}
	local order: { string } = {}

	for index, spec in specs do
		local rowRoot = Components.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			Position = UDim2.fromOffset(0, HEADER_HEIGHT + (index - 1) * ROW_HEIGHT),
			ZIndex = 2,
		}, panel.body) :: Frame

		-- Ancre au centre : le pictogramme peut pulser sans se decaler.
		--
		-- 20 px et non 16 : les rendus chrome portent des biseaux et des
		-- rayures qui deviennent une tache en dessous. La ligne fait 26 px de
		-- haut, c'est la place disponible.
		local icon = Components.icon(spec.icon, spec.color, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(0, 10, 0.5, 0),
		}, rowRoot)

		local labelText = Locale.t(spec.labelKey)
		local label = Components.label({
			text = labelText,
			size = Theme.size.micro,
			color = Theme.color.neutral,
			sizeUDim = UDim2.fromOffset(120, 11),
			position = UDim2.fromOffset(28, 1),
		}, rowRoot)

		local bar = Components.bar({
			Size = UDim2.new(0, 142, 0, 7),
			Position = UDim2.fromOffset(28, 14),
		}, spec.color, rowRoot)

		local value = Components.label({
			text = "",
			font = Theme.font.mono,
			size = Theme.size.body,
			color = Theme.color.info,
			align = Enum.TextXAlignment.Right,
			anchor = Vector2.new(1, 0.5),
			sizeUDim = UDim2.fromOffset(72, 18),
			position = UDim2.new(1, 0, 0.5, 0),
		}, rowRoot)

		rows[spec.key] = {
			root = rowRoot,
			icon = icon,
			label = label,
			labelText = labelText,
			bar = bar,
			value = value,
			color = spec.color,
			target = 1,
			shown = 1,
			ghost = 1,
			ghostHold = 0,
			flash = 0,
			current = 0,
			displayed = 0,
			maximum = 100,
			suffix = nil,
		}
		table.insert(order, spec.key)
	end

	-- ------------------------------------------------------- Trace ----

	local trace = Components.new("Frame", {
		Name = "Trace",
		BackgroundColor3 = Theme.color.void,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(TRACE_WIDTH, TRACE_HEIGHT),
		Position = UDim2.fromOffset(0, traceTop),
		ZIndex = 2,
	}, panel.body) :: Frame

	-- Grille millimetree : c'est elle qui transforme une ligne rouge en
	-- moniteur medical. Le trace a desormais une echelle contre laquelle se
	-- lire, meme si personne ne lit cette echelle.
	for column = 1, Theme.monitor.gridColumns - 1 do
		Components.new("Frame", {
			BackgroundColor3 = Theme.color.separator,
			BackgroundTransparency = Theme.monitor.gridTransparency,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 1, 1, 0),
			Position = UDim2.fromScale(column / Theme.monitor.gridColumns, 0),
			ZIndex = 2,
		}, trace)
	end
	for row = 1, Theme.monitor.gridRows - 1 do
		Components.new("Frame", {
			BackgroundColor3 = Theme.color.separator,
			BackgroundTransparency = Theme.monitor.gridTransparency,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromScale(0, row / Theme.monitor.gridRows),
			ZIndex = 2,
		}, trace)
	end

	Components.new("Frame", {
		BackgroundColor3 = Theme.color.separator,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.fromScale(0, 0.5),
		ZIndex = 3,
	}, trace)

	-- Les points partent tous sur la ligne de base : au demarrage le trace est
	-- plat, et la tete l'ecrit au fur et a mesure de son premier passage.
	local points: { number } = table.create(POINTS, 0)

	local segments: { Segment } = {}
	for _ = 1, POINTS - 1 do
		table.insert(segments, {
			frame = Components.new("Frame", {
				BackgroundColor3 = Theme.color.danger,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(POINT_SPACING, LINE_THICKNESS),
				Position = UDim2.fromScale(0, 0.5),
				ZIndex = 4,
			}, trace),
			age = math.huge,
		})
	end

	-- Tete d'ecriture : le point vif ou le signal s'inscrit. Le regard le
	-- suit, exactement comme sur un moniteur reel.
	local head = Components.new("Frame", {
		BackgroundColor3 = Theme.color.info,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		Position = UDim2.fromScale(0, 0.5),
		ZIndex = 6,
	}, trace) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(1, 0) }, head)

	local traceLabel = Components.label({
		text = "ECG",
		font = Theme.font.mono,
		size = Theme.size.micro,
		color = Theme.color.faint,
		sizeUDim = UDim2.fromOffset(40, 10),
		position = UDim2.fromOffset(3, 2),
		zIndex = 5,
	}, trace)

	-- -------------------------------------------------- Rythme chiffre ----

	-- Adossement du rythme : un voile sombre en degrade sous le chiffre.
	--
	-- Sans lui, le trace passe DERRIERE les chiffres et les hachure. Le
	-- degrade evite le rectangle net, qui aurait l'air d'une etiquette collee
	-- sur la courbe au lieu d'une incrustation.
	local bpmBacking = Components.new("Frame", {
		BackgroundColor3 = Theme.color.void,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(92, 44),
		Position = UDim2.new(1, 0, 0, 0),
		ZIndex = 6,
	}, trace) :: Frame

	Components.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.25),
			NumberSequenceKeypoint.new(1, 0.15),
		}),
	}, bpmBacking)

	-- Le rythme est incruste sur le champ, en haut a droite. Il flotte sur la
	-- courbe au lieu de lui voler de la place.
	local bpmValue = Components.label({
		text = "--",
		font = Theme.font.hero,
		size = Theme.size.large,
		color = Theme.color.danger,
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		sizeUDim = UDim2.fromOffset(72, 30),
		position = UDim2.new(1, -6, 0, 1),
		zIndex = 7,
	}, trace)

	local bpmCaption = Components.label({
		text = "BPM",
		size = Theme.size.micro,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		sizeUDim = UDim2.fromOffset(72, 11),
		position = UDim2.new(1, -6, 0, 30),
		zIndex = 7,
	}, trace)

	local bpmDot = Components.new("Frame", {
		BackgroundColor3 = Theme.color.danger,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(5, 5),
		Position = UDim2.new(1, -82, 0, 16),
		ZIndex = 7,
	}, trace) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(1, 0) }, bpmDot)

	-- ---------------------------------------------------- Balayage ----

	local scanlines: { Frame } = {}
	for index = 1, Theme.monitor.scanlines do
		table.insert(scanlines, Components.new("Frame", {
			BackgroundColor3 = Theme.color.info,
			BackgroundTransparency = Theme.monitor.scanlineTransparency,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromScale(0, (index - 1) / Theme.monitor.scanlines),
			ZIndex = 8,
		}, panel.root))
	end

	-- Coupure d'alimentation : voile noir sur toute la plaque, invisible au
	-- repos. C'est la batterie mourante qui l'allume.
	local brownout = Components.new("Frame", {
		BackgroundColor3 = Theme.color.void,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
	}, panel.root) :: Frame

	return {
		panel = panel,
		rows = rows,
		order = order,
		header = header,
		tag = tag,
		headerDot = headerDot,
		brownout = brownout,
		scanlines = scanlines,
		trace = trace,
		points = points,
		segments = segments,
		head = head,
		traceLabel = traceLabel,
		bpmValue = bpmValue,
		bpmCaption = bpmCaption,
		bpmDot = bpmDot,
		healthFraction = 1,
		staminaFraction = 1,
		batteryFraction = 1,
		band = "SAFE",
		startle = 0,
		bpm = BPM_REST,
		heat = 0,
		sprinting = false,
		proximity = 0,
		decay = 0,
		shownBpm = BPM_REST,
		phase = 0,
		lastWrite = 0,
		cursor = 0,
		clock = 0,
		glitchIn = 0,
		glitchUntil = 0,
		glitchRow = nil,
		flickerUntil = 0,
		flickerIn = 0,
		basePosition = basePosition,
	}
end

-- ------------------------------------------------------------ Lectures ---

function PlayerStatusWidget.setTag(widget: Widget, tag: string)
	widget.tag.Text = tag
end

-- Enregistre une CIBLE. L'affichage la rejoint dans `step` : c'est ce qui
-- fait qu'une perte se voit descendre au lieu d'apparaitre deja subie.
local function setRow(widget: Widget, key: string, current: number, maximum: number, suffix: string?)
	local row = widget.rows[key]
	if not row then
		return
	end

	local fraction = if maximum > 0 then math.clamp(current / maximum, 0, 1) else 0

	-- Une PERTE declenche l'eclat et retient le fantome. Un gain n'a pas a
	-- etre dramatise : le fantome le rattrape immediatement.
	if fraction < row.target - 0.001 then
		row.flash = 1
		row.ghostHold = 0.35
	elseif fraction > row.target then
		row.ghost = math.max(row.ghost, fraction)
	end

	row.target = fraction
	row.current = current
	row.maximum = maximum
	row.suffix = suffix
end

function PlayerStatusWidget.setHealth(widget: Widget, current: number, maximum: number)
	widget.healthFraction = if maximum > 0 then math.clamp(current / maximum, 0, 1) else 0
	setRow(widget, "health", current, maximum)
end

function PlayerStatusWidget.setStamina(widget: Widget, current: number, maximum: number)
	widget.staminaFraction = if maximum > 0 then math.clamp(current / maximum, 0, 1) else 0
	setRow(widget, "stamina", current, maximum)
end

function PlayerStatusWidget.setVitals(widget: Widget, vitals: any)
	setRow(widget, "armor", vitals.armor, vitals.maxArmor)
	setRow(widget, "battery", vitals.battery, vitals.maxBattery, "%")

	widget.batteryFraction = if vitals.maxBattery > 0
		then math.clamp(vitals.battery / vitals.maxBattery, 0, 1)
		else 0

	local battery = widget.rows.battery
	if battery then
		battery.labelText = Locale.t(if vitals.lightOn then "hud.vitals.battery" else "hud.vitals.batteryOff")
	end
end

function PlayerStatusWidget.setStress(widget: Widget, band: string)
	widget.band = band
end

function PlayerStatusWidget.onDamage(widget: Widget, severity: string)
	local jolt = if severity == "critical" then 1 elseif severity == "heavy" then 0.7 else 0.4
	widget.startle = math.max(widget.startle, jolt)
end

-- ------------------------------------------------------------- Boucle ----

-- Rythme normalise : 0 au repos, 1 a l'affolement. Lu par la panique
-- generale du HUD pour que tout batte sur le meme pouls.
-- La course, telle que le SERVEUR l'a accordee. Pas la touche enfoncee : on
-- ne s'essouffle pas a demander une course qu'on nous refuse.
function PlayerStatusWidget.setSprinting(widget: Widget, value: boolean)
	widget.sprinting = value
end

-- Proximite de la creature la plus proche, 0 (rien alentour) a 1 (sur nous).
function PlayerStatusWidget.setProximity(widget: Widget, value: number)
	widget.proximity = math.clamp(value, 0, 1)
end

function PlayerStatusWidget.getHeat(widget: Widget): number
	return widget.heat
end

-- Degradation de l'appareil, 0 a 1. Meme valeur que celle qui brouille
-- les libelles de ce bloc : la panique generale la lit pour se degrader
-- au meme rythme, avec le meme grain.
function PlayerStatusWidget.getDecay(widget: Widget): number
	return widget.decay
end

function PlayerStatusWidget.step(widget: Widget, dt: number)
	widget.clock += dt

	-- --- rythme -----------------------------------------------------------
	local wound = (1 - widget.healthFraction) ^ 1.4
	local effort = 1 - widget.staminaFraction
	local threat = BPM_FROM_THREAT[widget.band] or 0

	widget.startle = math.max(0, widget.startle - dt * 0.55)

	local sprint = if widget.sprinting then BPM_FROM_SPRINT else 0

	-- La proximite entre au CARRE : une creature a mi-portee ne doit pas
	-- valoir la moitie de la panique. C'est le dernier tiers de la
	-- distance qui compte.
	local near = widget.proximity * widget.proximity * BPM_FROM_PROXIMITY

	widget.bpm = math.clamp(
		BPM_REST
			+ wound * BPM_FROM_WOUND
			+ effort * BPM_FROM_EFFORT
			+ sprint
			+ near
			+ threat
			+ widget.startle * BPM_FROM_STARTLE,
		BPM_MIN,
		BPM_MAX
	)

	-- Un coeur ne saute pas de 60 a 160 en une image.
	widget.shownBpm += (widget.bpm - widget.shownBpm) * math.min(1, dt * 1.6)
	widget.bpmValue.Text = tostring(math.floor(widget.shownBpm + 0.5))

	widget.phase += dt * (widget.shownBpm / 60)

	-- --- degradation ------------------------------------------------------
	local decay = 0
	if widget.healthFraction < Theme.monitor.degradeBelow then
		decay = 1 - widget.healthFraction / Theme.monitor.degradeBelow
	end

	local heat = math.clamp((widget.shownBpm - BPM_REST) / (BPM_MAX - BPM_REST), 0, 1)
	-- Publiee : c'est la SOURCE UNIQUE de la panique du HUD entier. Le
	-- reste de l'interface ne recalcule pas son propre affolement, il lit
	-- celui du coeur.
	widget.heat = heat
	-- La DEGRADATION aussi : c'est elle qui pilote le brouillage ici, et
	-- donc celui du reste du HUD. Deux calculs separes deriveraient.
	widget.decay = decay
	local traceColor = Theme.color.danger:Lerp(Color3.fromRGB(255, 96, 96), heat * 0.6)
	local beat = waveform(widget.phase)

	-- --- lignes vitales ---------------------------------------------------
	for key, row in widget.rows do
		-- La valeur affichee glisse : le chiffre defile au lieu de sauter.
		row.displayed += (row.current - row.displayed) * math.min(1, dt * 11)
		row.shown += (row.target - row.shown) * math.min(1, dt * 9)

		-- Le fantome tient un instant, puis rattrape lentement. C'est ce
		-- retard qui rend la perte lisible.
		if row.ghostHold > 0 then
			row.ghostHold -= dt
		else
			row.ghost += (row.shown - row.ghost) * math.min(1, dt * 2.4)
		end
		if row.ghost < row.shown then
			row.ghost = row.shown
		end

		row.flash = math.max(0, row.flash - dt * 2.6)

		local fraction = row.shown
		local color = row.color
		if fraction <= 0.25 then
			color = Theme.color.danger
		elseif key == "battery" and row.current <= 35 then
			color = Theme.color.amber
		end

		-- L'eclat blanchit la couleur au moment de la perte, puis se retire.
		if row.flash > 0 then
			color = color:Lerp(Color3.fromRGB(255, 255, 255), row.flash * 0.75)
		end

		Components.setBar(row.bar, fraction, color, row.ghost, Theme.color.dangerDeep)
		Components.tintIcon(row.icon, color)

		row.value.Text = if row.suffix
			then `{math.floor(row.displayed + 0.5)}{row.suffix}`
			else `{math.floor(row.displayed + 0.5)}/{math.floor(row.maximum)}`
		row.value.TextColor3 = if row.flash > 0
			then Theme.color.info:Lerp(Color3.fromRGB(255, 255, 255), row.flash)
			elseif fraction <= 0.25 then Theme.color.danger
			else Theme.color.info

		if row.label.Text ~= row.labelText and widget.clock >= widget.glitchUntil then
			row.label.Text = row.labelText
			row.label.TextColor3 = Theme.color.neutral
		end
	end

	-- Le pictogramme de vie bat avec le coeur : le seul element du bloc
	-- synchronise sur une pulsation plutot que sur une horloge.
	local healthRow = widget.rows.health
	if healthRow then
		local pulse = 20 + math.max(0, beat) * 4
		healthRow.icon.Size = UDim2.fromOffset(math.floor(pulse), math.floor(pulse))
	end

	-- --- trace par balayage ------------------------------------------------
	--
	-- La tete avance a vitesse constante et n'ecrit QUE les cases qu'elle
	-- vient de franchir ; les autres gardent leur valeur. Devant elle, un vide
	-- efface le tour precedent.
	local previous = widget.cursor
	widget.cursor += dt / SWEEP_SECONDS
	local wrapped = widget.cursor >= 1
	widget.cursor %= 1

	-- Le pic R frole desormais le bord du champ : c'est lui qu'on doit voir
	-- de loin, pas la ligne de base.
	local amplitude = (TRACE_HEIGHT - 10) * 0.46
	local noise = decay * Theme.monitor.noisePixels

	-- Valeur du point ecrit : l'extreme le plus marque depuis la derniere
	-- ecriture. Prendre la valeur instantanee raterait le pic R quand une
	-- abscisse n'est ecrite qu'une image sur trois ; garder min ET max
	-- redonnerait un rectangle. On garde donc le plus significatif des deux,
	-- ce qui conserve la pointe tout en restant une LIGNE.
	local low, high = extremes(widget.lastWrite, widget.phase)
	local value = if math.abs(high) >= math.abs(low) then high else low
	local wroteSomething = false

	local jitter = if noise > 0 then (math.random() - 0.5) * 2 * noise else 0
	local written = -value * amplitude + jitter

	-- On ecrit les POINTS que la tete vient de franchir.
	local touched: { number } = {}
	for index = 1, POINTS do
		local position = (index - 1) / (POINTS - 1)

		local justPassed
		if wrapped then
			justPassed = position > previous or position <= widget.cursor
		else
			justPassed = position > previous and position <= widget.cursor
		end

		if justPassed then
			widget.points[index] = written
			wroteSomething = true
			table.insert(touched, index)
		end
	end

	-- Seuls les segments voisins d'un point modifie ont besoin d'etre
	-- recalcules : deux ou trois par image, pas cent vingt.
	local function refresh(index: number)
		local segment = widget.segments[index]
		if not segment then
			return
		end

		local y0 = widget.points[index]
		local y1 = widget.points[index + 1]
		local dy = y1 - y0

		-- Longueur exacte du segment, plus un pixel de recouvrement pour que
		-- deux segments consecutifs ne laissent pas de trou dans les angles
		-- vifs — et le pic R en est un.
		local length = math.sqrt(POINT_SPACING * POINT_SPACING + dy * dy) + 1

		segment.frame.Position = UDim2.new(0, (index - 1) * POINT_SPACING + POINT_SPACING * 0.5, 0.5, (y0 + y1) * 0.5)
		segment.frame.Size = UDim2.fromOffset(math.ceil(length), LINE_THICKNESS)
		segment.frame.Rotation = math.deg(math.atan2(dy, POINT_SPACING))
		segment.age = 0
	end

	for _, index in touched do
		refresh(index - 1)
		refresh(index)
	end

	-- Vieillissement et effacement devant la tete.
	for index, segment in widget.segments do
		if segment.age ~= 0 then
			segment.age += dt
		end

		local position = (index - 0.5) / (POINTS - 1)
		local ahead = (position - widget.cursor) % 1
		if ahead > 0 and ahead <= ERASE_GAP then
			-- Vide devant la tete : c'est lui qui fait « balayage » plutot que
			-- « graphique fixe ».
			segment.frame.BackgroundTransparency = 1
			continue
		end

		segment.frame.BackgroundColor3 = traceColor

		-- Persistance du phosphore : le trace fraichement ecrit brille, le
		-- reste s'eteint doucement jusqu'au prochain passage.
		local fade = math.clamp(segment.age / SWEEP_SECONDS, 0, 1)
		segment.frame.BackgroundTransparency = 0.05 + fade * 0.5
	end

	if wroteSomething then
		widget.lastWrite = widget.phase
	end

	widget.head.Position = UDim2.new(widget.cursor, 0, 0.5, math.floor(-beat * amplitude))
	widget.head.BackgroundColor3 = traceColor

	-- --- temoin de pulsation ---------------------------------------------
	widget.bpmDot.BackgroundTransparency = math.clamp(1 - beat * 1.6, 0.15, 0.9)
	widget.bpmDot.BackgroundColor3 = traceColor
	widget.bpmValue.TextColor3 = traceColor
	widget.bpmCaption.TextColor3 = if widget.shownBpm >= 140 then Theme.color.danger else Theme.color.dim

	widget.headerDot.BackgroundColor3 = if decay > 0.5
		then Theme.color.danger
		elseif decay > 0 then Theme.color.amber
		else Theme.color.extraction
	widget.headerDot.BackgroundTransparency = 0.5 + math.abs(math.sin(widget.clock * 1.6)) * 0.35

	-- --- balayage cathodique ----------------------------------------------
	for index, line in widget.scanlines do
		local offset = ((widget.clock * Theme.monitor.scanlineSpeed) + (index - 1) / Theme.monitor.scanlines) % 1
		line.Position = UDim2.fromScale(0, offset)
		line.BackgroundTransparency = Theme.monitor.scanlineTransparency - decay * 0.06
	end

	-- --- brouillage et tremblement ----------------------------------------
	if widget.healthFraction < Theme.monitor.glitchBelow and widget.healthFraction > 0 then
		widget.glitchIn -= dt
		if widget.glitchIn <= 0 then
			widget.glitchIn = 1 / (Theme.monitor.glitchPerSecond * math.max(0.2, decay))
			widget.glitchUntil = widget.clock + 0.12
			widget.glitchRow = widget.order[math.random(1, #widget.order)]

			local target = widget.rows[widget.glitchRow :: string]
			if target then
				target.label.Text = scramble(target.labelText)
				target.label.TextColor3 = Theme.color.danger
			end
		end

		widget.panel.root.Position = widget.basePosition
			+ UDim2.fromOffset(math.random(-1, 1), math.random(-1, 1))
	else
		widget.panel.root.Position = widget.basePosition
	end

	-- --- coupures d'alimentation ------------------------------------------
	--
	-- Sous 15 % de batterie, l'appareil clignote : c'est la SEULE consequence
	-- visible d'une batterie vide avant qu'elle ne coupe la lampe, et elle
	-- previent le joueur pendant qu'il peut encore agir.
	if widget.batteryFraction < 0.15 then
		widget.flickerIn -= dt
		if widget.flickerIn <= 0 then
			widget.flickerIn = 0.4 + math.random() * 1.6
			widget.flickerUntil = widget.clock + 0.05 + math.random() * 0.08
		end
	end

	widget.brownout.BackgroundTransparency = if widget.clock < widget.flickerUntil then 0.35 else 1
end

-- ---------------------------------------------------------- Responsive ---

function PlayerStatusWidget.setCompact(widget: Widget, compact: boolean)
	-- En profil reduit, armure et batterie sortent : vie et souffle sont les
	-- seules dont la lecture est vitale. Le trace RESTE — c'est lui qui porte
	-- l'ambiance, et il ne coute qu'une bande de soixante pixels.
	--
	-- LES LIGNES RESTANTES SONT REPLACEES.
	--
	-- Les masquer sans les repositionner laissait SOUFFLE a son emplacement
	-- d'origine, c'est-a-dire par-dessus le cardiogramme remonte. Un trou au
	-- milieu du bloc et deux elements superposes : la lecture etait perdue.
	local hidden = { armor = compact, battery = compact }
	local slot = 0

	for _, key in widget.order do
		local row = widget.rows[key]
		if not row then
			continue
		end

		local visible = not hidden[key]
		row.root.Visible = visible

		if visible then
			row.root.Position = UDim2.fromOffset(0, HEADER_HEIGHT + slot * ROW_HEIGHT)
			slot += 1
		end
	end

	local traceTop = HEADER_HEIGHT + ROW_HEIGHT * slot + 6

	widget.panel.root.Size = UDim2.fromOffset(268, traceTop + TRACE_HEIGHT + 16)
	widget.trace.Position = UDim2.fromOffset(0, traceTop)
end

return PlayerStatusWidget
