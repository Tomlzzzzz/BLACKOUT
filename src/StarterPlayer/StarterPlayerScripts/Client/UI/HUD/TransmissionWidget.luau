--!strict
-- Transmissions du commanditaire, au-dessus des vitaux.
--
-- Conserve du HUD precedent : c'est ce qui porte le fait que le joueur
-- travaille pour quelqu'un, et rien dans la maquette ne l'annule — elle ne
-- montre simplement pas cet etat.
--
-- Le texte arrive lettre par lettre. C'est ce qui le fait lire comme une
-- liaison radio et non comme un panneau qui s'allume.
--
-- Le ton vit dans le filet de gauche, jamais dans le texte : une phrase en
-- rouge sur fond noir est illisible, et toutes les autres plaques du HUD
-- suivent deja cette regle.

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local TransmissionWidget = {}

export type Widget = {
	panel: Components.Panel,
	accent: Frame,
	sender: TextLabel,
	body: TextLabel,

	full: string,
	shown: number,
	hold: number,
	alpha: number,
}

-- Decoupe respectueuse de l'UTF-8 : les montants formates contiennent une
-- espace fine insecable de trois octets, et couper au milieu afficherait un
-- glyphe casse pendant une image.
local function prefix(text: string, count: number): string
	local boundary = utf8.offset(text, count + 1)
	return if boundary then text:sub(1, boundary - 1) else text
end

function TransmissionWidget.create(parent: Instance): Widget
	local panel = Components.panel({
		Name = "Transmission",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(340, 66),
		-- Au-dessus du panneau de vitaux, jamais dessus : celui-ci monte a
		-- 96 + 118 px du bas, plus le trace cardiaque.
		Position = UDim2.new(0, 24, 1, -246),
	}, parent)

	local accent = Components.new("Frame", {
		BackgroundColor3 = Theme.color.cyan,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 0),
		Position = UDim2.fromScale(0, 0),
		ZIndex = 3,
	}, panel.root) :: Frame

	local sender = Components.label({
		text = "",
		size = Theme.size.micro,
		color = Theme.color.dim,
		sizeUDim = UDim2.new(1, 0, 0, 12),
		position = UDim2.fromOffset(0, 2),
	}, panel.body)

	-- TextScaled desactive volontairement : une transmission fait une a deux
	-- lignes de longueur variable, et un texte mis a l'echelle changerait de
	-- corps a chaque message. Le HUD perdrait sa voix fixe.
	local body = Components.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.font.label,
		TextSize = Theme.size.body,
		TextColor3 = Theme.color.info,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 1, -18),
		Position = UDim2.fromOffset(0, 16),
		Text = "",
		ZIndex = 2,
	}, panel.body) :: TextLabel

	return {
		panel = panel,
		accent = accent,
		sender = sender,
		body = body,
		full = "",
		shown = 0,
		hold = 0,
		alpha = 1,
	}
end

function TransmissionWidget.transmit(widget: Widget, sender: string, text: string, tone: string, holdTime: number?)
	local color = Theme.transmission.tone[tone] or Theme.color.info

	widget.full = text
	widget.shown = 0
	widget.hold = holdTime or Theme.transmission.hold
	widget.panel.root.Visible = true
	widget.accent.BackgroundColor3 = color
	widget.sender.Text = Components.spaced(sender)
	widget.body.Text = ""
end

function TransmissionWidget.step(widget: Widget, dt: number)
	if not widget.panel.root.Visible then
		return
	end

	local total = utf8.len(widget.full) or #widget.full

	if widget.shown < total then
		widget.shown = math.min(total, widget.shown + dt * Theme.transmission.rate)
		widget.body.Text = prefix(widget.full, math.floor(widget.shown))
	else
		-- Le maintien ne commence qu'une fois la phrase entierement frappee :
		-- un message long ne doit pas disparaitre plus vite qu'un court.
		widget.hold -= dt
	end

	if widget.hold > 0 then
		widget.alpha += (0 - widget.alpha) * math.min(1, dt * Theme.transmission.fadeIn)
	else
		widget.alpha += (1 - widget.alpha) * math.min(1, dt * Theme.transmission.fadeOut)
		if widget.alpha > 0.99 then
			widget.panel.root.Visible = false
			widget.full = ""
			return
		end
	end

	widget.panel.root.BackgroundTransparency = Theme.panel.background + widget.alpha * (1 - Theme.panel.background)
	widget.accent.BackgroundTransparency = widget.alpha
	widget.sender.TextTransparency = math.min(1, widget.alpha + 0.2)
	widget.body.TextTransparency = widget.alpha

	local stroke = widget.panel.root:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0.25 + widget.alpha * 0.75
	end
end

return TransmissionWidget
