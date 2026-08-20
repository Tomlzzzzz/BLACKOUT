--!strict
-- Indicateur directionnel de degats.
--
-- En premiere personne, savoir QU'ON encaisse ne sert a rien si on ne sait
-- pas D'OU. Le champ de vision est reduit a ce qu'on regarde : sans cet
-- indicateur, se faire frapper dans le dos est une mort sans information.
--
-- Un arc apparait autour du centre de l'ecran, oriente vers l'agresseur, et
-- s'efface en une seconde. Plusieurs arcs peuvent coexister : deux crawlers
-- qui frappent des deux cotes doivent produire deux marques.
--
-- L'angle est calcule CLIENT a partir d'une position envoyee par le serveur.
-- C'est de la presentation pure : le client ne decide de rien, il oriente une
-- image a partir d'un fait deja etabli.

local Workspace = game:GetService("Workspace")

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local DamageIndicator = {}

type Arc = {
	root: Frame,
	angle: number,
	life: number,
	strength: number,
}

export type Widget = {
	root: Frame,
	arcs: { Arc },
}

local POOL = 6
local LIFE = 1.3

-- Rayon de l'arc depuis le centre, en fraction de la hauteur d'ecran.
--
-- Repousse de 0.13 a 0.19 : a 0.13 l'arc tombait dans la zone que le
-- joueur fixe pour viser, ou il se lisait comme une rayure sur l'ecran
-- plutot que comme une direction.
local RADIUS = 0.19

function DamageIndicator.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "DamageDirection",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
	}, parent) :: Frame

	local arcs: { Arc } = {}
	for _ = 1, POOL do
		-- Un arc est un trapeze approche par une barre epaisse, arrondie et
		-- degradee. Roblox ne dessine pas d'arc : trois Frames coutent moins
		-- cher qu'une image a televerser et restent nettes partout.
		local arc = Components.new("Frame", {
			BackgroundColor3 = Theme.color.danger,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(150, 10),
			Position = UDim2.fromScale(0.5, 0.5),
			Visible = false,
			ZIndex = 20,
		}, root) :: Frame

		Components.new("UICorner", { CornerRadius = UDim.new(1, 0) }, arc)
		Components.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.22, 0.35),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.78, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, arc)

		table.insert(arcs, { root = arc, angle = 0, life = 0, strength = 1 })
	end

	return { root = root, arcs = arcs }
end

-- `origin` est la position monde de l'agresseur. `severity` module la taille
-- et l'opacite : un coup leger ne doit pas produire la meme marque qu'un coup
-- qui manque de tuer.
function DamageIndicator.hit(widget: Widget, origin: Vector3?, severity: string)
	local camera = Workspace.CurrentCamera
	local character = game.Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not camera or not origin or not root or not root:IsA("BasePart") then
		return
	end

	-- Angle entre la direction du regard et la direction de l'agresseur, dans
	-- le plan horizontal. C'est ce qui fait qu'un arc reste a gauche quand on
	-- tourne la tete.
	local flatLook = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	local flatTo = (origin - root.Position) * Vector3.new(1, 0, 1)

	if flatLook.Magnitude < 1e-3 or flatTo.Magnitude < 1e-3 then
		return
	end

	flatLook = flatLook.Unit
	flatTo = flatTo.Unit

	local dot = math.clamp(flatLook:Dot(flatTo), -1, 1)
	local cross = flatLook:Cross(flatTo).Y
	local angle = math.atan2(cross, dot)

	local strength = if severity == "critical" then 1 elseif severity == "heavy" then 0.75 else 0.5

	-- On reutilise l'arc le plus ancien : jamais de creation a chaud, et un
	-- flot de degats ne peut pas faire enfler la pile d'instances.
	local oldest = widget.arcs[1]
	for _, arc in widget.arcs do
		if arc.life < oldest.life then
			oldest = arc
		end
	end

	oldest.angle = angle
	oldest.life = LIFE
	oldest.strength = strength
	oldest.root.Visible = true
end

function DamageIndicator.step(widget: Widget, dt: number)
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 1080
	local aspect = if camera and camera.ViewportSize.Y > 0
		then camera.ViewportSize.X / camera.ViewportSize.Y
		else 1.777

	for _, arc in widget.arcs do
		if arc.life <= 0 then
			continue
		end

		arc.life -= dt
		if arc.life <= 0 then
			arc.root.Visible = false
			continue
		end

		local fade = arc.life / LIFE

		-- Position sur un cercle autour du centre. Le rayon est exprime en
		-- fraction de HAUTEUR puis corrige par le rapport d'image : sans
		-- cela l'anneau serait un ovale sur un ecran large.
		local offsetX = math.sin(arc.angle) * RADIUS / aspect
		local offsetY = -math.cos(arc.angle) * RADIUS

		arc.root.Position = UDim2.fromScale(0.5 + offsetX, 0.5 + offsetY)
		-- L'arc est tangent au cercle : perpendiculaire au rayon.
		arc.root.Rotation = math.deg(arc.angle)
		arc.root.Size = UDim2.fromOffset(
			math.floor(height * 0.135 * (0.65 + arc.strength * 0.55)),
			math.max(6, math.floor(height * 0.0105))
		)
		arc.root.BackgroundTransparency = 1 - fade * arc.strength
	end
end

function DamageIndicator.clear(widget: Widget)
	for _, arc in widget.arcs do
		arc.life = 0
		arc.root.Visible = false
	end
end

return DamageIndicator
