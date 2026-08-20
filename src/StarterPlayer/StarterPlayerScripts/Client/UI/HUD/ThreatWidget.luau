--!strict
-- Menace, en haut au centre sous la boussole.
--
-- C'est l'element le plus important du HUD, et la maquette le traite comme
-- tel : le libelle « THREAT » en tout petit, la valeur en tres grand, puis
-- une reglette 0-100 avec un curseur, et l'etat sous la reglette.
--
-- Le contraste de taille fait tout le travail. Un chiffre de 58 pixels au
-- centre haut de l'ecran se lit sans etre regarde — ce qui est exactement ce
-- qu'on veut d'une jauge de danger.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local ThreatWidget = {}

export type Widget = {
	root: Frame,
	caption: TextLabel,
	value: TextLabel,
	track: Frame,
	fill: Frame,
	cursor: Frame,
	ticks: { Frame },
	state: TextLabel,
	minLabel: TextLabel,
	maxLabel: TextLabel,

	band: string,
	shown: number,
	target: number,
	pulse: number,
}

local TRACK_TICKS = 20

function ThreatWidget.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "Threat",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(360, 130),
		Position = UDim2.new(0.5, 0, 0, 56),
		ZIndex = 2,
	}, parent) :: Frame

	local caption = Components.label({
		text = Components.spaced(Locale.t("hud.threat")),
		size = Theme.size.micro,
		color = Theme.color.neutral,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.new(1, 0, 0, 12),
	}, root)

	local value = Components.label({
		text = "0",
		font = Theme.font.hero,
		size = Theme.size.hero,
		color = Theme.color.neutral,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.new(1, 0, 0, 62),
		position = UDim2.fromOffset(0, 12),
	}, root)

	-- Reglette. Fond continu, curseur, et graduations par-dessus : c'est la
	-- superposition de la maquette.
	local track = Components.new("Frame", {
		BackgroundColor3 = Theme.color.border,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 280, 0, 3),
		Position = UDim2.new(0.5, 0, 0, 80),
		ZIndex = 2,
	}, root) :: Frame

	local fill = Components.new("Frame", {
		BackgroundColor3 = Theme.color.neutral,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 3,
	}, track) :: Frame

	local ticks: { Frame } = {}
	for index = 0, TRACK_TICKS do
		table.insert(ticks, Components.new("Frame", {
			BackgroundColor3 = Theme.color.border,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(1, if index % 5 == 0 then 7 else 4),
			Position = UDim2.new(index / TRACK_TICKS, 0, 0, 4),
			ZIndex = 4,
		}, track))
	end

	-- Curseur : le petit chevron pointant la valeur courante.
	local cursor = Components.new("Frame", {
		BackgroundColor3 = Theme.color.neutral,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		Position = UDim2.fromScale(0, 0.5),
		Rotation = 45,
		ZIndex = 5,
	}, track) :: Frame

	local minLabel = Components.label({
		text = "0",
		font = Theme.font.mono,
		size = Theme.size.micro,
		color = Theme.color.faint,
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0.5),
		sizeUDim = UDim2.fromOffset(24, 12),
		position = UDim2.new(0, -6, 0.5, 0),
	}, track)

	local maxLabel = Components.label({
		text = "100",
		font = Theme.font.mono,
		size = Theme.size.micro,
		color = Theme.color.faint,
		align = Enum.TextXAlignment.Left,
		anchor = Vector2.new(0, 0.5),
		sizeUDim = UDim2.fromOffset(30, 12),
		position = UDim2.new(1, 6, 0.5, 0),
	}, track)

	local state = Components.label({
		text = "",
		size = Theme.size.label,
		color = Theme.color.neutral,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 92),
	}, root)

	root.Visible = true

	return {
		root = root,
		caption = caption,
		value = value,
		track = track,
		fill = fill,
		cursor = cursor,
		ticks = ticks,
		state = state,
		minLabel = minLabel,
		maxLabel = maxLabel,
		band = "SAFE",
		shown = 0,
		target = 0,
		pulse = 0,
	}
end

-- Ne fixe que la CIBLE. L'affichage la rejoint dans `step` : une menace qui
-- saute de 40 a 100 doit se voir monter, sinon le joueur rate l'evenement le
-- plus important du jeu.
function ThreatWidget.setThreat(widget: Widget, value: number, band: string)
	widget.target = math.clamp(value, 0, 100)
	widget.band = band

	local color = Theme.threat.color[band] or Theme.color.neutral
	widget.value.TextColor3 = color
	widget.fill.BackgroundColor3 = color
	widget.cursor.BackgroundColor3 = color
	widget.state.TextColor3 = color
	widget.state.Text = Components.spaced(Locale.t(`hud.band.{band}`))

	-- En zone sure, l'element s'efface presque : c'est le principe contextuel
	-- de la maquette. Il ne disparait jamais tout a fait — savoir que la
	-- menace est basse est une information.
	local quiet = band == "SAFE"
	widget.caption.TextTransparency = if quiet then 0.55 else 0.1
	widget.state.TextTransparency = if quiet then 0.4 else 0
	widget.minLabel.TextTransparency = if quiet then 0.5 else 0.15
	widget.maxLabel.TextTransparency = if quiet then 0.5 else 0.15
end

function ThreatWidget.step(widget: Widget, dt: number)
	-- Approche exponentielle : rapide au debut, douce a l'arrivee.
	widget.shown += (widget.target - widget.shown) * math.min(1, dt * 4)

	local displayed = math.floor(widget.shown + 0.5)
	widget.value.Text = tostring(displayed)
	widget.fill.Size = UDim2.fromScale(widget.shown / 100, 1)
	widget.cursor.Position = UDim2.fromScale(widget.shown / 100, 0.5)

	-- Au-dela de HIGH, la valeur respire. C'est le seul mouvement permanent
	-- du HUD, et il ne demarre qu'a un moment ou il veut dire quelque chose.
	local escalation = Theme.threat.escalation[widget.band] or Theme.threat.escalation.SAFE
	if escalation.pulse > 0 then
		widget.pulse += dt * escalation.pulse
		widget.value.TextTransparency = (math.sin(widget.pulse) * 0.5 + 0.5) * 0.22
	else
		widget.value.TextTransparency = if widget.band == "SAFE" then 0.35 else 0
	end
end

function ThreatWidget.setVisible(widget: Widget, visible: boolean)
	widget.root.Visible = visible
end

return ThreatWidget
