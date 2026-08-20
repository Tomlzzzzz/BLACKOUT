--!strict
-- Degradation generale du HUD.
--
-- LE BLOC DE VITAUX EST LA REFERENCE. Ce module ne fait pas « quelque chose
-- de ressemblant » : il applique EXACTEMENT le meme traitement au reste de
-- l'equipement — memes reglages (`Theme.monitor`), meme brouillage
-- (`Components.scramble`), meme duree, meme couleur d'alerte, meme
-- tremblement d'un pixel.
--
-- Un HUD dont un seul coin se degrade pendant que les autres panneaux
-- tiennent parfaitement raconte que le moniteur medical est mal fixe. Deux
-- coins qui se degradent DIFFEREMMENT racontent deux appareils. Il n'y en a
-- qu'un, sangle sur un porteur qui va mal.
--
-- LA SOURCE EST UNIQUE
--
-- La degradation n'est pas recalculee ici : elle est LUE sur le bloc de
-- vitaux (`PlayerStatusWidget.getDecay`). Deux horloges deriveraient, et le
-- HUD tremblerait a contretemps de son propre cardiogramme.

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local Panic = {}

type FrameEntry = {
	frame: GuiObject,
	base: UDim2,
	baseTransparency: number,
}

-- Un libelle qui peut decrocher.
--
-- DEUX MODES, parce que le HUD contient deux natures de texte :
--
--   fixe   le texte ne change jamais (« MENACE », « APPUYER »). La
--          reference est prise une fois pour toutes.
--   vivant le widget le REECRIT en permanence — la transmission du
--          commanditaire s'ecrit lettre par lettre, le journal defile. Une
--          reference figee y afficherait un message perime.
--
-- En mode vivant on relit au moment de brouiller, et on ne restaure QUE si
-- personne n'a ecrit entre-temps : `scrambled` sert de temoin.
type LabelEntry = {
	label: TextLabel,
	live: boolean,
	text: string,
	color: Color3,
	scrambled: string?,
	restoreAt: number,
	-- Double d'impression, cree a la premiere degradation seulement.
	ghost: TextLabel?,
}

export type Widget = {
	frames: { FrameEntry },
	labels: { LabelEntry },
	clock: number,
	glitchIn: number,
	active: boolean,
	-- Coupure d'alimentation en cours : dure quelques centiemes.
	flickerUntil: number,
	flickerIn: number,
	flickered: FrameEntry?,
}

-- Duree d'un decrochage. Identique a celle du bloc de vitaux.
local HOLD = 0.12

function Panic.create(): Widget
	return {
		frames = {},
		labels = {},
		clock = 0,
		glitchIn = 0,
		active = false,
		flickerUntil = 0,
		flickerIn = 0,
		flickered = nil,
	}
end

-- Enregistre un panneau. Sa position d'origine est relevee MAINTENANT, une
-- seule fois : la relire plus tard la prendrait deja decalee par le
-- tremblement, et le panneau deriverait a chaque secousse.
function Panic.watchFrame(widget: Widget, frame: GuiObject?)
	if not frame then
		return
	end
	table.insert(widget.frames, {
		frame = frame,
		base = frame.Position,
		baseTransparency = frame.BackgroundTransparency,
	})
end

function Panic.watchLabel(widget: Widget, label: TextLabel?)
	if not label then
		return
	end
	table.insert(widget.labels, {
		label = label,
		live = false,
		text = label.Text,
		color = label.TextColor3,
		scrambled = nil,
		restoreAt = 0,
	})
end

-- Libelle REECRIT par son widget : transmission du commanditaire, lignes du
-- journal d'evenements.
--
-- C'est le pop-up d'information — precisement l'endroit ou un decrochage se
-- lit le mieux, puisque c'est une liaison radio — et c'etait le seul texte
-- que la degradation ne pouvait pas toucher.
function Panic.watchLive(widget: Widget, label: TextLabel?)
	if not label then
		return
	end
	table.insert(widget.labels, {
		label = label,
		live = true,
		text = "",
		color = label.TextColor3,
		scrambled = nil,
		restoreAt = 0,
	})
end

-- Repose un libelle, mais SEULEMENT si c'est bien notre brouillage qui est
-- encore a l'ecran. Si le widget a reecrit entre-temps, sa version est plus
-- recente que la notre.
local function restore(entry: LabelEntry)
	if entry.scrambled and entry.label.Text == entry.scrambled then
		entry.label.Text = entry.text
		entry.label.TextColor3 = entry.color
	end
	entry.scrambled = nil
	entry.restoreAt = 0

	local ghost = entry.ghost
	if ghost then
		ghost.Visible = false
	end
end

-- DOUBLE D'IMPRESSION.
--
-- Un exemplaire du libelle, decale de deux pixels, en rouge, DERRIERE le
-- vrai. Les canaux d'une mauvaise impression ne se superposent pas : ce
-- dedoublement transforme un texte simplement brouille en texte mal
-- transmis, ce qui n'est pas la meme histoire.
--
-- Cree a la PREMIERE degradation seulement, puis reutilise : la plupart des
-- parties n'en verront jamais un seul.
local function ghostFor(entry: LabelEntry): TextLabel?
	if entry.ghost then
		return entry.ghost
	end

	local parent = entry.label.Parent
	if not parent then
		return nil
	end

	local clone = entry.label:Clone()
	clone.Name = entry.label.Name .. "_Ghost"
	clone.ZIndex = math.max(1, entry.label.ZIndex - 1)
	clone.TextColor3 = Theme.color.danger
	clone.TextTransparency = 0.55
	clone.Visible = false
	clone.Parent = parent

	entry.ghost = clone
	return clone
end

-- `decay` est la degradation lue sur le bloc de vitaux : 0 quand tout va
-- bien, 1 a l'agonie.
function Panic.step(widget: Widget, dt: number, decay: number)
	widget.clock += dt
	local level = math.clamp(decay, 0, 1)

	-- Les libelles deja brouilles reviennent a leur heure, panique ou pas.
	for _, entry in widget.labels do
		if entry.restoreAt > 0 and widget.clock >= entry.restoreAt then
			restore(entry)
		end
	end

	if level <= 0 then
		-- Retour au calme : on repose tout EXACTEMENT une fois, puis on ne
		-- touche plus a rien. Reecrire les positions a chaque image pendant
		-- qu'il ne se passe rien coute pour rien.
		if widget.active then
			widget.active = false
			for _, entry in widget.frames do
				entry.frame.Position = entry.base
				entry.frame.BackgroundTransparency = entry.baseTransparency
			end
			widget.flickered = nil
			for _, entry in widget.labels do
				restore(entry)
			end
		end
		return
	end

	widget.active = true

	-- TREMBLEMENT : un pixel, redecide a chaque image. Exactement ce que fait
	-- le bloc de vitaux — pas une amplitude proportionnelle, pas un tirage
	-- espace. L'appareil vibre, il ne se deplace pas.
	for _, entry in widget.frames do
		entry.frame.Position = entry.base + UDim2.fromOffset(math.random(-1, 1), math.random(-1, 1))
	end

	-- COUPURE D'ALIMENTATION.
	--
	-- Un panneau au hasard s'efface quelques centiemes de seconde. C'est le
	-- meme evenement que le clignotement du bloc de vitaux sur batterie
	-- faible, applique a l'equipement entier : l'appareil ne se contente pas
	-- de trembler, il PERD LE CONTACT par moments.
	local flickered = widget.flickered
	if flickered and widget.clock >= widget.flickerUntil then
		flickered.frame.BackgroundTransparency = flickered.baseTransparency
		widget.flickered = nil
	end

	widget.flickerIn -= dt
	if widget.flickerIn <= 0 and #widget.frames > 0 and not widget.flickered then
		widget.flickerIn = (1.4 + math.random() * 2.6) / math.max(0.25, level)
		local entry = widget.frames[math.random(1, #widget.frames)]
		entry.frame.BackgroundTransparency = 1
		widget.flickerUntil = widget.clock + 0.05 + math.random() * 0.04
		widget.flickered = entry
	end

	-- DECROCHAGE : meme cadence que le bloc de vitaux, bornee de la meme
	-- facon pour qu'une degradation naissante ne fige pas l'intervalle.
	widget.glitchIn -= dt
	if widget.glitchIn > 0 or #widget.labels == 0 then
		return
	end
	widget.glitchIn = 1 / (Theme.monitor.glitchPerSecond * math.max(0.2, level))

	local entry = widget.labels[math.random(1, #widget.labels)]

	-- Un decrochage deja en cours sur ce libelle : on repose avant de
	-- rebrouiller, sinon la reference deviendrait le texte deja abime.
	if entry.scrambled then
		restore(entry)
	end

	-- Un libelle vivant se RELIT ; un libelle fixe garde sa reference.
	local source = if entry.live then entry.label.Text else entry.text
	if #source == 0 then
		return
	end

	entry.text = source
	if entry.live then
		entry.color = entry.label.TextColor3
	end

	entry.scrambled = Components.scramble(source)
	entry.label.Text = entry.scrambled :: string
	entry.label.TextColor3 = Theme.color.danger
	entry.restoreAt = widget.clock + HOLD

	-- Le double porte le texte PROPRE : c'est l'ecart entre les deux qui
	-- se lit comme une mauvaise transmission. Deux textes brouilles
	-- differemment ne donneraient qu'une bouillie.
	local ghost = ghostFor(entry)
	if ghost then
		ghost.Text = source
		ghost.Position = entry.label.Position + UDim2.fromOffset(2, 1)
		ghost.Visible = true
	end
end

return Panic
