--!strict
-- Identifiant de jeu, en haut a gauche.
--
-- « BLACKOUT » et la version sous-jacente. Purement identitaire : c'est le
-- seul element du HUD qui ne dit rien sur la partie en cours.
--
-- Il reste tres discret et ne reagit a rien. La maquette le place la comme
-- une marque de build, pas comme une information.

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local IdentityWidget = {}

export type Widget = {
	root: Frame,
	title: TextLabel,
	accent: TextLabel,
	version: TextLabel,
}

-- Le « A » de BLACKOUT est accentue en rouge dans la maquette. Roblox ne sait
-- pas colorer un caractere dans un TextLabel : on superpose donc un second
-- label qui ne contient que cette lettre, aligne par une chasse fixe.
--
-- C'est pour cela que le titre est en RobotoMono et non en RobotoCondensed :
-- une chasse variable rendrait l'alignement de la lettre impossible a tenir.
local TITLE = "BLACKOUT"
local ACCENT_INDEX = 3

function IdentityWidget.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "Identity",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, 46),
		Position = UDim2.fromOffset(24, 18),
		ZIndex = 2,
	}, parent) :: Frame

	local title = Components.label({
		text = Components.spaced(TITLE),
		font = Theme.font.mono,
		size = Theme.size.large,
		color = Theme.color.info,
		sizeUDim = UDim2.new(1, 0, 0, 32),
	}, root)

	-- Masque de la lettre accentuee : meme texte, tout efface sauf le A.
	local masked = {}
	for index = 1, #TITLE do
		table.insert(masked, if index == ACCENT_INDEX then TITLE:sub(index, index) else " ")
	end

	local accent = Components.label({
		text = Components.spaced(table.concat(masked)),
		font = Theme.font.mono,
		size = Theme.size.large,
		color = Theme.color.danger,
		sizeUDim = UDim2.new(1, 0, 0, 32),
		zIndex = 3,
	}, root)

	local version = Components.label({
		text = "EARLY ACCESS V0.1.0",
		size = Theme.size.micro,
		color = Theme.color.faint,
		sizeUDim = UDim2.new(1, 0, 0, 12),
		position = UDim2.fromOffset(2, 32),
	}, root)

	root.Visible = true

	return { root = root, title = title, accent = accent, version = version }
end

function IdentityWidget.setVersion(widget: Widget, text: string)
	widget.version.Text = text
end

function IdentityWidget.setVisible(widget: Widget, visible: boolean)
	widget.root.Visible = visible
end

return IdentityWidget
