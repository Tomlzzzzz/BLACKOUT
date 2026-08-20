--!strict
-- Invites contextuelles, au centre.
--
-- Le centre de l'ecran est reserve. Rien n'y vit en permanence : la consigne
-- est explicite, la vue de jeu doit rester dominante.
--
-- Deux usages seulement :
--   l'invite d'interaction, sous le reticule
--   les alertes breves (ENEMY DETECTED), au-dessus
--
-- La touche est encadree comme dans la maquette, et l'action secondaire
-- (« [HOLD] SEARCH ») passe en dessous, plus petite et plus grise.

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local InteractionWidget = {}

export type Widget = {
	prompt: Frame,
	keyBox: Frame,
	keyLabel: TextLabel,
	action: TextLabel,
	hint: TextLabel,

	progressTrack: Frame,
	progressFill: Frame,

	alert: TextLabel,
	alertUntil: number,

	-- Maintien en cours. `holdDuration` vient du ProximityPrompt lui-meme :
	-- la barre doit se remplir exactement au rythme ou le serveur valide,
	-- sinon elle ment sur le moment ou l'action aboutit.
	holding: boolean,
	holdElapsed: number,
	holdDuration: number,
	flash: number,

	visible: boolean,
	alpha: number,
	clock: number,
}

function InteractionWidget.create(parent: Instance): Widget
	local prompt = Components.new("Frame", {
		Name = "Interaction",
		BackgroundColor3 = Theme.color.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(260, 42),
		Position = UDim2.fromScale(0.5, 0.62),
		Visible = false,
		ZIndex = 6,
	}, parent) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(0, Theme.panel.corner) }, prompt)
	Components.new("UIStroke", {
		Color = Theme.color.border,
		Thickness = 1,
		Transparency = 0.3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, prompt)

	local keyBox = Components.new("Frame", {
		BackgroundColor3 = Theme.color.raised,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(0, 12, 0.5, 0),
		ZIndex = 7,
	}, prompt) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(0, 2) }, keyBox)
	Components.new("UIStroke", { Color = Theme.color.borderBright, Thickness = 1, Transparency = 0.2 }, keyBox)

	local keyLabel = Components.label({
		text = "E",
		size = Theme.size.label,
		color = Theme.color.info,
		align = Enum.TextXAlignment.Center,
		zIndex = 8,
	}, keyBox)

	local action = Components.label({
		text = "",
		size = Theme.size.body,
		color = Theme.color.info,
		sizeUDim = UDim2.new(1, -50, 0, 16),
		position = UDim2.fromOffset(42, 5),
		zIndex = 7,
	}, prompt)

	local hint = Components.label({
		text = "",
		size = Theme.size.micro,
		color = Theme.color.dim,
		sizeUDim = UDim2.new(1, -50, 0, 12),
		position = UDim2.fromOffset(42, 22),
		zIndex = 7,
	}, prompt)

	-- BARRE DE MAINTIEN.
	--
	-- « [MAINTENIR] FOUILLER » disait quoi faire mais rien ne se passait
	-- pendant qu'on le faisait : aucun moyen de savoir si la touche etait
	-- prise en compte, ni combien de temps il restait. Le joueur relachait
	-- au bout d'une demi-seconde en croyant que ca ne marchait pas.
	local progressTrack = Components.new("Frame", {
		BackgroundColor3 = Theme.color.raised,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 3),
		Visible = false,
		ZIndex = 8,
	}, prompt) :: Frame

	local progressFill = Components.new("Frame", {
		BackgroundColor3 = Theme.color.amber,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 9,
	}, progressTrack) :: Frame

	local alert = Components.label({
		text = "",
		size = Theme.size.value,
		color = Theme.color.danger,
		align = Enum.TextXAlignment.Center,
		anchor = Vector2.new(0.5, 0.5),
		sizeUDim = UDim2.fromOffset(560, 26),
		position = UDim2.fromScale(0.5, 0.38),
		zIndex = 8,
	}, parent)
	alert.Visible = false

	return {
		prompt = prompt,
		keyBox = keyBox,
		keyLabel = keyLabel,
		action = action,
		hint = hint,
		progressTrack = progressTrack,
		progressFill = progressFill,
		alert = alert,
		alertUntil = 0,
		holding = false,
		holdElapsed = 0,
		holdDuration = 0,
		flash = 0,
		visible = false,
		alpha = 1,
		clock = 0,
	}
end

-- `action` nil masque l'invite.
function InteractionWidget.setPrompt(widget: Widget, action: string?, target: string?, key: string?, hold: boolean?)
	if not action then
		widget.visible = false
		return
	end

	widget.visible = true
	widget.keyLabel.Text = key or "E"
	widget.action.Text = string.upper(action) .. (if target then ` {string.upper(target)}` else "")
	widget.hint.Text = if hold then Components.spaced("[HOLD] SEARCH") else ""
end

-- Le joueur vient d'enfoncer la touche.
function InteractionWidget.beginHold(widget: Widget, duration: number)
	widget.holding = true
	widget.holdElapsed = 0
	-- Une invite SANS maintien se declenche instantanement. On lui donne
	-- quand meme une duree minuscule : la barre part et se remplit d'un coup,
	-- ce qui accuse la pression au lieu de ne rien montrer.
	widget.holdDuration = math.max(0.12, duration)
	widget.progressTrack.Visible = true
	widget.progressFill.Size = UDim2.new(0, 0, 1, 0)
	widget.progressFill.BackgroundColor3 = Theme.color.amber
end

-- Relachee avant la fin : la barre se vide vite, sans flash.
function InteractionWidget.cancelHold(widget: Widget)
	widget.holding = false
end

-- L'action a REELLEMENT abouti. La barre passe au vert et flashe : c'est le
-- seul retour qui distingue « j'ai tenu assez longtemps » de « j'ai relache
-- trop tot », et les deux se ressemblaient exactement.
function InteractionWidget.completeHold(widget: Widget)
	widget.holding = false
	widget.holdElapsed = widget.holdDuration
	widget.progressFill.Size = UDim2.new(1, 0, 1, 0)
	widget.progressFill.BackgroundColor3 = Theme.color.extraction
	widget.flash = 1
end

function InteractionWidget.alert(widget: Widget, message: string, color: Color3?)
	widget.alert.Text = Components.spaced(message)
	widget.alert.TextColor3 = color or Theme.color.danger
	widget.alert.Visible = true
	widget.alertUntil = widget.clock + 2.5
end

function InteractionWidget.step(widget: Widget, dt: number)
	-- --- maintien ---------------------------------------------------------
	if widget.holding then
		widget.holdElapsed = math.min(widget.holdDuration, widget.holdElapsed + dt)
		local fraction = widget.holdElapsed / widget.holdDuration
		widget.progressFill.Size = UDim2.new(fraction, 0, 1, 0)
		-- Le cadre de touche s'enfonce : la barre dit le temps, le cadre dit
		-- que la touche est tenue.
		widget.keyBox.BackgroundTransparency = 0.05 - 0.05 * fraction
		widget.keyBox.Size = UDim2.fromOffset(20, 20 - math.floor(fraction * 2))
	elseif widget.progressTrack.Visible then
		-- Retrait. Rapide apres un abandon, plus lent apres une reussite pour
		-- laisser voir le vert.
		local speed = if widget.flash > 0 then 2.5 else 7
		local remaining = widget.progressFill.Size.X.Scale
		local next = math.max(0, remaining - dt * speed)
		widget.progressFill.Size = UDim2.new(next, 0, 1, 0)
		widget.keyBox.BackgroundTransparency = 0.05
		widget.keyBox.Size = UDim2.fromOffset(20, 20)
		if next <= 0 then
			widget.progressTrack.Visible = false
		end
	end

	if widget.flash > 0 then
		widget.flash = math.max(0, widget.flash - dt * 2.2)
	end

	widget.clock += dt

	if widget.alert.Visible then
		if widget.clock >= widget.alertUntil then
			widget.alert.Visible = false
		else
			-- Legere respiration pendant l'affichage : l'alerte doit accrocher
			-- l'oeil sans clignoter.
			widget.alert.TextTransparency = (math.sin(widget.clock * 8) * 0.5 + 0.5) * 0.3
		end
	end

	local target = if widget.visible then 0 else 1
	widget.alpha += (target - widget.alpha) * math.min(1, dt * Theme.motion.slide)

	if widget.alpha > 0.98 then
		widget.prompt.Visible = false
		return
	end

	widget.prompt.Visible = true
	widget.prompt.BackgroundTransparency = 0.25 + widget.alpha * 0.75
	widget.action.TextTransparency = widget.alpha
	widget.hint.TextTransparency = math.min(1, widget.alpha + 0.2)
	widget.keyLabel.TextTransparency = widget.alpha
	widget.keyBox.BackgroundTransparency = 0.05 + widget.alpha * 0.95
end

return InteractionWidget
