--!strict
-- File d'evenements, a droite au-dessus de l'arme.
--
-- Une pile de lignes qui entrent par la droite, tiennent quelques secondes,
-- puis s'effacent en laissant remonter les suivantes. Butin ramasse, cible
-- abattue, objectif rempli, plaque posee.
--
-- POURQUOI UNE FILE ET PAS DES POPUPS
--
-- Ces evenements arrivent en rafale — un conteneur donne cinq objets d'un
-- coup. Cinq popups se recouvriraient ; une file les empile et les rend
-- tous lisibles, dans l'ordre.
--
-- Les lignes sont creees une fois et recyclees : rien n'est instancie en
-- cours de partie.

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local EventFeed = {}

type Row = {
	root: Frame,
	icon: Frame,
	label: TextLabel,
	amount: TextLabel,
	life: number,
	slot: number,
	offset: number,
}

export type Widget = {
	root: Frame,
	rows: { Row },
	nextSlot: number,
}

local ROWS = 6
local ROW_HEIGHT = 20
local LIFE = 4.5

-- Duree du glissement d'entree, en secondes.
local SLIDE = 0.22

function EventFeed.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "EventFeed",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(280, ROWS * ROW_HEIGHT),
		Position = UDim2.new(1, -24, 1, -110),
		ZIndex = 6,
	}, parent) :: Frame

	local rows: { Row } = {}
	for index = 1, ROWS do
		local rowRoot = Components.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			Position = UDim2.fromOffset(0, (index - 1) * ROW_HEIGHT),
			Visible = false,
			ZIndex = 6,
		}, root) :: Frame

		local icon = Components.new("Frame", {
			BackgroundColor3 = Theme.color.neutral,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(3, 3),
			Position = UDim2.new(1, 0, 0.5, 0),
			Rotation = 45,
			ZIndex = 7,
		}, rowRoot) :: Frame

		local label = Components.label({
			text = "",
			size = Theme.size.label,
			color = Theme.color.neutral,
			align = Enum.TextXAlignment.Right,
			anchor = Vector2.new(1, 0),
			sizeUDim = UDim2.new(1, -46, 0, ROW_HEIGHT),
			position = UDim2.new(1, -12, 0, 0),
			zIndex = 7,
		}, rowRoot)

		local amount = Components.label({
			text = "",
			font = Theme.font.mono,
			size = Theme.size.label,
			color = Theme.color.info,
			align = Enum.TextXAlignment.Right,
			anchor = Vector2.new(1, 0),
			sizeUDim = UDim2.fromOffset(34, ROW_HEIGHT),
			position = UDim2.new(1, -12, 0, 0),
			zIndex = 7,
		}, rowRoot)
		amount.Visible = false

		table.insert(rows, {
			root = rowRoot,
			icon = icon,
			label = label,
			amount = amount,
			life = 0,
			slot = index,
			offset = 0,
		})
	end

	return { root = root, rows = rows, nextSlot = 0 }
end

-- Ajoute une ligne. `amount` optionnel : « x3 » pour du butin, rien pour un
-- evenement sans quantite.
function EventFeed.push(widget: Widget, text: string, color: Color3?, amount: string?)
	-- On recycle la ligne la plus ancienne : la file ne grandit jamais.
	local target = widget.rows[1]
	for _, row in widget.rows do
		if row.life < target.life then
			target = row
		end
	end

	-- Les lignes existantes descendent d'un cran pour laisser la place en
	-- haut : la plus recente est toujours la plus basse, pres de l'oeil.
	for _, row in widget.rows do
		if row ~= target and row.life > 0 then
			row.slot = math.max(1, row.slot - 1)
		end
	end

	target.life = LIFE
	target.slot = ROWS
	target.offset = 1
	target.root.Visible = true
	target.label.Text = text
	target.label.TextColor3 = color or Theme.color.neutral
	target.icon.BackgroundColor3 = color or Theme.color.neutral

	if amount then
		target.amount.Visible = true
		target.amount.Text = amount
		target.amount.TextColor3 = color or Theme.color.info
		target.label.Size = UDim2.new(1, -84, 0, ROW_HEIGHT)
		target.label.Position = UDim2.new(1, -50, 0, 0)
	else
		target.amount.Visible = false
		target.label.Size = UDim2.new(1, -46, 0, ROW_HEIGHT)
		target.label.Position = UDim2.new(1, -12, 0, 0)
	end
end

function EventFeed.step(widget: Widget, dt: number)
	for _, row in widget.rows do
		if row.life <= 0 then
			continue
		end

		row.life -= dt
		if row.life <= 0 then
			row.root.Visible = false
			continue
		end

		-- Glissement d'entree : la ligne arrive par la droite.
		row.offset = math.max(0, row.offset - dt / SLIDE)
		local slide = row.offset * 40

		-- Position verticale interpolee : quand une ligne au-dessus expire,
		-- les autres remontent au lieu de sauter.
		local targetY = (row.slot - 1) * ROW_HEIGHT
		local currentY = row.root.Position.Y.Offset
		local nextY = currentY + (targetY - currentY) * math.min(1, dt * 12)

		row.root.Position = UDim2.fromOffset(math.floor(slide), math.floor(nextY))

		-- Effacement sur la derniere seconde seulement : avant, la ligne
		-- reste pleinement lisible.
		local fade = if row.life < 1 then 1 - row.life else 0
		local entering = row.offset
		local alpha = math.max(fade, entering)

		row.label.TextTransparency = alpha
		row.amount.TextTransparency = alpha
		row.icon.BackgroundTransparency = math.min(1, alpha + 0.2)
	end
end

function EventFeed.clear(widget: Widget)
	for _, row in widget.rows do
		row.life = 0
		row.root.Visible = false
	end
end

function EventFeed.setVisible(widget: Widget, visible: boolean)
	widget.root.Visible = visible
end

return EventFeed
