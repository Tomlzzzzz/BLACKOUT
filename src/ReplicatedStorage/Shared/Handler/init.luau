--!strict
-- Ordonnanceur des transmissions du commanditaire.
--
-- Module PUR, comme Inventory ou Threat : pas de Player, pas d'Instance, le
-- temps est toujours passe en argument. Tout ce qui decide QUOI dire et QUAND
-- se taire vit ici et se teste sans lancer de partie ; HandlerService ne fait
-- que brancher les vrais evenements dessus et envoyer le resultat au client.
--
-- Quatre regles portent tout le ressenti :
--
--   INTERRUPTION  une transmission plus prioritaire coupe la precedente.
--   ABANDON       une moins prioritaire arrivee trop tot est jetee, jamais
--                 mise en file : un message qui arrive en retard sur son
--                 evenement ment au joueur.
--   MONOTONIE     les paliers (cargaison, menace) ne se declenchent qu'en
--                 montant, une seule fois par raid. Faire l'aller-retour
--                 autour d'un seuil ne doit pas declencher un bavardage.
--   SILENCE       pendant THE HUNT le bureau ne parle plus. C'est le
--                 retournement du jeu et il est applique ici, pas au cas par
--                 cas dans chaque appelant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)

local HandlerConfig = Config.Handler

local Handler = {}

type Transmission = Types.Transmission

export type State = {
	-- Horodatage et priorite de la derniere transmission emise.
	lastAt: number,
	lastPriority: number,

	-- Cles `once` deja consommees.
	seen: { [string]: boolean },

	-- Sacs de variantes : tirage sans remise, la voix se repete moins.
	bags: { [string]: { number } },

	-- Paliers franchis (monotones).
	cargoTier: number,
	bandIndex: number,
	windowWarned: { [number]: boolean },

	-- Suivi d'inactivite et de remplissage.
	lastLootAt: number,
	lastIdleAt: number,
	lastAmbientAt: number,
	lowHealthAt: number,

	-- Le bureau s'est tu (THE HUNT).
	silenced: boolean,
}

-- Ordre des paliers de menace. Sert a n'annoncer qu'une montee : redescendre
-- de DANGER a ALERT ne doit rien dire, sinon la voix commente le bruit.
local BAND_ORDER: { [string]: number } = {
	SAFE = 1,
	ALERT = 2,
	DANGER = 3,
	SEVERE = 4,
	CRITICAL = 5,
	HUNT = 6,
}

-- Seules cles autorisees a percer le silence de THE HUNT. `huntEnd` doit
-- passer : c'est lui qui annonce que le bureau est revenu, sans quoi le
-- silence serait definitif.
local BREAKS_SILENCE: { [string]: boolean } = {
	huntEnd = true,
}

function Handler.new(now: number): State
	return {
		lastAt = -math.huge,
		lastPriority = 0,
		seen = {},
		bags = {},
		cargoTier = 0,
		bandIndex = BAND_ORDER.SAFE,
		windowWarned = {},
		lastLootAt = now,
		lastIdleAt = now,
		lastAmbientAt = now,
		lowHealthAt = -math.huge,
		silenced = false,
	}
end

-- ----------------------------------------------------------- Formatage ---

-- 12400 -> "12 400". Espace fine insecable : le nombre ne se coupe pas en
-- fin de ligne et reste lisible en RobotoMono.
function Handler.formatNumber(value: number): string
	local text = tostring(math.floor(math.abs(value)))
	local out = ""
	local count = 0

	for index = #text, 1, -1 do
		out = text:sub(index, index) .. out
		count += 1
		if count % 3 == 0 and index > 1 then
			out = "\u{202F}" .. out
		end
	end

	return if value < 0 then "-" .. out else out
end

-- Tirage sans remise dans les variantes d'une cle.
local function pickVariant(state: State, key: string, count: number, rng: (number) -> number): number
	if count <= 1 then
		return 1
	end

	local bag = state.bags[key]
	if not bag or #bag == 0 then
		bag = {}
		for index = 1, count do
			table.insert(bag, index)
		end
		state.bags[key] = bag
	end

	local slot = rng(#bag)
	local choice = bag[slot]
	table.remove(bag, slot)
	return choice
end

-- ------------------------------------------------------------- Emission --

-- Coeur du module. Retourne la transmission a envoyer, ou nil si elle doit
-- etre abandonnee. Aucun effet de bord hors `state`.
function Handler.submit(
	state: State,
	key: string,
	now: number,
	fields: { [string]: any }?,
	rng: ((number) -> number)?
): Transmission?
	local line = HandlerConfig.lines[key]
	if not line then
		return nil
	end

	if state.silenced and not BREAKS_SILENCE[key] then
		return nil
	end

	-- Le nombre de variantes vient du fichier de langue de reference, pas de
	-- la config : enrichir la voix se fait en ajoutant une traduction.
	local variants = Locale.variants(`handler.{key}`)
	if variants == 0 then
		return nil
	end
	local variant = pickVariant(state, key, variants, rng or math.random)

	if line.once and state.seen[key] then
		return nil
	end

	local priority = HandlerConfig.priority[line.priority] or HandlerConfig.priority.routine

	-- Fenetre de silence depuis la derniere emission. Une transmission
	-- strictement plus prioritaire la traverse ; les autres sont jetees.
	local gap = if state.lastPriority >= HandlerConfig.priority.critical
		then HandlerConfig.criticalGap
		else HandlerConfig.minGap

	if now - state.lastAt < gap and priority <= state.lastPriority then
		-- Abandonnee : le sac a deja perdu sa variante, ce qui est voulu.
		-- Rejouer la meme phrase a la premiere occasion suivante donnerait
		-- l'impression que la voix bafouille.
		return nil
	end

	if line.once then
		state.seen[key] = true
	end

	state.lastAt = now
	state.lastPriority = priority

	-- `hunt` s'annonce, puis coupe la voix. L'ordre compte : la transmission
	-- part, ensuite le silence tombe.
	if key == "hunt" then
		state.silenced = true
	elseif key == "huntEnd" then
		state.silenced = false
	end

	-- `company` est toujours disponible : c'est la signature de la voix,
	-- aucun appelant ne devrait avoir a la fournir.
	local payload: { [string]: any } = { company = HandlerConfig.company }
	if fields then
		for name, value in fields do
			payload[name] = if type(value) == "number" then Handler.formatNumber(value) else value
		end
	end

	return {
		key = key,
		-- Societe ET bureau. « SUPERVISION » seul pourrait etre n'importe qui ;
		-- c'est le nom de l'employeur en tete de chaque message qui rappelle
		-- pour qui le joueur travaille. Nom propre : jamais traduit.
		-- Separateur ASCII. Le point median U+00B7 s'affichait en carre :
		-- RobotoCondensed ne le porte pas, et un glyphe manquant dans le nom
		-- de l'employeur est la derniere chose qu'on veut voir.
		sender = `{HandlerConfig.company} // {HandlerConfig.desk}`,
		textKey = `handler.{key}.{variant}`,
		fields = payload,
		tone = line.tone,
		priority = priority,
		holdTime = HandlerConfig.holdTime,
	}
end

-- ------------------------------------------------------------- Paliers ---

-- Cargaison. Ne parle qu'en montant et une seule fois par palier.
function Handler.cargoChanged(state: State, value: number, now: number): Transmission?
	local reached = 0
	for index, tier in HandlerConfig.cargoTiers do
		if value >= tier.at then
			reached = index
		end
	end

	if reached <= state.cargoTier then
		return nil
	end

	local tier = HandlerConfig.cargoTiers[reached]
	state.cargoTier = reached
	return Handler.submit(state, tier.key, now, { cargo = value })
end

-- Menace. Meme regle : uniquement les montees.
function Handler.bandChanged(state: State, band: string, now: number): Transmission?
	local index = BAND_ORDER[band]
	if not index or index <= state.bandIndex then
		-- On NE rabaisse PAS le palier atteint. La menace peut redescendre
		-- pendant les accalmies ; si le compteur suivait, chaque oscillation
		-- autour d'un seuil relancerait la meme phrase, et la voix
		-- commenterait le bruit au lieu de commenter le jeu.
		return nil
	end

	state.bandIndex = index

	if band == "HUNT" then
		return Handler.submit(state, "hunt", now)
	end
	return Handler.submit(state, `band{band}`, now)
end

-- Fenetre de contrat. Un avertissement par seuil franchi.
function Handler.windowTick(state: State, remaining: number, now: number): Transmission?
	if remaining <= HandlerConfig.windowFinalAt and not state.windowWarned[HandlerConfig.windowFinalAt] then
		state.windowWarned[HandlerConfig.windowFinalAt] = true
		return Handler.submit(state, "windowFinal", now, { seconds = math.floor(remaining) })
	end

	for _, threshold in HandlerConfig.windowWarnAt do
		if remaining <= threshold and not state.windowWarned[threshold] then
			state.windowWarned[threshold] = true
			return Handler.submit(state, "windowWarning", now, { minutes = math.floor(threshold / 60) })
		end
	end

	return nil
end

-- Vie. Une remarque, puis plus rien avant d'etre remonte au-dessus du seuil :
-- sinon chaque coup encaisse en dessous de 30 % relancerait la phrase.
function Handler.healthChanged(state: State, fraction: number, now: number): Transmission?
	if fraction > HandlerConfig.lowHealthAt then
		state.lowHealthAt = -math.huge
		return nil
	end

	if state.lowHealthAt > -math.huge then
		return nil
	end

	state.lowHealthAt = now
	return Handler.submit(state, "lowHealth", now)
end

-- ------------------------------------------------------------ Cadence ----

-- Appele regulierement. Produit les transmissions qui ne repondent a aucun
-- evenement : le rappel de rendement et le bruit administratif.
function Handler.tick(state: State, now: number, rng: ((number) -> number)?): Transmission?
	local idleFor = now - state.lastLootAt
	if idleFor >= HandlerConfig.idleAfter and now - state.lastIdleAt >= HandlerConfig.idleRepeat then
		state.lastIdleAt = now
		local sent = Handler.submit(state, "idle", now, { seconds = math.floor(idleFor) }, rng)
		if sent then
			return sent
		end
	end

	-- PLUS DE REMPLISSAGE.
	--
	-- Les transmissions « d'ambiance » partaient sur minuterie, sans rapport
	-- avec quoi que ce soit : « Archivage en cours » pendant qu'un crawler
	-- chargeait. Le joueur apprend vite qu'un message peut ne rien vouloir
	-- dire, et il cesse alors de tous les lire — y compris ceux qui comptent.
	--
	-- Il ne reste donc que des messages ADOSSES A UN FAIT : un palier franchi,
	-- un equipier tombe, une sortie ouverte, une fenetre qui se ferme, ou une
	-- absence de production mesuree. Le rappel d'inactivite ci-dessus en fait
	-- partie : ne rien avoir ramasse depuis cent secondes est un etat reel.
	return nil
end

-- --------------------------------------------------------- Production ----

-- Enregistre un ramassage. Remet a zero le compteur d'inactivite : c'est ce
-- qui fait que le rappel de rendement ne vise que les joueurs qui ne
-- produisent vraiment rien.
--
-- Le SUIVI D'OBJECTIF ne passe plus par ici : MissionService tient les
-- contrats. Deux compteurs de progression en parallele finiraient
-- forcement par diverger.
function Handler.recordLoot(state: State, now: number): Transmission?
	state.lastLootAt = now
	state.lastIdleAt = now
	return Handler.submit(state, "firstLoot", now)
end

return Handler
