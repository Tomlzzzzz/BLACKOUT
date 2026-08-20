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
function Stamina.step(state: StaminaState, dt: number, speed: number, now: number): boolean
	if not isUsable(dt) or dt <= 0 then
		return false
	end

	local settings = cfg()
	local before = state.value
	local effort = isUsable(speed) and speed >= settings.moveThreshold

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
