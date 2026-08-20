--!strict
-- Retour plein ecran : degats, escalade de menace, bandeau de chasse.
--
-- Deux principes, tous deux dans la consigne :
--
--   Le rouge MORD LES BORDS, il ne couvre jamais l'ecran. Un ecran noye de
--   rouge empeche de jouer au moment ou il faut le plus voir.
--
--   Le HUD REAGIT plutot que d'afficher un avertissement fixe. C'est la
--   difference entre « tu es en danger » ecrit quelque part et un ecran qui
--   se comporte comme si on l'etait.
--
-- Tout vit sur une couche separee, au-dessus du jeu et sous les panneaux.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local DamageFeedback = {}

export type Widget = {
	gui: ScreenGui,
	edges: { Frame },
	flashLayer: Frame,
	scanlines: { Frame },
	huntBanner: Frame,
	huntLabel: TextLabel,
	huntSub: TextLabel,

	band: string,
	hunting: boolean,
	intensity: number,
	damage: number,
	damageDecay: number,
	flash: number,
	flashDecay: number,
	pulse: number,
	clock: number,
	flickerAt: number,
	huntUntil: number,
}

local SCANLINES = 5

function DamageFeedback.create(playerGui: Instance): Widget
	local gui = Components.new("ScreenGui", {
		Name = "BlackoutFeedback",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 8,
	}, playerGui) :: ScreenGui

	-- Quatre degrades de bord. Un halo construit ainsi ne masque jamais le
	-- centre de l'ecran, ce qu'un cadre plein ferait.
	-- Bandes VOLONTAIREMENT etroites, avec une chute rapide.
	--
	-- Premiere version : 30 % de hauteur et 22 % de largeur, degrade lineaire.
	-- Resultat mesure a l'ecran — l'image entiere virait au rouge des le
	-- palier HIGH, ce qui est exactement ce que la consigne interdit. Le
	-- rouge doit mordre le bord et rendre le centre au jeu.
	local edges: { Frame } = {}
	local specs = {
		{ size = UDim2.new(1, 0, 0.105, 0), pos = UDim2.fromScale(0, 0), rot = 90 },
		{ size = UDim2.new(1, 0, 0.105, 0), pos = UDim2.fromScale(0, 0.895), rot = 270 },
		{ size = UDim2.new(0.08, 0, 1, 0), pos = UDim2.fromScale(0, 0), rot = 0 },
		{ size = UDim2.new(0.08, 0, 1, 0), pos = UDim2.fromScale(0.92, 0), rot = 180 },
	}

	for _, spec in specs do
		local edge = Components.new("Frame", {
			BackgroundColor3 = Theme.color.danger,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = spec.size,
			Position = spec.pos,
			ZIndex = 1,
		}, gui) :: Frame

		-- Point median a 35 % : la teinte s'effondre bien avant le bord
		-- interieur de la bande. Un degrade lineaire laissait 30 % d'opacite
		-- a mi-ecran.
		Components.new("UIGradient", {
			Rotation = spec.rot,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.28, 0.82),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, edge)

		table.insert(edges, edge)
	end

	-- Nappe d'impact, plein ecran.
	--
	-- Volontairement au-DESSUS des bandes de bord et volontairement tres
	-- breve : c'est un coup, pas une teinte. Une nappe qui durerait une
	-- demi-seconde redeviendrait le voile rouge qu'on vient de retirer.
	local flashLayer = Components.new("Frame", {
		Name = "Impact",
		BackgroundColor3 = Theme.color.danger,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, gui) :: Frame

	-- Lignes de balayage : signature « flux video degrade ». Elles
	-- n'apparaissent qu'a partir de HIGH.
	local scanlines: { Frame } = {}
	for index = 1, SCANLINES do
		table.insert(scanlines, Components.new("Frame", {
			BackgroundColor3 = Theme.color.info,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2),
			Position = UDim2.fromScale(0, (index - 1) / SCANLINES),
			ZIndex = 2,
		}, gui))
	end

	local huntBanner = Components.new("Frame", {
		BackgroundColor3 = Theme.color.void,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(520, 92),
		Position = UDim2.fromScale(0.5, 0.4),
		Visible = false,
		ZIndex = 20,
	}, gui) :: Frame
	Components.new("UICorner", { CornerRadius = UDim.new(0, Theme.panel.corner) }, huntBanner)

	Components.new("UIStroke", { Color = Theme.color.danger, Thickness = 1, Transparency = 0.35 }, huntBanner)

	local huntLabel = Components.label({
		text = Components.spaced(Locale.t("hud.hunt.title")),
		font = Theme.font.hero,
		size = 44,
		color = Theme.color.danger,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.new(1, 0, 0, 54),
		zIndex = 21,
	}, huntBanner)

	local huntSub = Components.label({
		text = Components.spaced(Locale.t("hud.hunt.sub")),
		size = Theme.size.label,
		color = Theme.color.neutral,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 58),
		zIndex = 21,
	}, huntBanner)

	return {
		gui = gui,
		edges = edges,
		flashLayer = flashLayer,
		scanlines = scanlines,
		huntBanner = huntBanner,
		huntLabel = huntLabel,
		huntSub = huntSub,
		band = "SAFE",
		hunting = false,
		intensity = 0,
		damage = 0,
		damageDecay = 1,
		flash = 0,
		flashDecay = 1,
		pulse = 0,
		clock = 0,
		flickerAt = 0,
		huntUntil = 0,
	}
end

function DamageFeedback.setBand(widget: Widget, band: string)
	widget.band = band
end

-- La traque prime sur le palier : le compteur redescend pendant que le
-- Warden chasse encore.
function DamageFeedback.setHunt(widget: Widget, active: boolean)
	widget.hunting = active

	if active then
		-- Le bandeau est une TRANSITION, pas un etat permanent. Il s'affiche
		-- quelques secondes puis rend l'ecran au jeu, comme demande.
		widget.huntBanner.Visible = true
		widget.huntUntil = widget.clock + 3.2
	else
		widget.huntBanner.Visible = false
	end
end

function DamageFeedback.onDamage(widget: Widget, severity: string)
	local spec = Theme.damage[severity] or Theme.damage.light
	-- On prend le maximum : deux coups rapproches ne doivent pas s'annuler
	-- en repartant de zero.
	widget.damage = math.max(widget.damage, spec.intensity)
	widget.damageDecay = spec.intensity / math.max(0.05, spec.duration)

	local flash = Theme.damage.flash
	widget.flash = flash.intensity * spec.intensity
	widget.flashDecay = widget.flash / math.max(0.02, flash.duration)
end

function DamageFeedback.step(widget: Widget, dt: number)
	widget.clock += dt

	local key = if widget.hunting then "HUNT" else widget.band
	local escalation = Theme.threat.escalation[key] or Theme.threat.escalation.SAFE

	if widget.huntBanner.Visible and widget.clock >= widget.huntUntil then
		widget.huntBanner.Visible = false
	end

	-- Halo de menace, lisse pour ne jamais sauter d'un palier a l'autre.
	widget.intensity += (escalation.vignette - widget.intensity) * math.min(1, dt * 2.2)

	-- Degats : montee instantanee, retrait lineaire.
	if widget.damage > 0 then
		widget.damage = math.max(0, widget.damage - widget.damageDecay * dt)
	end

	local breath = 1
	if escalation.pulse > 0 then
		widget.pulse += dt * escalation.pulse
		breath = 0.75 + math.sin(widget.pulse) * 0.25
	end

	-- Le scintillement est un evenement rare, pas une animation continue :
	-- on le declenche par tirage, ce qui evite un motif reconnaissable.
	local flicker = 0
	if escalation.flicker > 0 and widget.clock >= widget.flickerAt then
		widget.flickerAt = widget.clock + (1 / escalation.flicker) * (0.5 + math.random())
		flicker = 0.18
	end

	if widget.flash > 0 then
		widget.flash = math.max(0, widget.flash - widget.flashDecay * dt)
	end
	widget.flashLayer.BackgroundTransparency = 1 - widget.flash

	-- COMPOSITION EN ECRAN, pas en somme.
	--
	-- `a + b` fait saturer les deux couches des qu'elles coexistent : sous la
	-- traque, le moindre coup encaisse repeignait l'image entiere. `a + b(1-a)`
	-- laisse toujours de la place a la seconde couche sans jamais depasser 1,
	-- et surtout garde une DIFFERENCE lisible entre « menace haute » et
	-- « menace haute + je viens de me faire toucher ».
	local ambient = math.clamp(widget.intensity * breath + flicker, 0, 1)
	local total = ambient + widget.damage * (1 - ambient)

	for _, edge in widget.edges do
		edge.BackgroundTransparency = 1 - math.clamp(total, 0, 1) * Theme.damage.maxEdge
	end

	if escalation.scan > 0 then
		for index, line in widget.scanlines do
			line.Position = UDim2.fromScale(0, ((widget.clock * 0.05) + (index - 1) / SCANLINES) % 1)
			line.BackgroundTransparency = escalation.scan
		end
	else
		for _, line in widget.scanlines do
			line.BackgroundTransparency = 1
		end
	end

	if widget.huntBanner.Visible then
		local flash = 0.5 + math.sin(widget.clock * 9) * 0.5
		widget.huntBanner.BackgroundTransparency = 0.2 + flash * 0.14
		widget.huntLabel.TextTransparency = flash * 0.3
	end
end

function DamageFeedback.destroy(widget: Widget)
	widget.gui:Destroy()
end

return DamageFeedback
