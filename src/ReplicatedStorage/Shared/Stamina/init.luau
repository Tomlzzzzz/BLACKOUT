--!strict
-- Endurance, pure.
--
-- Meme patron que le reste : le temps et l'effort sont des arguments, pas
-- des mesures prises ici. Le service fournit la vitesse reelle mesuree
-- serveur, ce module dit ce qu'il en resulte.

local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)

type StaminaState = Types.StaminaState

local Stamina = {}

local function cfg()
	return Config.Player.stamina
end

local function isUsable(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Stamina.new(now: number?): StaminaState
	return {
		value = cfg().max,
		lastEffortAt = -math.huge,
		exhausted = false,
	}
end

-- Un pas de temps. `speed` est la vitesse mesuree du personnage.
--
-- Retourne true si la valeur a change de facon perceptible, pour que le
-- service n'inonde pas le reseau d'une mise a jour par tick alors que rien
-- ne bouge.
-- `sprinting` est l'arbitrage SERVEUR de la course. Quand il est fourni,
-- c'est lui qui decide de l'effort et la vitesse ne sert plus qu'a verifier
-- que le joueur avance reellement.
--
-- POURQUOI CE PARAMETRE EXISTE
--
-- L'effort se deduisait de la seule VITESSE MESUREE, comparee a un seuil
-- place entre la marche et la course. Deux decisions differentes — courir
-- (intention, arbitree serveur) et consommer (vitesse observee) — pouvaient
-- donc etre en desaccord : personnage qui n'atteint pas sa vitesse cible,
-- velocite repliquee en retard sur un personnage possede par le client,
-- montee, obstacle. Symptome constate en jeu : la jauge ne bougeait pas
-- pendant la course et chutait au relachement.
--
-- Une seule source decide maintenant : si le serveur a accorde la course et
-- que le joueur avance, ca coute. L'ancien comportement reste disponible en
-- omettant l'argument — c'est ce que font les tests du modele pur.
function Stamina.step(
	state: StaminaState,
	dt: number,
	speed: number,
	now: number,
	sprinting: boolean?
): boolean
	if not isUsable(dt) or dt <= 0 then
		return false
	end

	local settings = cfg()
	local before = state.value

	local effort
	if sprinting ~= nil then
		effort = sprinting and isUsable(speed) and speed > settings.movingAt
	else
		effort = isUsable(speed) and speed >= settings.moveThreshold
	end

	if effort then
		state.lastEffortAt = now
		state.value -= settings.drainPerSecond * dt
	elseif (now - state.lastEffortAt) >= settings.regenDelay then
		state.value += settings.regenPerSecond * dt
	end

	state.value = math.clamp(state.value, 0, settings.max)

	-- Hysteresis d'epuisement : on tombe epuise sous le seuil, on n'en sort
	-- qu'a un quart de la jauge. Sans cet ecart, un joueur a la limite
	-- alternerait entre les deux vitesses plusieurs fois par seconde.
	if state.exhausted then
		if state.value >= settings.max * 0.25 then
			state.exhausted = false
		end
	elseif state.value <= settings.exhaustedBelow then
		state.exhausted = true
	end

	return math.abs(state.value - before) > 0.01
end

function Stamina.fraction(state: StaminaState): number
	return math.clamp(state.value / cfg().max, 0, 1)
end

return Stamina
