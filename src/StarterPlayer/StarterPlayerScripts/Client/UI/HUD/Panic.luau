--!strict
-- Panique generale du HUD.
--
-- Le bloc de vitaux tremblait et se brouillait quand le rythme cardiaque
-- montait ; le reste de l'interface restait impeccable. Un HUD dont un seul
-- coin panique pendant que les autres panneaux tiennent parfaitement raconte
-- que le moniteur medical est mal fixe, pas que le porteur est en train de
-- perdre pied.
--
-- Ce module propage la MEME degradation a tout l'equipement : les panneaux
-- tremblent, les libelles decrochent. La source est unique — le rythme
-- cardiaque calcule par le bloc de vitaux — pour que tout batte ensemble.
--
-- DEUX REGLES QUI ONT DICTE L'IMPLEMENTATION
--
-- 1. Rien ne bouge tant qu'on va bien. En dessous du seuil, les panneaux
--    sont exactement a leur place : la panique doit etre un EVENEMENT, pas
--    une texture permanente qu'on cesse de voir au bout de trois minutes.
--
-- 2. Le tremblement se retire par TIRAGES, pas par image. Un decalage
--    reechantillonne soixante fois par seconde n'est pas un tremblement,
--    c'est du bruit blanc : illisible, et fatigant en dix secondes. On tire
--    une nouvelle position quelques fois par seconde, et on s'y tient.

local Theme = require(script.Parent.Theme)

local Panic = {}

type FrameEntry = {
	frame: GuiObject,
	base: UDim2,
	offsetX: number,
	offsetY: number,
}

-- Un libelle qui peut decrocher.
--
-- DEUX MODES, parce que le HUD contient deux natures de texte :
--
--   fixe   le texte ne change jamais (« MENACE », « APPUYER »). On garde
--          la reference une fois pour toutes.
--   vivant le widget le REECRIT en permanence — la transmission du
--          commanditaire s'ecrit lettre par lettre, le journal defile. Une
--          reference figee y afficherait un message perime.
--
-- En mode vivant, on relit le texte au moment de brouiller et on ne restaure
-- QUE si personne n'a ecrit entre-temps : `scrambled` sert de temoin.
type LabelEntry = {
	label: TextLabel,
	live: boolean,
	text: string,
	scrambled: string?,
	restoreAt: number,
}

export type Widget = {
	frames: { FrameEntry },
	labels: { LabelEntry },
	clock: number,
	rerollAt: number,
	glitchAt: number,
	level: number,
	settled: boolean,
}

function Panic.create(): Widget
	return {
		frames = {},
		labels = {},
		clock = 0,
		rerollAt = 0,
		glitchAt = 0,
		level = 0,
		settled = true,
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
		offsetX = 0,
		offsetY = 0,
	})
end

-- Enregistre un libelle dont le texte peut decrocher.
--
-- Reserve aux libelles FIXES — titres, unites, etiquettes. Brouiller une
-- valeur chiffree ferait douter le joueur du chiffre lui-meme, ce qui est
-- une tout autre promesse que « l'appareil fatigue ».
function Panic.watchLabel(widget: Widget, label: TextLabel?)
	if not label then
		return
	end
	table.insert(widget.labels, {
		label = label,
		live = false,
		text = label.Text,
		scrambled = nil,
		restoreAt = 0,
	})
end

-- Libelle REECRIT par son widget : transmission du commanditaire, lignes du
-- journal d'evenements. On ne fige aucune reference, on relit a chaque
-- brouillage.
--
-- C'est ce qui manquait : le pop-up d'information est precisement l'endroit
-- ou un decrochage se lit le mieux — c'est une liaison radio — et c'etait le
-- seul texte que la panique ne pouvait pas toucher.
function Panic.watchLive(widget: Widget, label: TextLabel?)
	if not label then
		return
	end
	table.insert(widget.labels, {
		label = label,
		live = true,
		text = "",
		scrambled = nil,
		restoreAt = 0,
	})
end

-- Le texte fixe d'un libelle surveille a change (traduction, contrat
-- different) : on reprend la nouvelle reference.
function Panic.refresh(widget: Widget, label: TextLabel, text: string)
	for _, entry in widget.labels do
		if entry.label == label then
			entry.text = text
			entry.restoreAt = 0
			entry.label.Text = text
			return
		end
	end
end

-- Remplace `count` caracteres au hasard par des glyphes parasites.
--
-- Un seul caractere pendant neuf centiemes de seconde ne se voyait pas. On
-- en abime plusieurs, plus longtemps : un decrochage doit se REMARQUER,
-- sinon autant ne rien faire.
local function scramble(text: string, count: number): string
	if #text == 0 then
		return text
	end

	local out = text
	for _ = 1, math.max(1, count) do
		local at = math.random(1, #out)
		local pick = math.random(1, #Theme.glitchGlyphs)
		local glyph = string.sub(Theme.glitchGlyphs, pick, pick)
		out = string.sub(out, 1, at - 1) .. glyph .. string.sub(out, at + 1)
	end
	return out
end

-- `level` est le rythme cardiaque normalise, 0 au repos, 1 a l'affolement.
function Panic.step(widget: Widget, dt: number, level: number)
	widget.clock += dt
	widget.level = math.clamp(level, 0, 1)

	local settings = Theme.panic
	local intensity = 0
	if widget.level > settings.startsAt then
		intensity = (widget.level - settings.startsAt) / (1 - settings.startsAt)
	end

	-- Retour au calme : on repose tout EXACTEMENT une fois, puis on ne
	-- touche plus a rien. Continuer a ecrire les positions a chaque image
	-- pendant qu'il ne se passe rien coute pour rien.
	if intensity <= 0 then
		if not widget.settled then
			widget.settled = true
			for _, entry in widget.frames do
				entry.frame.Position = entry.base
				entry.offsetX, entry.offsetY = 0, 0
			end
			for _, entry in widget.labels do
				-- On ne repose QUE ce qu'on a soi-meme brouille. Ecraser un
				-- libelle vivant avec une reference figee y afficherait un
				-- message deja perime.
				if entry.scrambled and entry.label.Text == entry.scrambled then
					entry.label.Text = entry.text
				end
				entry.scrambled = nil
				entry.restoreAt = 0
			end
		end
		return
	end

	widget.settled = false

	-- --- tremblement ------------------------------------------------------
	if widget.clock >= widget.rerollAt then
		local rate = settings.rerollBase + settings.rerollGain * intensity
		widget.rerollAt = widget.clock + 1 / rate

		local amplitude = settings.maxOffset * intensity
		for _, entry in widget.frames do
			entry.offsetX = (math.random() - 0.5) * 2 * amplitude
			entry.offsetY = (math.random() - 0.5) * 2 * amplitude
		end
	end

	for _, entry in widget.frames do
		entry.frame.Position = UDim2.new(
			entry.base.X.Scale,
			entry.base.X.Offset + entry.offsetX,
			entry.base.Y.Scale,
			entry.base.Y.Offset + entry.offsetY
		)
	end

	-- --- decrochage des libelles ------------------------------------------
	for _, entry in widget.labels do
		if entry.restoreAt > 0 and widget.clock >= entry.restoreAt then
			-- COMPARAISON AVANT ECRITURE. Si le widget a reecrit son libelle
			-- pendant le decrochage, sa version est plus recente que la
			-- notre : on ne la touche pas.
			if entry.scrambled and entry.label.Text == entry.scrambled then
				entry.label.Text = entry.text
			end
			entry.scrambled = nil
			entry.restoreAt = 0
		end
	end

	if widget.clock >= widget.glitchAt then
		local rate = settings.glitchBase + settings.glitchGain * intensity
		widget.glitchAt = widget.clock + 1 / rate

		if #widget.labels > 0 then
			local entry = widget.labels[math.random(#widget.labels)]

			-- Un libelle vivant se RELIT : sa reference figee serait un
			-- message perime. Un libelle fixe garde la sienne.
			local source = if entry.live then entry.label.Text else entry.text

			if #source > 0 then
				local span = settings.glitchCharsMax - settings.glitchCharsMin
				local count = math.floor(settings.glitchCharsMin + span * intensity + 0.5)

				entry.text = source
				entry.scrambled = scramble(source, count)
				entry.label.Text = entry.scrambled :: string
				entry.restoreAt = widget.clock + settings.glitchHold
			end
		end
	end
end

function Panic.clear(widget: Widget)
	Panic.step(widget, 0, 0)
	widget.settled = false
	Panic.step(widget, 0, 0)
end

return Panic
