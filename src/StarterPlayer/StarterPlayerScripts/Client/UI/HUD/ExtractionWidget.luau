--!strict
-- Panneau d'extraction, a droite sous le bandeau de zone.
--
-- CONTEXTUEL : il n'existe que lorsqu'une sortie est ouverte. La consigne est
-- explicite sur ce point — ne pas l'afficher en permanence. Une information
-- toujours presente cesse d'etre une information.
--
-- Vert, et vert seulement : c'est la couleur reservee a l'extraction dans le
-- code couleur de la maquette.
--
-- Il porte aussi la progression d'extraction en cours, qui remplace la
-- distance des qu'on est dans la zone : a ce moment-la, la seule chose qui
-- compte est le temps restant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local ExtractionWidget = {}

export type Widget = {
	panel: Components.Panel,
	header: TextLabel,
	hint: TextLabel,
	distance: TextLabel,
	pin: Frame,
	track: Frame,
	fill: Frame,
	flash: TextLabel,

	available: boolean,
	extracting: boolean,
	alpha: number,
	flashUntil: number,
	clock: number,
}

function ExtractionWidget.create(parent: Instance): Widget
	local panel = Components.panel({
		Name = "Extraction",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(230, 76),
		Position = UDim2.new(1, -24, 0, 152),
	}, parent)

	-- Le filet du cadre passe au vert : c'est un panneau d'etat, sa bordure
	-- porte la couleur.
	local stroke = panel.root:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.color.extraction
		stroke.Transparency = 0.45
	end

	local header = Components.label({
		text = Components.spaced(Locale.t("hud.extraction.available")),
		size = Theme.size.micro,
		color = Theme.color.extraction,
		sizeUDim = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 4),
	}, panel.body)

	local hint = Components.label({
		text = "Go to the extraction zone",
		size = Theme.size.label,
		color = Theme.color.neutral,
		sizeUDim = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(0, 24),
	}, panel.body)

	local distance = Components.label({
		text = "",
		font = Theme.font.mono,
		size = Theme.size.body,
		color = Theme.color.extraction,
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		sizeUDim = UDim2.new(1, -18, 0, 18),
		position = UDim2.new(1, -18, 0, 46),
	}, panel.body)

	local pin = Components.icon("pin", Theme.color.extraction, {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.new(1, 0, 0, 55),
	}, panel.body)

	-- Reglette de maintien, masquee tant qu'aucune extraction n'est en cours.
	local track = Components.new("Frame", {
		BackgroundColor3 = Theme.color.border,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.new(0, 0, 0, 66),
		Visible = false,
		ZIndex = 2,
	}, panel.body) :: Frame

	local fill = Components.new("Frame", {
		BackgroundColor3 = Theme.color.extraction,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 3,
	}, track) :: Frame

	local flash = Components.label({
		text = "",
		size = Theme.size.label,
		color = Theme.color.extraction,
		align = Enum.TextXAlignment.Center,
		anchor = Vector2.new(0.5, 0),
		sizeUDim = UDim2.fromOffset(460, 18),
		position = UDim2.new(0.5, 0, 0.62, 0),
		zIndex = 12,
	}, parent)
	flash.Visible = false

	return {
		panel = panel,
		header = header,
		hint = hint,
		distance = distance,
		pin = pin,
		track = track,
		fill = fill,
		flash = flash,
		available = false,
		extracting = false,
		alpha = 1,
		flashUntil = 0,
		clock = 0,
	}
end

-- Sortie ouverte la plus proche. `name` nil = aucune sortie : le panneau
-- disparait.
function ExtractionWidget.setExit(widget: Widget, name: string?, distance: number?)
	widget.available = name ~= nil

	if not name then
		return
	end

	widget.hint.Text = Locale.t("hud.extraction.goTo", { zone = Locale.maybe(`zone.{name}`) or name })
	widget.distance.Text = if distance then `{math.floor(distance)}m` else ""
end

-- Extraction en cours : la reglette remplace la distance.
function ExtractionWidget.setProgress(widget: Widget, zone: string?, fraction: number?, remaining: number?)
	if not zone then
		widget.extracting = false
		widget.track.Visible = false
		widget.header.Text = Components.spaced(Locale.t("hud.extraction.available"))
		return
	end

	widget.extracting = true
	widget.available = true
	widget.panel.root.Visible = true
	widget.track.Visible = true
	widget.header.Text = Components.spaced(Locale.t("hud.extraction.inProgress"))
	widget.hint.Text = Locale.maybe(`zone.{zone}`) or zone
	widget.fill.Size = UDim2.fromScale(math.clamp(fraction or 0, 0, 1), 1)
	widget.distance.Text = if remaining then string.format("%.1fs", math.max(0, remaining)) else ""
end

function ExtractionWidget.flash(widget: Widget, message: string, danger: boolean?)
	widget.flash.Text = Components.spaced(message)
	widget.flash.TextColor3 = if danger then Theme.color.danger else Theme.color.extraction
	widget.flash.Visible = true
	widget.flashUntil = widget.clock + 3.5
end

function ExtractionWidget.step(widget: Widget, dt: number)
	widget.clock += dt

	if widget.flash.Visible and widget.clock >= widget.flashUntil then
		widget.flash.Visible = false
	end

	local target = if widget.available then 0 else 1
	widget.alpha += (target - widget.alpha) * math.min(1, dt * Theme.motion.fade)

	if widget.alpha > 0.98 then
		widget.panel.root.Visible = false
		return
	end

	widget.panel.root.Visible = true
	widget.panel.root.BackgroundTransparency = Theme.panel.background + widget.alpha * (1 - Theme.panel.background)

	local stroke = widget.panel.root:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0.45 + widget.alpha * 0.55
	end

	widget.header.TextTransparency = widget.alpha
	widget.hint.TextTransparency = math.min(1, widget.alpha + 0.1)
	widget.distance.TextTransparency = widget.alpha
end

function ExtractionWidget.setVisible(widget: Widget, visible: boolean)
	if not visible then
		widget.available = false
	end
end

return ExtractionWidget
