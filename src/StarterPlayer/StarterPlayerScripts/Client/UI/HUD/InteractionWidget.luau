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
	stroke: UIStroke,
	keyBox: Frame,
	keyShadow: Frame,
	glow: Frame,
	keyLabel: TextLabel,
	action: TextLabel,
	hint: TextLabel,

	progressTrack: Frame,
	segments: { Frame },

	alert: TextLabel,
	alertUntil: number,

	-- Maintien en cours. `holdDuration` vient du ProximityPrompt lui-meme :
	-- la barre doit se remplir exactement au rythme ou le serveur valide,
	-- sinon elle ment sur le moment ou l'action aboutit.
	holding: boolean,
	shown: number,
	holdElapsed: number,
	holdDuration: number,
	flash: number,
	-- Entree du panneau : il monte et se revele au lieu d'apparaitre.
	appear: number,
	press: number,

	visible: boolean,
	alpha: number,
	clock: number,
}

local HOLD_SEGMENTS = 32
local HOLD_RADIUS = 17

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
	local stroke = Components.new("UIStroke", {
		Color = Theme.color.border,
		Thickness = 1,
		Transparency = 0.3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, prompt) :: UIStroke

	-- LA TOUCHE EST UN OBJET PHYSIQUE.
	--
	-- C'etait un carre plat de 20 pixels avec une lettre dedans : rien n'y
	-- disait qu'on peut appuyer dessus, et rien n'y changeait quand on
	-- appuyait. Une touche a une EPAISSEUR — un liseré sombre sous elle — et
	-- cette epaisseur disparait quand elle s'enfonce. C'est le seul detail qui
	-- transforme un carre en bouton.
	--
	-- L'ombre est un second cadre, decale vers le bas, dessine DERRIERE.
	local keyShadow = Components.new("Frame", {
		BackgroundColor3 = Theme.color.void,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(0, 22, 0.5, 3),
		ZIndex = 6,
	}, prompt) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(0, 4) }, keyShadow)

	local keyBox = Components.new("Frame", {
		BackgroundColor3 = Theme.color.raised,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(0, 22, 0.5, 0),
		ZIndex = 7,
	}, prompt) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(0, 4) }, keyBox)
	Components.new("UIStroke", { Color = Theme.color.borderBright, Thickness = 1, Transparency = 0.2 }, keyBox)

	-- LUEUR DE CHARGE, derriere la touche.
	--
	-- Un anneau dit « ou j'en suis » ; il ne dit pas « quelque chose est en
	-- train de se passer ». La lueur grossit et s'intensifie avec le maintien,
	-- et c'est elle qu'on percoit du coin de l'oeil sans lire la progression.
	--
	-- Elle est dessinee SOUS l'ombre de la touche pour ne jamais manger le
	-- contraste de la lettre.
	local glow = Components.new("Frame", {
		Name = "Charge",
		BackgroundColor3 = Theme.color.amber,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 22, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 5,
	}, prompt) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)

	-- Reflet en haut de la touche : une bande claire en degrade. Sans elle le
	-- cadre reste plat quelle que soit son epaisseur.
	local gloss = Components.new("Frame", {
		BackgroundColor3 = Theme.color.info,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.45, 0),
		ZIndex = 8,
	}, keyBox) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(0, 4) }, gloss)

	local keyLabel = Components.label({
		text = "E",
		size = Theme.size.body,
		font = Theme.font.hero,
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

	-- ANNEAU DE MAINTIEN, autour du cadre de touche.
	--
	-- « [MAINTENIR] FOUILLER » disait quoi faire, mais rien ne se passait
	-- pendant qu'on le faisait : aucun moyen de savoir si la touche etait
	-- prise en compte ni combien de temps il restait. On relachait au bout
	-- d'une demi-seconde en croyant a une panne.
	--
	-- Un filet sous le panneau disait bien la progression, mais loin de
	-- l'endroit ou l'oeil est pose : la touche. On la CERCLE donc.
	--
	-- Roblox ne dessine pas d'arc. L'anneau est fait de segments poses en
	-- cercle et reveles un par un — meme procede que le trace du bloc de
	-- vitaux. Trente-deux suffisent a lire un cercle, et ca evite de
	-- televerser puis faire moderer une image.
	local progressTrack = Components.new("Frame", {
		Name = "HoldRing",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 22, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		Visible = false,
		ZIndex = 8,
	}, prompt) :: Frame

	local segments: { Frame } = {}
	for index = 1, HOLD_SEGMENTS do
		local angle = (index - 1) / HOLD_SEGMENTS * math.pi * 2
		table.insert(
			segments,
			Components.new("Frame", {
				BackgroundColor3 = Theme.color.amber,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(
					0.5,
					math.sin(angle) * HOLD_RADIUS,
					0.5,
					-math.cos(angle) * HOLD_RADIUS
				),
				Size = UDim2.fromOffset(4, 3),
				Rotation = math.deg(angle),
				ZIndex = 8,
			}, progressTrack) :: Frame
		)
	end

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
		stroke = stroke,
		keyBox = keyBox,
		keyShadow = keyShadow,
		glow = glow,
		keyLabel = keyLabel,
		action = action,
		hint = hint,
		progressTrack = progressTrack,
		segments = segments,
		alert = alert,
		alertUntil = 0,
		holding = false,
		shown = 0,
		holdElapsed = 0,
		holdDuration = 0,
		flash = 0,
		appear = 0,
		press = 0,
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
	widget.shown = 0
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
	widget.shown = 1
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
	--
	-- LA TOUCHE S'ENFONCE VRAIMENT. Trois choses bougent ensemble, et c'est
	-- leur simultaneite qui fait la sensation d'appui :
	--
	--   la touche DESCEND de trois pixels
	--   son ombre portee DISPARAIT sous elle — l'epaisseur s'ecrase
	--   elle s'eclaircit legerement, comme un contact qui se ferme
	--
	-- La version precedente se contentait de retirer deux pixels de hauteur :
	-- la touche maigrissait au lieu de s'enfoncer.
	local pressed = 0
	if widget.holding then
		widget.holdElapsed = math.min(widget.holdDuration, widget.holdElapsed + dt)
		widget.shown = widget.holdElapsed / widget.holdDuration
		pressed = 1
	elseif widget.progressTrack.Visible then
		-- Retrait. Rapide apres un abandon, plus lent apres une reussite pour
		-- laisser voir l'anneau complet passer au vert.
		local speed = if widget.flash > 0 then 2.5 else 7
		widget.shown = math.max(0, widget.shown - dt * speed)
		if widget.shown <= 0 then
			widget.progressTrack.Visible = false
		end
	end

	-- Le mouvement d'appui suit sa propre interpolation : une touche qui
	-- tombe instantanement claque, une touche qui met une demi-seconde est
	-- molle. Un vingtieme de seconde environ.
	widget.press += (pressed - widget.press) * math.min(1, dt * 22)

	local drop = widget.press * 3
	widget.keyBox.Position = UDim2.new(0, 22, 0.5, drop)
	widget.keyShadow.Position = UDim2.new(0, 22, 0.5, 3)
	widget.keyShadow.BackgroundTransparency = 0.15 + widget.press * 0.85
	widget.keyBox.BackgroundTransparency = 0.05 - widget.press * 0.05

	if widget.flash > 0 then
		widget.flash = math.max(0, widget.flash - dt * 2.2)
	end

	-- --- anneau -----------------------------------------------------------
	--
	-- Trois lectures superposees, et c'est leur combinaison qui rend
	-- l'attente supportable :
	--
	--   le REMPLI      dit ou l'on en est ;
	--   la TETE        — les trois derniers segments, plus clairs et plus
	--                    epais — dit que ca AVANCE encore ;
	--   la LUEUR       dit qu'il se passe quelque chose, sans avoir a lire.
	--
	-- A la reussite, l'anneau s'ECARTE : il quitte la touche vers l'exterieur
	-- en s'effacant, ce qui evacue l'invite au lieu de la faire disparaitre.
	if widget.progressTrack.Visible then
		local filled = widget.shown * #widget.segments
		local done = widget.flash > 0
		local color = if done then Theme.color.extraction else Theme.color.amber

		-- L'onde de validation : l'anneau grandit de six pixels en s'effacant.
		local burst = if done then (1 - widget.flash) * 6 else 0
		local radius = HOLD_RADIUS + burst

		for index, segment in widget.segments do
			local amount = math.clamp(filled - (index - 1), 0, 1)

			-- Proximite de la tete, sur les trois derniers segments remplis.
			local fromHead = filled - index
			local head = if fromHead >= 0 and fromHead < 3 then 1 - fromHead / 3 else 0

			segment.BackgroundTransparency = 1 - amount * (if done then widget.flash else 1)
			segment.BackgroundColor3 = if head > 0
				then color:Lerp(Theme.color.info, head * 0.7)
				else color
			segment.Size = UDim2.fromOffset(4 + math.floor(head * 2), 3 + math.floor(head * 2))

			local angle = (index - 1) / #widget.segments * math.pi * 2
			segment.Position = UDim2.new(
				0.5,
				math.sin(angle) * radius,
				0.5,
				-math.cos(angle) * radius
			)
		end

		-- La lueur suit la charge, puis eclate a la validation.
		local charge = if done then widget.flash else widget.shown
		widget.glow.BackgroundColor3 = color
		widget.glow.BackgroundTransparency = 1 - charge * 0.32
		widget.glow.Size = UDim2.fromOffset(
			30 + math.floor(charge * 14),
			30 + math.floor(charge * 14)
		)
	else
		widget.glow.BackgroundTransparency = 1
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
		widget.appear = 0
		return
	end

	-- ENTREE DU PANNEAU. Il MONTE en se revelant, sur huit pixels.
	--
	-- Une invite qui apparait d'un coup au centre de l'ecran se lit comme un
	-- defaut d'affichage. Huit pixels de montee suffisent a la faire lire
	-- comme quelque chose qui ARRIVE.
	widget.appear += ((1 - widget.alpha) - widget.appear) * math.min(1, dt * 14)

	widget.prompt.Visible = true
	widget.prompt.Position = UDim2.new(0.5, 0, 0.62, math.floor((1 - widget.appear) * 8))
	widget.prompt.BackgroundTransparency = 0.25 + widget.alpha * 0.75
	widget.action.TextTransparency = widget.alpha
	widget.hint.TextTransparency = math.min(1, widget.alpha + 0.2)
	widget.keyLabel.TextTransparency = widget.alpha
	widget.keyShadow.BackgroundTransparency = math.min(1, 0.15 + widget.press * 0.85 + widget.alpha)

	-- Le liseré du panneau prend la couleur de l'action quand elle aboutit :
	-- le cadre entier confirme, pas seulement l'anneau.
	widget.stroke.Color = if widget.flash > 0
		then Theme.color.extraction
		else Theme.color.border
	widget.stroke.Transparency = 0.3 + widget.alpha * 0.7 - widget.flash * 0.25
end

return InteractionWidget
