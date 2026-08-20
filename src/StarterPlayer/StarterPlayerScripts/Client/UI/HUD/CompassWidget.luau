--!strict
-- Boussole, en haut au centre.
--
-- Une reglette graduee qui defile avec le regard, quatre points cardinaux
-- majeurs, et le cap numerique sous le curseur central.
--
-- POINT DE PERFORMANCE
--
-- Les graduations sont creees UNE FOIS et repositionnees. Une boussole naive
-- detruit et recree ses reperes a chaque image ; a soixante images par
-- seconde, ce sont des milliers d'instances par minute, et le ramasse-miettes
-- finit par se voir a l'ecran.
--
-- Le repositionnement, lui, tourne bien a l'echantillonnage : c'est le seul
-- widget du HUD qui suit la camera, il ne peut pas etre purement
-- evenementiel.

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local CompassWidget = {}

type Tick = {
	frame: Frame,
	label: TextLabel,
	angle: number,
}

type Marker = {
	root: Frame,
	label: TextLabel,
}

export type Widget = {
	root: Frame,
	window: Frame,
	ticks: { Tick },
	cursor: Frame,
	heading: TextLabel,
	markers: { Marker },
}

-- Champ visible de part et d'autre du cap, en degres. 60 de chaque cote
-- reproduit la densite de la maquette.
local HALF_SPAN = 60

-- Une graduation tous les 15 degres, un libelle tous les 45.
local STEP = 15

local CARDINALS: { [number]: string } = {
	[0] = "N",
	[45] = "NE",
	[90] = "E",
	[135] = "SE",
	[180] = "S",
	[225] = "SW",
	[270] = "W",
	[315] = "NW",
}

function CompassWidget.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "Compass",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(420, 34),
		Position = UDim2.new(0.5, 0, 0, 16),
		ZIndex = 2,
	}, parent) :: Frame

	-- Fenetre de decoupe : une graduation qui sort du cadre doit disparaitre,
	-- pas deborder sur le reste du HUD.
	local window = Components.new("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, 22),
		ZIndex = 2,
	}, root) :: Frame

	local ticks: { Tick } = {}
	-- Assez de graduations pour couvrir la fenetre entiere avec de la marge :
	-- on en cree une de plus que necessaire pour que l'enroulement ne laisse
	-- jamais de trou au bord.
	local count = math.ceil((HALF_SPAN * 2) / STEP) + 2

	for _ = 1, count do
		local frame = Components.new("Frame", {
			BackgroundColor3 = Theme.color.neutral,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(1, 6),
			Position = UDim2.fromScale(0.5, 0),
			ZIndex = 2,
		}, window) :: Frame

		local label = Components.label({
			text = "",
			size = Theme.size.micro,
			color = Theme.color.neutral,
			align = Enum.TextXAlignment.Center,
			anchor = Vector2.new(0.5, 0),
			sizeUDim = UDim2.fromOffset(40, 12),
			position = UDim2.fromScale(0.5, 0.4),
		}, window)

		table.insert(ticks, { frame = frame, label = label, angle = 0 })
	end

	-- Curseur central : le seul repere fixe.
	local cursor = Components.new("Frame", {
		BackgroundColor3 = Theme.color.info,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(1, 10),
		Position = UDim2.new(0.5, 0, 0, 0),
		ZIndex = 4,
	}, root) :: Frame

	local heading = Components.label({
		text = "000",
		font = Theme.font.mono,
		size = Theme.size.micro,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Center,
		anchor = Vector2.new(0.5, 0),
		sizeUDim = UDim2.fromOffset(60, 12),
		position = UDim2.new(0.5, 0, 0, 22),
	}, root)

	-- Marqueurs de sortie. Ils vivent DANS la fenetre de decoupe : une sortie
	-- hors du champ de vision ne doit pas deborder sur le reste du HUD.
	--
	-- C'est ce qui transforme la boussole d'une decoration en outil : sans
	-- marqueur, savoir qu'on regarde le nord ne dit pas ou est la sortie.
	local markers: { Marker } = {}
	for _ = 1, 4 do
		local markerRoot = Components.new("Frame", {
			BackgroundColor3 = Theme.color.extraction,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(7, 7),
			Position = UDim2.fromScale(0.5, 0),
			Rotation = 45,
			Visible = false,
			ZIndex = 4,
		}, window) :: Frame

		local distance = Components.label({
			text = "",
			font = Theme.font.mono,
			size = Theme.size.micro,
			color = Theme.color.extraction,
			align = Enum.TextXAlignment.Center,
			anchor = Vector2.new(0.5, 0),
			sizeUDim = UDim2.fromOffset(52, 12),
			position = UDim2.fromScale(0.5, 0.44),
			zIndex = 4,
		}, window)
		distance.Visible = false

		table.insert(markers, { root = markerRoot, label = distance })
	end

	root.Visible = true

	return {
		root = root,
		window = window,
		ticks = ticks,
		cursor = cursor,
		heading = heading,
		markers = markers,
	}
end

-- Difference d'angle la plus courte, ramenee dans [-180, 180]. C'est elle qui
-- fait que la boussole ne fait pas un tour complet quand on passe 359 -> 0.
local function shortestDelta(from: number, to: number): number
	local delta = (to - from + 180) % 360 - 180
	return delta
end

-- `yaw` en degres, 0 = nord, sens horaire.
function CompassWidget.setHeading(widget: Widget, yaw: number)
	local heading = (yaw % 360 + 360) % 360
	widget.heading.Text = string.format("%03d", math.floor(heading + 0.5))

	-- Graduation la plus proche du cap, arrondie au pas : c'est le point
	-- d'ancrage a partir duquel on distribue les autres.
	local base = math.floor(heading / STEP + 0.5) * STEP
	local half = math.floor(#widget.ticks / 2)

	for index, tick in widget.ticks do
		local angle = (base + (index - 1 - half) * STEP) % 360
		tick.angle = angle

		local delta = shortestDelta(heading, angle)
		local fraction = 0.5 + delta / (HALF_SPAN * 2)

		-- Hors champ : on masque au lieu de laisser Roblox dessiner puis
		-- decouper. Une instance invisible ne coute rien au rendu.
		if fraction < -0.05 or fraction > 1.05 then
			tick.frame.Visible = false
			tick.label.Visible = false
			continue
		end

		local cardinal = CARDINALS[angle]
		local major = cardinal ~= nil

		tick.frame.Visible = true
		tick.frame.Position = UDim2.fromScale(fraction, 0)
		tick.frame.Size = UDim2.fromOffset(1, if major then 9 else 5)
		tick.frame.BackgroundTransparency = if major then 0.15 else 0.6

		if major then
			tick.label.Visible = true
			tick.label.Position = UDim2.new(fraction, 0, 0.42, 0)
			tick.label.Text = cardinal :: string
			tick.label.TextColor3 = if cardinal == "N" then Theme.color.info else Theme.color.neutral
		else
			tick.label.Visible = false
		end
	end
end

-- Pose les marqueurs de sortie. `entries` porte un cap et une distance par
-- sortie ouverte ; le HUDController les calcule a la cadence lente.
function CompassWidget.setMarkers(widget: Widget, entries: { { bearing: number, distance: number } }, yaw: number)
	local heading = (yaw % 360 + 360) % 360

	for index, marker in widget.markers do
		local entry = entries[index]
		if not entry then
			marker.root.Visible = false
			marker.label.Visible = false
			continue
		end

		local delta = shortestDelta(heading, entry.bearing)
		local fraction = 0.5 + delta / (HALF_SPAN * 2)

		-- Une sortie derriere soi est epinglee au bord au lieu de disparaitre :
		-- « elle est a gauche, loin » reste une information utile.
		local clamped = math.clamp(fraction, 0.02, 0.98)
		local offscreen = fraction < 0 or fraction > 1

		marker.root.Visible = true
		marker.label.Visible = true
		marker.root.Position = UDim2.fromScale(clamped, 0)
		marker.label.Position = UDim2.new(clamped, 0, 0.44, 0)
		marker.label.Text = `{math.floor(entry.distance)}m`

		local dim = if offscreen then 0.55 else 0
		marker.root.BackgroundTransparency = dim
		marker.label.TextTransparency = dim + 0.1
	end
end

function CompassWidget.setVisible(widget: Widget, visible: boolean)
	widget.root.Visible = visible
end

return CompassWidget
