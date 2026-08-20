--!strict
-- Zone, heure et meteo, en haut a droite.
--
-- Trois lignes alignees a droite, sans cadre : la maquette les pose
-- directement sur l'image. C'est volontaire — ce sont les informations les
-- moins urgentes du HUD, elles ne meritent pas un panneau.
--
-- L'heure est la seule a bouger en continu, et elle avance lentement : c'est
-- un rappel de duree, pas un chronometre.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local WorldInfoWidget = {}

export type Widget = {
	root: Frame,
	clock: TextLabel,
	district: TextLabel,
	weather: TextLabel,
	clockIcon: Frame,
	weatherIcon: Frame,
	value: number,
}

local ROW = 20

function WorldInfoWidget.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "WorldInfo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(220, ROW * 3 + 6),
		Position = UDim2.new(1, -24, 0, 18),
		ZIndex = 2,
	}, parent) :: Frame

	-- Les pictogrammes sont a droite du texte, comme dans la maquette : le
	-- bord droit reste une ligne nette.
	local function row(index: number, iconKind: string, color: Color3): (TextLabel, Frame)
		local label = Components.label({
			text = "",
			size = Theme.size.label,
			color = color,
			align = Enum.TextXAlignment.Right,
			sizeUDim = UDim2.new(1, -20, 0, ROW),
			position = UDim2.fromOffset(0, (index - 1) * ROW),
		}, root)

		local icon = Components.icon(iconKind, color, {
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(12, 12),
			Position = UDim2.new(1, 0, 0, (index - 1) * ROW + ROW * 0.5),
		}, root)

		return label, icon
	end

	local clock, clockIcon = row(1, "clock", Theme.color.info)
	-- Le district n'a pas de pictogramme, contrairement a l'heure et a la
	-- meteo. Il ne doit donc PAS porter leur retrait de 20 px : sans icone a
	-- droite, ce retrait le laissait suspendu au milieu de rien. Il va au bord.
	local district = Components.label({
		text = "",
		size = Theme.size.label,
		color = Theme.color.neutral,
		align = Enum.TextXAlignment.Right,
		sizeUDim = UDim2.new(1, 0, 0, ROW),
		position = UDim2.fromOffset(0, ROW),
	}, root)
	local weather, weatherIcon = row(3, "weather", Theme.color.neutral)

	root.Visible = true

	return {
		root = root,
		clock = clock,
		district = district,
		weather = weather,
		clockIcon = clockIcon,
		weatherIcon = weatherIcon,
		value = 0,
	}
end

-- `clock` est une heure decimale Roblox (19.5 = 19h30), eventuellement
-- au-dela de 24 quand la nuit deborde sur le lendemain.
function WorldInfoWidget.setInfo(widget: Widget, district: string, weather: string, clock: number)
	local hours = math.floor(clock) % 24
	local minutes = math.floor((clock % 1) * 60)

	widget.clock.Text = string.format("%02d:%02d", hours, minutes)

	-- District et meteo arrivent en identifiants stables ; on les traduit ici,
	-- avec repli sur l'identifiant brut pour qu'un lieu ajoute sans traduction
	-- reste lisible.
	widget.district.Text = Locale.maybe(`world.district.{district}`) or district
	widget.weather.Text = Locale.maybe(`world.weather.{weather}`) or weather
	widget.value = clock
end

function WorldInfoWidget.setVisible(widget: Widget, visible: boolean)
	widget.root.Visible = visible
end

return WorldInfoWidget
