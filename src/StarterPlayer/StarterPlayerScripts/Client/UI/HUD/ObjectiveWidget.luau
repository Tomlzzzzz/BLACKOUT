--!strict
-- Panneau de contrat, a gauche.
--
-- La maquette le montre avec equerres d'angle, en-tete ambre, titre blanc,
-- sous-titre gris, puis les objectifs marques d'un losange, et un rappel de
-- touche en pied.
--
-- Regle de couleur : l'ambre est la couleur des OBJECTIFS. Un objectif
-- rempli passe au vert avec une coche. Un objectif en attente reste neutre —
-- si tout etait ambre, plus rien ne ressortirait.
--
-- Les lignes sont creees une fois pour le maximum d'objectifs prevu et
-- reutilisees : un contrat qui change ne doit pas reconstruire le panneau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local ObjectiveWidget = {}

type Row = {
	root: Frame,
	marker: TextLabel,
	label: TextLabel,
	progress: TextLabel,
}

export type Widget = {
	panel: Components.Panel,
	header: TextLabel,
	headerDot: Frame,
	title: TextLabel,
	subtitle: TextLabel,
	rows: { Row },
	flashKey: string?,
	flashLife: number,
	footer: TextLabel,
	footerSuffix: TextLabel,
	keyBox: Frame,
	keyLabel: TextLabel,
	alpha: number,
	visible: boolean,
}

local MAX_ROWS = 4
local ROW_HEIGHT = 22

-- Losange vide / coche. Les deux existent dans les polices Roblox standard.
local MARK_PENDING = "\u{25C7}"
local MARK_DONE = "\u{2713}"

function ObjectiveWidget.create(parent: Instance): Widget
	local height = 96 + MAX_ROWS * ROW_HEIGHT

	local panel = Components.panel({
		Name = "Objectives",
		Size = UDim2.fromOffset(268, height),
		Position = UDim2.fromOffset(24, 138),
	}, parent, Theme.color.border)

	local headerDot = Components.new("Frame", {
		BackgroundColor3 = Theme.color.amber,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(4, 4),
		Position = UDim2.new(0, 0, 0, 12),
		Rotation = 45,
		ZIndex = 3,
	}, panel.body) :: Frame

	local header = Components.label({
		text = Components.spaced(Locale.t("hud.contract.current")),
		size = Theme.size.micro,
		color = Theme.color.amber,
		sizeUDim = UDim2.new(1, -12, 0, 14),
		position = UDim2.fromOffset(12, 5),
	}, panel.body)

	local title = Components.label({
		text = "",
		size = Theme.size.value,
		color = Theme.color.info,
		sizeUDim = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromOffset(0, 24),
	}, panel.body)

	local subtitle = Components.label({
		text = "",
		size = Theme.size.label,
		color = Theme.color.dim,
		sizeUDim = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(0, 48),
	}, panel.body)

	Components.separator({
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.fromOffset(0, 70),
	}, panel.body)

	local rows: { Row } = {}
	for index = 1, MAX_ROWS do
		local rowRoot = Components.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			Position = UDim2.fromOffset(0, 78 + (index - 1) * ROW_HEIGHT),
			Visible = false,
			ZIndex = 2,
		}, panel.body) :: Frame

		local marker = Components.label({
			text = MARK_PENDING,
			size = Theme.size.label,
			color = Theme.color.dim,
			sizeUDim = UDim2.fromOffset(16, ROW_HEIGHT),
		}, rowRoot)

		local label = Components.label({
			text = "",
			size = Theme.size.label,
			color = Theme.color.neutral,
			sizeUDim = UDim2.new(1, -66, 0, ROW_HEIGHT),
			position = UDim2.fromOffset(18, 0),
		}, rowRoot)

		local progress = Components.label({
			text = "",
			font = Theme.font.mono,
			size = Theme.size.label,
			color = Theme.color.amber,
			align = Enum.TextXAlignment.Right,
			anchor = Vector2.new(1, 0),
			sizeUDim = UDim2.fromOffset(44, ROW_HEIGHT),
			position = UDim2.fromScale(1, 0),
		}, rowRoot)

		table.insert(rows, { root = rowRoot, marker = marker, label = label, progress = progress })
	end

	Components.separator({
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -26),
	}, panel.body)

	-- PIED DE PAGE : « APPUYER [M] POUR LA CARTE ».
	--
	-- Trois elements poses par un UIListLayout horizontal, et non a des
	-- positions calculees.
	--
	-- Deux versions ont echoue avant celle-ci. La premiere reservait la place
	-- du cadre avec des espaces dans le texte : la largeur d'un espace depend
	-- de la police et de l'echelle, le cadre ne tombait plus dans le trou des
	-- le premier changement de taille. La seconde posait le cadre a x=44 et le
	-- suffixe a x=64 : ecarts de 14 px avant et 6 px apres, donc un cadre
	-- visiblement decale — et « APPUYER », plus long que « PRESS », debordait
	-- de sa boite de 40 px.
	--
	-- Avec AutomaticSize sur les libelles, le layout mesure lui-meme et pose
	-- le meme ecart des deux cotes, dans n'importe quelle langue et a
	-- n'importe quelle echelle. C'est la seule facon d'etre CENTRE plutot que
	-- de viser juste.
	local footerRow = Components.new("Frame", {
		Name = "MapHint",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -20),
		ZIndex = 3,
	}, panel.body) :: Frame

	Components.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, footerRow)

	local footer = Components.label({
		text = Locale.t("hud.contract.pressPrefix"),
		size = Theme.size.micro,
		color = Theme.color.faint,
		sizeUDim = UDim2.fromOffset(0, 14),
		zIndex = 3,
	}, footerRow)
	footer.AutomaticSize = Enum.AutomaticSize.X
	footer.LayoutOrder = 1

	local keyBox = Components.new("Frame", {
		BackgroundColor3 = Theme.color.raised,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(14, 14),
		LayoutOrder = 2,
		ZIndex = 3,
	}, footerRow) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(0, 2) }, keyBox)
	Components.new("UIStroke", { Color = Theme.color.border, Thickness = 1, Transparency = 0.2 }, keyBox)

	local keyLabel = Components.label({
		text = "M",
		size = Theme.size.micro,
		color = Theme.color.neutral,
		align = Enum.TextXAlignment.Center,
		zIndex = 4,
	}, keyBox)

	local footerSuffix = Components.label({
		text = Locale.t("hud.contract.pressSuffix"),
		size = Theme.size.micro,
		color = Theme.color.faint,
		sizeUDim = UDim2.fromOffset(0, 14),
		zIndex = 3,
	}, footerRow)
	footerSuffix.AutomaticSize = Enum.AutomaticSize.X
	footerSuffix.LayoutOrder = 3

	return {
		panel = panel,
		header = header,
		headerDot = headerDot,
		title = title,
		subtitle = subtitle,
		rows = rows,
		flashKey = nil,
		flashLife = 0,
		footer = footer,
		footerSuffix = footerSuffix,
		keyBox = keyBox,
		keyLabel = keyLabel,
		alpha = 1,
		visible = false,
	}
end

-- `contract` nil masque le panneau. Un contrat absent ne doit pas laisser un
-- cadre vide a l'ecran.
function ObjectiveWidget.setContract(widget: Widget, contract: any?)
	if not contract then
		widget.visible = false
		return
	end

	widget.visible = true
	widget.panel.root.Visible = true
	widget.title.Text = Locale.t(contract.titleKey)
	widget.subtitle.Text = Locale.t(contract.subtitleKey)

	for index, row in widget.rows do
		local objective = contract.objectives[index]
		if not objective then
			row.root.Visible = false
			continue
		end

		row.root.Visible = true
		row.label.Text = Locale.t(objective.labelKey)

		if objective.done then
			row.marker.Text = MARK_DONE
			row.marker.TextColor3 = Theme.color.extraction
			row.label.TextColor3 = Theme.color.extraction
			row.label.TextTransparency = 0.25
			row.progress.Text = ""
		else
			row.marker.Text = MARK_PENDING
			row.marker.TextColor3 = Theme.color.dim
			row.label.TextColor3 = Theme.color.neutral
			row.label.TextTransparency = 0
			-- La progression ne s'affiche que si elle a un sens : « atteindre
			-- la sortie » n'a pas de compteur.
			row.progress.Text = if objective.quantity
				then `{objective.progress}/{objective.quantity}`
				else ""
		end
	end

	-- Contrat rempli : l'en-tete passe au vert. C'est le seul moment ou ce
	-- panneau quitte l'ambre.
	local done = contract.complete == true
	widget.header.Text = Components.spaced(Locale.t(if done then "hud.contract.complete" else "hud.contract.current"))
	widget.header.TextColor3 = if done then Theme.color.extraction else Theme.color.amber
	widget.headerDot.BackgroundColor3 = if done then Theme.color.extraction else Theme.color.amber
end

-- Marque une ligne comme venant d'etre validee : elle pulse en vert une
-- seconde. Sans ce signal, un objectif rempli change juste de couleur — et un
-- changement de couleur hors du regard passe totalement inapercu.
function ObjectiveWidget.flash(widget: Widget, labelKey: string)
	widget.flashKey = labelKey
	widget.flashLife = 1.2
end

-- Fondu d'entree et de sortie. La consigne demande une animation discrete :
-- une opacite qui glisse, rien de plus.
function ObjectiveWidget.step(widget: Widget, dt: number)
	-- Pulsation de la ligne qui vient d'etre validee.
	if widget.flashLife > 0 then
		widget.flashLife -= dt
		local key = widget.flashKey
		for _, row in widget.rows do
			if key and row.root.Visible and row.label.Text == Locale.t(key) then
				local beat = math.abs(math.sin(widget.flashLife * 9))
				row.label.TextTransparency = 0.25 - beat * 0.25
				row.marker.TextTransparency = 0.5 - beat * 0.5
			end
		end
		if widget.flashLife <= 0 then
			widget.flashKey = nil
		end
	end

	local target = if widget.visible then 0 else 1
	widget.alpha += (target - widget.alpha) * math.min(1, dt * Theme.motion.fade)

	if widget.alpha > 0.98 then
		widget.panel.root.Visible = false
		return
	end

	widget.panel.root.Visible = true
	widget.panel.root.BackgroundTransparency = Theme.panel.background + widget.alpha * (1 - Theme.panel.background)

	local stroke = widget.panel.root:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0.25 + widget.alpha * 0.75
	end

	widget.title.TextTransparency = widget.alpha
	widget.subtitle.TextTransparency = math.min(1, widget.alpha + 0.15)
	widget.header.TextTransparency = widget.alpha
	widget.footer.TextTransparency = math.min(1, widget.alpha + 0.2)
	widget.footerSuffix.TextTransparency = math.min(1, widget.alpha + 0.2)
end

function ObjectiveWidget.setVisible(widget: Widget, visible: boolean)
	widget.visible = visible
end

return ObjectiveWidget
