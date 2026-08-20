--!strict
-- Annonce de changement de palier de menace.
--
-- Une bande fine qui s'ouvre depuis le centre, affiche le nouveau palier,
-- puis se referme. Deux secondes, une seule fois par montee.
--
-- POURQUOI CET ELEMENT EXISTE
--
-- La barre de menace est en haut de l'ecran ; en premiere personne, le joueur
-- regarde devant lui. Franchir un palier est l'evenement le plus important du
-- jeu apres l'extraction, et il se produisait sans que rien ne l'annonce au
-- centre du champ de vision.
--
-- Il ne s'affiche QUE sur les montees. Redescendre est une bonne nouvelle :
-- elle n'a pas besoin d'interrompre.

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local BandBanner = {}

export type Widget = {
	root: Frame,
	ruleTop: Frame,
	ruleBottom: Frame,
	label: TextLabel,
	life: number,
}

local LIFE = 2.2
local OPEN = 0.28
local CLOSE = 0.35

function BandBanner.create(parent: Instance): Widget
	local root = Components.new("Frame", {
		Name = "BandBanner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 620, 0, 46),
		Position = UDim2.fromScale(0.5, 0.3),
		Visible = false,
		ZIndex = 18,
	}, parent) :: Frame

	-- Deux filets qui s'ecartent : l'ouverture se lit comme un mecanisme, pas
	-- comme une boite qui apparait.
	local function rule(y: number): Frame
		return Components.new("Frame", {
			BackgroundColor3 = Theme.color.danger,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0, 0),
			Position = UDim2.fromScale(0.5, y),
			ZIndex = 18,
		}, root) :: Frame
	end

	local ruleTop = rule(0.08)
	local ruleBottom = rule(0.92)

	local label = Components.label({
		text = "",
		size = Theme.size.value,
		color = Theme.color.danger,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.fromScale(1, 1),
		zIndex = 19,
	}, root)

	return { root = root, ruleTop = ruleTop, ruleBottom = ruleBottom, label = label, life = 0 }
end

function BandBanner.announce(widget: Widget, text: string, color: Color3)
	widget.life = LIFE
	widget.root.Visible = true
	widget.label.Text = Components.spaced(text)
	widget.label.TextColor3 = color
	widget.ruleTop.BackgroundColor3 = color
	widget.ruleBottom.BackgroundColor3 = color
end

function BandBanner.step(widget: Widget, dt: number)
	if widget.life <= 0 then
		return
	end

	widget.life -= dt
	if widget.life <= 0 then
		widget.root.Visible = false
		return
	end

	local elapsed = LIFE - widget.life

	-- Trois phases : ouverture, maintien, fermeture.
	local width, alpha

	if elapsed < OPEN then
		local t = elapsed / OPEN
		width = t * t
		alpha = 1 - t
	elseif widget.life < CLOSE then
		local t = widget.life / CLOSE
		width = t
		alpha = 1 - t
	else
		width = 1
		alpha = 0
	end

	widget.ruleTop.Size = UDim2.new(width, 0, 0, 1)
	widget.ruleBottom.Size = UDim2.new(width, 0, 0, 1)
	widget.label.TextTransparency = alpha

	-- Le texte respire pendant le maintien : il reste vivant sans bouger.
	if alpha <= 0 then
		widget.label.TextTransparency = math.abs(math.sin(elapsed * 3)) * 0.12
	end
end

return BandBanner
