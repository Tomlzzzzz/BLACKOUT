--!strict
-- Marqueur de touche, au centre de l'ecran.
--
-- Quatre traits en diagonale qui s'ecartent puis s'effacent. Blanc pour une
-- touche, rouge et plus large pour une elimination.
--
-- C'est la boucle de retour la plus courte du jeu : le joueur tire, il sait
-- immediatement si le serveur a valide. Sans lui, le tir est muet — et un tir
-- muet donne l'impression que l'arme ne marche pas, meme quand elle marche.
--
-- Le marqueur ne prouve rien : il illustre une decision serveur deja prise.

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local HitMarker = {}

export type Widget = {
	root: Frame,
	ticks: { Frame },
	life: number,
	kind: string,
}

local LIFE = 0.32
local KILL_LIFE = 0.55

function HitMarker.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "HitMarker",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromScale(0.5, 0.5),
		Visible = false,
		ZIndex = 22,
	}, parent) :: Frame

	local ticks: { Frame } = {}
	-- Quatre branches, une par diagonale.
	for _, rotation in { 45, 135, 225, 315 } do
		table.insert(ticks, Components.new("Frame", {
			BackgroundColor3 = Theme.color.info,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(2, 9),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = rotation,
			ZIndex = 22,
		}, root))
	end

	return { root = root, ticks = ticks, life = 0, kind = "hit" }
end

function HitMarker.hit(widget: Widget, kind: string)
	widget.kind = kind
	widget.life = if kind == "kill" then KILL_LIFE else LIFE
	widget.root.Visible = true

	local color = if kind == "kill" then Theme.color.danger else Theme.color.info
	for _, tick in widget.ticks do
		tick.BackgroundColor3 = color
		tick.Size = UDim2.fromOffset(if kind == "kill" then 3 else 2, if kind == "kill" then 12 else 9)
	end
end

function HitMarker.step(widget: Widget, dt: number)
	if widget.life <= 0 then
		return
	end

	widget.life -= dt
	if widget.life <= 0 then
		widget.root.Visible = false
		return
	end

	local total = if widget.kind == "kill" then KILL_LIFE else LIFE
	local fade = widget.life / total

	-- Les branches s'ecartent du centre en s'effacant : c'est l'expansion qui
	-- fait lire « impact », pas la disparition seule.
	local spread = (1 - fade) * (if widget.kind == "kill" then 16 else 9) + 7

	for index, tick in widget.ticks do
		local angle = math.rad(45 + (index - 1) * 90)
		tick.Position = UDim2.new(0.5, math.sin(angle) * spread, 0.5, -math.cos(angle) * spread)
		tick.BackgroundTransparency = 1 - fade
	end
end

return HitMarker
