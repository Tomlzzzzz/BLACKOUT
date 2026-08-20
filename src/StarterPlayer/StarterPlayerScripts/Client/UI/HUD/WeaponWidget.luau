--!strict
-- Arme, en bas a droite.
--
-- « 30 / 120 » avec un fort contraste de graisse entre le chargeur et la
-- reserve, le calibre en dessous, la silhouette de l'arme a droite, et le
-- mode de tir en pied.
--
-- Quatre etats, comme la maquette :
--   NORMAL     blanc
--   LOW AMMO   ambre
--   EMPTY      rouge
--   RELOADING  chargeur remplace par des points animes

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local WeaponWidget = {}

export type Widget = {
	root: Frame,
	magazine: TextLabel,
	reserve: TextLabel,
	caliber: TextLabel,
	silhouette: Frame,
	mode: TextLabel,
	modeTicks: { Frame },

	reloading: boolean,
	clock: number,
	visible: boolean,
	alpha: number,
}

local LOW_RATIO = 0.3
local MODE_TICKS = 6

function WeaponWidget.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "Weapon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(250, 78),
		Position = UDim2.new(1, -24, 1, -24),
		Visible = false,
		ZIndex = 2,
	}, parent) :: Frame

	-- Chargeur : le plus gros chiffre du bas d'ecran.
	local magazine = Components.label({
		text = "0",
		font = Theme.font.hero,
		size = Theme.size.large,
		color = Theme.color.info,
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		sizeUDim = UDim2.fromOffset(90, 36),
		position = UDim2.fromOffset(110, 6),
	}, root)

	-- Reserve : nettement plus petite et grise. Le rapport de taille EST
	-- l'information — le joueur doit lire le chargeur, pas la reserve.
	local reserve = Components.label({
		text = "/0",
		font = Theme.font.value,
		size = Theme.size.body,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Left,
		sizeUDim = UDim2.fromOffset(60, 20),
		position = UDim2.fromOffset(114, 20),
	}, root)

	local caliber = Components.label({
		text = "",
		font = Theme.font.mono,
		size = Theme.size.micro,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		sizeUDim = UDim2.fromOffset(100, 12),
		position = UDim2.fromOffset(110, 42),
	}, root)

	local silhouette = Components.icon("rifle", Theme.color.neutral, {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(76, 30),
		Position = UDim2.new(1, 0, 0, 26),
	}, root)

	local mode = Components.label({
		text = "",
		size = Theme.size.micro,
		color = Theme.color.dim,
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		sizeUDim = UDim2.fromOffset(120, 12),
		position = UDim2.new(1, 0, 0, 50),
	}, root)

	-- Petit peigne de graduations sous le mode de tir : detail purement
	-- decoratif de la maquette, mais c'est lui qui donne l'air « instrument ».
	local modeTicks: { Frame } = {}
	for index = 1, MODE_TICKS do
		table.insert(modeTicks, Components.new("Frame", {
			BackgroundColor3 = Theme.color.border,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(6, 2),
			Position = UDim2.new(1, -(index - 1) * 9, 0, 66),
			ZIndex = 2,
		}, root))
	end

	return {
		root = root,
		magazine = magazine,
		reserve = reserve,
		caliber = caliber,
		silhouette = silhouette,
		mode = mode,
		modeTicks = modeTicks,
		reloading = false,
		clock = 0,
		visible = false,
		alpha = 1,
	}
end

local function tint(widget: Widget, color: Color3)
	for _, child in widget.silhouette:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundColor3 = color
		end
	end
end

-- `name` nil masque le module : sans arme equipee, il n'y a rien a dire.
function WeaponWidget.setWeapon(
	widget: Widget,
	name: string?,
	ammo: number,
	magazine: number,
	reserve: number,
	caliber: string?,
	mode: string?,
	reloading: boolean
)
	if not name then
		widget.visible = false
		return
	end

	widget.visible = true
	widget.reloading = reloading
	widget.reserve.Text = `/{reserve}`
	widget.caliber.Text = caliber or ""
	widget.mode.Text = Components.spaced(mode or "SEMI-AUTO")

	if reloading then
		-- Le chargeur devient illisible pendant le rechargement : c'est
		-- exactement ce que la maquette montre, et c'est juste — pendant
		-- deux secondes, le joueur n'a effectivement pas de munitions.
		widget.magazine.TextColor3 = Theme.color.dim
		return
	end

	widget.magazine.Text = tostring(math.floor(ammo))

	local ratio = if magazine > 0 then ammo / magazine else 0
	local color = Theme.color.info
	if ammo <= 0 then
		color = Theme.color.danger
	elseif ratio <= LOW_RATIO then
		color = Theme.color.amber
	end

	widget.magazine.TextColor3 = color
	widget.reserve.TextColor3 = if reserve <= 0 then Theme.color.danger else Theme.color.dim
	tint(widget, if ammo <= 0 then Theme.color.danger else Theme.color.neutral)
end

function WeaponWidget.step(widget: Widget, dt: number)
	widget.clock += dt

	if widget.reloading then
		-- Trois points qui defilent. Discret, et suffisant pour dire
		-- « attends ».
		local phase = math.floor(widget.clock * 4) % 4
		widget.magazine.Text = ("."):rep(phase)
	end

	local target = if widget.visible then 0 else 1
	widget.alpha += (target - widget.alpha) * math.min(1, dt * Theme.motion.fade)

	if widget.alpha > 0.98 then
		widget.root.Visible = false
		return
	end

	widget.root.Visible = true
	widget.magazine.TextTransparency = widget.alpha
	widget.reserve.TextTransparency = math.min(1, widget.alpha + 0.1)
	widget.caliber.TextTransparency = math.min(1, widget.alpha + 0.2)
	widget.mode.TextTransparency = math.min(1, widget.alpha + 0.2)
end

function WeaponWidget.setVisible(widget: Widget, visible: boolean)
	widget.visible = visible
end

return WeaponWidget
