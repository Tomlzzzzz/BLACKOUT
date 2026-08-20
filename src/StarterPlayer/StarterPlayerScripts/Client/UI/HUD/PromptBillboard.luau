--!strict
-- Invite d'interaction POSEE SUR L'OBJET.
--
-- Une invite au centre de l'ecran repond a « quelle touche », jamais a
-- « quoi ». Devant deux caisses cote a cote, le joueur ne sait pas laquelle
-- il va fouiller — et en premiere personne, avec un champ de vision reduit,
-- c'est une question qu'on se pose tout le temps.
--
-- Le E est donc accroche AU CONTENEUR. Le panneau central garde le nom de
-- l'action et le compte a rebours du maintien ; celui-ci dit « c'est
-- CELLE-CI ».
--
-- L'ANNEAU
--
-- Roblox ne dessine pas d'arc. L'anneau est donc compose de segments
-- disposes en cercle et reveles un par un a mesure que le maintien avance —
-- le meme procede que le trace ECG du bloc de vitaux. Trente-deux segments
-- suffisent a lire un cercle, et coutent moins qu'une image a televerser et
-- faire moderer.

local Players = game:GetService("Players")

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local PromptBillboard = {}

type Segment = {
	frame: Frame,
	angle: number,
}

export type Widget = {
	gui: BillboardGui?,
	ring: Frame?,
	segments: { Segment },
	keyLabel: TextLabel?,
	halo: Frame?,

	holding: boolean,
	elapsed: number,
	duration: number,
	flash: number,
	pulse: number,
}

local SEGMENTS = 32
local RADIUS = 26
local SIZE = 92

function PromptBillboard.create(): Widget
	return {
		gui = nil,
		ring = nil,
		segments = {},
		keyLabel = nil,
		halo = nil,
		holding = false,
		elapsed = 0,
		duration = 0,
		flash = 0,
		pulse = 0,
	}
end

local function build(widget: Widget, adornee: BasePart | Model)
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	if widget.gui then
		widget.gui.Adornee = adornee
		widget.gui.Enabled = true
		return
	end

	-- Le BillboardGui vit dans le PlayerGui et pointe l'objet par `Adornee`.
	-- Le parenter a l'objet lui-meme le ferait disparaitre avec lui — un
	-- conteneur detruit pendant qu'on le fouille laisserait une invite
	-- orpheline.
	local gui = Components.new("BillboardGui", {
		Name = "BlackoutPrompt",
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(SIZE, SIZE),
		StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0),
		Adornee = adornee,
		LightInfluence = 0,
		MaxDistance = 40,
	}, playerGui) :: BillboardGui

	-- Halo : un disque sombre derriere le E, pour qu'il reste lisible sur un
	-- mur clair comme sur le noir.
	local halo = Components.new("Frame", {
		BackgroundColor3 = Theme.color.void,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		ZIndex = 2,
	}, gui) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(1, 0) }, halo)
	Components.new("UIStroke", {
		Color = Theme.color.borderBright,
		Thickness = 1,
		Transparency = 0.35,
	}, halo)

	local keyLabel = Components.label({
		text = "E",
		size = 20,
		font = Theme.font.hero,
		color = Theme.color.info,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.fromScale(1, 1),
		zIndex = 4,
	}, halo)

	-- L'anneau. Chaque segment est une petite barre posee sur le cercle et
	-- tournee pour lui rester tangente.
	local ring = Components.new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, gui) :: Frame

	local segments: { Segment } = {}
	for index = 1, SEGMENTS do
		local angle = (index - 1) / SEGMENTS * math.pi * 2

		local frame = Components.new("Frame", {
			BackgroundColor3 = Theme.color.amber,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(
				0.5,
				math.sin(angle) * RADIUS,
				0.5,
				-math.cos(angle) * RADIUS
			),
			Size = UDim2.fromOffset(5, 3),
			Rotation = math.deg(angle),
			ZIndex = 3,
		}, ring) :: Frame

		table.insert(segments, { frame = frame, angle = angle })
	end

	widget.gui = gui
	widget.ring = ring
	widget.segments = segments
	widget.keyLabel = keyLabel
	widget.halo = halo
end

-- L'invite apparait sur `adornee`. `key` est la lettre affichee.
function PromptBillboard.show(widget: Widget, adornee: Instance?, key: string?)
	if not adornee or not (adornee:IsA("BasePart") or adornee:IsA("Model")) then
		PromptBillboard.hide(widget)
		return
	end

	build(widget, adornee :: any)

	local label = widget.keyLabel
	if label then
		label.Text = if key and #key > 0 then key else "E"
	end

	widget.holding = false
	widget.elapsed = 0
	widget.duration = 0
	widget.flash = 0
end

function PromptBillboard.hide(widget: Widget)
	local gui = widget.gui
	if gui then
		gui.Enabled = false
	end
	widget.holding = false
	widget.elapsed = 0
	widget.flash = 0
end

function PromptBillboard.beginHold(widget: Widget, duration: number)
	widget.holding = true
	widget.elapsed = 0
	-- Une invite sans maintien se declenche instantanement : on lui donne
	-- une duree minuscule pour que l'anneau se ferme d'un coup au lieu de
	-- ne rien montrer.
	widget.duration = math.max(0.12, duration)
end

function PromptBillboard.cancelHold(widget: Widget)
	widget.holding = false
end

function PromptBillboard.completeHold(widget: Widget)
	widget.holding = false
	widget.elapsed = widget.duration
	widget.flash = 1
end

function PromptBillboard.step(widget: Widget, dt: number)
	local gui = widget.gui
	if not gui or not gui.Enabled then
		return
	end

	widget.pulse += dt

	if widget.holding then
		widget.elapsed = math.min(widget.duration, widget.elapsed + dt)
	elseif widget.elapsed > 0 then
		-- Retrait rapide quand on relache, lent apres une reussite pour
		-- laisser voir l'anneau complet passer au vert.
		local speed = if widget.flash > 0 then 1.6 else 5
		widget.elapsed = math.max(0, widget.elapsed - dt * widget.duration * speed)
	end

	if widget.flash > 0 then
		widget.flash = math.max(0, widget.flash - dt * 1.8)
	end

	local fraction = if widget.duration > 0 then widget.elapsed / widget.duration else 0
	local filled = fraction * SEGMENTS
	local color = if widget.flash > 0 then Theme.color.extraction else Theme.color.amber

	for index, segment in widget.segments do
		-- Le dernier segment se revele progressivement : sans ca l'anneau
		-- avance par crans visibles au lieu de se fermer.
		local amount = math.clamp(filled - (index - 1), 0, 1)
		segment.frame.BackgroundTransparency = 1 - amount
		segment.frame.BackgroundColor3 = color
	end

	-- Respiration du halo au repos : l'invite doit accrocher l'oeil sans
	-- clignoter.
	local halo = widget.halo
	local label = widget.keyLabel
	if halo and label then
		if widget.holding then
			halo.Size = UDim2.fromOffset(34 - fraction * 3, 34 - fraction * 3)
			label.TextColor3 = color
		else
			local breath = 0.5 + math.sin(widget.pulse * 2.4) * 0.5
			halo.Size = UDim2.fromOffset(34 + breath * 1.5, 34 + breath * 1.5)
			label.TextColor3 = if widget.flash > 0 then Theme.color.extraction else Theme.color.info
		end
	end
end

function PromptBillboard.destroy(widget: Widget)
	local gui = widget.gui
	if gui then
		gui:Destroy()
	end
	widget.gui = nil
	table.clear(widget.segments)
end

return PromptBillboard
