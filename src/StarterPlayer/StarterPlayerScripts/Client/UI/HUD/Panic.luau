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

type LabelEntry = {
	label: TextLabel,
	text: string,
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
	table.insert(widget.labels, { label = label, text = label.Text, restoreAt = 0 })
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

local function scramble(text: string): string
	if #text == 0 then
		return text
	end
	local at = math.random(1, #text)
	local pick = math.random(1, #Theme.glitchGlyphs)
	local glyph = string.sub(Theme.glitchGlyphs, pick, pick)
	return string.sub(text, 1, at - 1) .. glyph .. string.sub(text, at + 1)
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
				entry.label.Text = entry.text
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
			entry.label.Text = entry.text
			entry.restoreAt = 0
		end
	end

	if widget.clock >= widget.glitchAt then
		local rate = settings.glitchBase + settings.glitchGain * intensity
		widget.glitchAt = widget.clock + 1 / rate

		if #widget.labels > 0 then
			local entry = widget.labels[math.random(#widget.labels)]
			entry.label.Text = scramble(entry.text)
			entry.restoreAt = widget.clock + settings.glitchHold
		end
	end
end

function Panic.clear(widget: Widget)
	Panic.step(widget, 0, 0)
	widget.settled = false
	Panic.step(widget, 0, 0)
end

return Panic
