--!strict
-- Coeur de la menace, pur.
--
-- Un compteur borne a [0, 100], une table de paliers, et des regles de gain
-- et de decroissance. Aucun Player, aucun Heartbeat, aucun remote : le temps
-- est passe en argument, ce qui rend testable une partie de vingt minutes en
-- quelques appels.
--
-- Toutes les valeurs viennent de Config.Threat. Ce module ne fixe aucun
-- nombre, il applique ceux qu'on lui donne.

local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)

type ThreatBand = Types.ThreatBand
type ThreatChange = Types.ThreatChange
type ThreatMeter = Types.ThreatMeter

local Threat = {}

local function isUsableNumber(value: any): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

-- Paliers evalues du plus haut au plus bas : le premier dont la borne basse
-- est atteinte gagne. La table de config est deja ordonnee, mais on ne s'y
-- fie pas — une insertion mal placee produirait un palier fantome.
function Threat.bandFor(value: number): ThreatBand
	local best: ThreatBand = "SAFE"
	local bestFrom = -math.huge

	for _, band in Config.Threat.bands do
		if value >= band.from and band.from >= bestFrom then
			best = band.name :: ThreatBand
			bestFrom = band.from
		end
	end

	return best
end

function Threat.new(initial: number?, now: number?): ThreatMeter
	local start = if isUsableNumber(initial) then initial :: number else Config.Threat.min
	return {
		value = math.clamp(start, Config.Threat.min, Config.Threat.max),
		lastEventAt = now or 0,
		huntTriggeredAt = nil,
	}
end

local function applyDelta(meter: ThreatMeter, delta: number, reason: string): ThreatChange
	local previous = meter.value
	local previousBand = Threat.bandFor(previous)

	meter.value = math.clamp(previous + delta, Config.Threat.min, Config.Threat.max)

	return {
		value = meter.value,
		previous = previous,
		band = Threat.bandFor(meter.value),
		previousBand = previousBand,
		reason = reason,
	}
end

-- Ajout ponctuel. Marque l'instant comme actif, ce qui repousse d'autant le
-- moment ou la decroissance reprendra.
function Threat.add(meter: ThreatMeter, amount: number, reason: string, now: number): ThreatChange
	-- Seule une valeur inexploitable est ecartee. Un montant nul, lui, est
	-- un appel parfaitement forme : une source configuree a 0 signale quand
	-- meme qu'il se passe quelque chose sur la carte, et doit donc repousser
	-- la decroissance comme n'importe quel autre evenement.
	if not isUsableNumber(amount) then
		return applyDelta(meter, 0, reason)
	end

	-- Un retrait explicite reste un evenement : il est voulu par un service,
	-- pas subi. Seul le gain passif ne compte pas comme activite.
	meter.lastEventAt = now

	return applyDelta(meter, amount, reason)
end

-- Reglage direct. Ne marque pas d'activite : forcer une valeur est un acte
-- d'administration ou de scenario, pas du bruit sur la carte.
function Threat.set(meter: ThreatMeter, value: number, reason: string): ThreatChange
	if not isUsableNumber(value) then
		return applyDelta(meter, 0, reason)
	end
	return applyDelta(meter, value - meter.value, reason)
end

-- Un pas de temps : gain passif toujours, decroissance seulement au calme.
--
-- Les deux s'additionnent plutot que de s'exclure. C'est ce qui permet de
-- lire le bilan net directement dans la config (passive - decay) au lieu de
-- devoir suivre une branche de code pour le deduire.
function Threat.step(meter: ThreatMeter, dt: number, now: number): ThreatChange
	if not isUsableNumber(dt) or dt <= 0 then
		return applyDelta(meter, 0, "tick")
	end

	local quiet = (now - meter.lastEventAt) >= Config.Threat.quietDelay
	local delta = Config.Threat.passivePerSecond * dt
	if quiet then
		delta -= Config.Threat.decayPerSecond * dt
	end

	return applyDelta(meter, delta, if quiet then "decay" else "time")
end

-- La traque se declenche a l'instant precis ou l'on entre dans HUNT, une
-- seule fois, et pas avant la fin du temps de recharge.
function Threat.shouldTriggerHunt(meter: ThreatMeter, change: ThreatChange, now: number): boolean
	if change.band ~= "HUNT" or change.previousBand == "HUNT" then
		return false
	end

	local last = meter.huntTriggeredAt
	if last and (now - last) < Config.Threat.hunt.cooldown then
		return false
	end

	return true
end

function Threat.markHuntTriggered(meter: ThreatMeter, now: number)
	meter.huntTriggeredAt = now
end

function Threat.isHuntActive(meter: ThreatMeter, now: number): boolean
	local last = meter.huntTriggeredAt
	return last ~= nil and (now - last) < Config.Threat.hunt.duration
end

return Threat
