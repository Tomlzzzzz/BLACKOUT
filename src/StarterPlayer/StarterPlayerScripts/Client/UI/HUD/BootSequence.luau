--!strict
-- Sequence d'allumage du terminal.
--
-- A chaque apparition, le HUD ne surgit pas : il DEMARRE. Un balayage
-- horizontal traverse l'ecran, trois lignes de terminal se frappent au
-- centre, puis les panneaux entrent en decale.
--
-- POURQUOI CA COMPTE
--
-- C'est deux secondes qui installent la fiction : le joueur ne « voit pas
-- une interface », il allume un equipement. C'est aussi la seule occasion du
-- jeu de nommer le materiel et l'employeur sans que ce soit du bavardage.
--
-- La sequence est PUREMENT visuelle et ne bloque rien. Un joueur qui court
-- des la premiere image joue normalement ; il rate juste l'animation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local BootSequence = {}

export type Widget = {
	root: Frame,
	sweep: Frame,
	lines: { TextLabel },
	clock: number,
	running: boolean,
	tag: string,
}

-- Duree totale, et instants d'apparition de chaque ligne.
local DURATION = 2.4
local LINE_AT = { 0.15, 0.55, 0.95 }
local LINE_TYPE_RATE = 38

function BootSequence.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "Boot",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 30,
	}, parent) :: Frame

	-- Balayage : une bande fine qui descend, avec un degrade pour ne pas
	-- ressembler a un trait plein.
	local sweep = Components.new("Frame", {
		BackgroundColor3 = Theme.color.cyan,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.fromScale(0, 0),
		ZIndex = 31,
	}, root) :: Frame

	Components.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, sweep)

	local lines: { TextLabel } = {}
	for index = 1, 3 do
		table.insert(lines, Components.label({
			text = "",
			font = Theme.font.mono,
			size = if index == 1 then Theme.size.body else Theme.size.label,
			color = if index == 1 then Theme.color.info else Theme.color.dim,
			align = Enum.TextXAlignment.Center,
			anchor = Vector2.new(0.5, 0),
			sizeUDim = UDim2.fromOffset(520, 20),
			position = UDim2.new(0.5, 0, 0.44, (index - 1) * 22),
			zIndex = 32,
		}, root))
	end

	return { root = root, sweep = sweep, lines = lines, clock = 0, running = false, tag = "" }
end

function BootSequence.play(widget: Widget, tag: string)
	widget.clock = 0
	widget.running = true
	widget.tag = tag
	widget.root.Visible = true
	for _, label in widget.lines do
		label.Text = ""
		label.TextTransparency = 0
	end
end

function BootSequence.step(widget: Widget, dt: number): boolean
	if not widget.running then
		return false
	end

	widget.clock += dt
	local progress = widget.clock / DURATION

	if progress >= 1 then
		widget.running = false
		widget.root.Visible = false
		return false
	end

	-- Le balayage traverse sur le premier tiers, puis disparait.
	local sweepProgress = math.min(1, widget.clock / (DURATION * 0.42))
	widget.sweep.Position = UDim2.fromScale(0, sweepProgress)
	widget.sweep.BackgroundTransparency = 0.7 + sweepProgress * 0.3

	for index, label in widget.lines do
		local startAt = LINE_AT[index]
		if widget.clock < startAt then
			continue
		end

		local key = `hud.boot.{index}`
		local full = Locale.t(key, { tag = widget.tag })
		local shown = math.floor((widget.clock - startAt) * LINE_TYPE_RATE)

		-- Decoupe respectueuse de l'UTF-8 : couper au milieu d'un caractere
		-- accentue afficherait un glyphe casse pendant une image.
		local boundary = utf8.offset(full, shown + 1)
		label.Text = if boundary then full:sub(1, boundary - 1) else full

		-- Les lignes s'effacent sur le dernier quart, pour rendre l'ecran au
		-- jeu sans coupure brutale.
		if progress > 0.75 then
			label.TextTransparency = (progress - 0.75) / 0.25
		end
	end

	return true
end

-- Avancement 0-1, lu par HUDController pour faire entrer les panneaux en
-- decale derriere la sequence.
function BootSequence.progress(widget: Widget): number
	if not widget.running then
		return 1
	end
	return math.clamp(widget.clock / DURATION, 0, 1)
end

return BootSequence
