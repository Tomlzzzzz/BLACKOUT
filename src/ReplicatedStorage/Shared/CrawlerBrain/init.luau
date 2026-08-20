--!strict
-- Cerveau du Crawler, pur.
--
-- Machine a cinq etats : Idle, Patrol, Investigate, Chase, Attack.
-- Aucun Instance, aucun Humanoid, aucun PathfindingService : on lui donne
-- un instantane de perception, il rend une decision. EnemyService se charge
-- de mesurer le monde et d'executer.
--
-- C'est ce decouplage qui permet de tester six crawlers face a six joueurs
-- sans lancer six clients Studio.
--
-- Cycle nominal :
--   Idle --(repos ecoule)--> Patrol --(arrive)--> Idle
--   Idle/Patrol/Investigate --(cible vue)--> Chase
--   Chase --(a portee)--> Attack --(cible s'eloigne)--> Chase
--   Chase/Attack --(cible perdue)--> Investigate --(fouille finie)--> Patrol

local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)

type CrawlerBrainState = Types.CrawlerBrainState
type CrawlerDecision = Types.CrawlerDecision
type CrawlerPerception = Types.CrawlerPerception
type CrawlerState = Types.CrawlerState
type TargetCandidate = Types.TargetCandidate

local CrawlerBrain = {}

local function cfg()
	return Config.Enemies.crawler
end

-- Selection de cible : le joueur valide le plus proche dans la portee de
-- detection. Comparaison sur la distance au carre — la racine ne change pas
-- l'ordre et coute pour rien a chaque candidat.
function CrawlerBrain.selectTarget(
	candidates: { TargetCandidate },
	origin: Vector3,
	range: number
): TargetCandidate?
	local best: TargetCandidate? = nil
	local bestSquared = range * range

	for _, candidate in candidates do
		if not candidate.valid then
			continue
		end

		local offset = candidate.position - origin
		local squared = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
		if squared <= bestSquared then
			best = candidate
			bestSquared = squared
		end
	end

	return best
end

function CrawlerBrain.new(anchor: Vector3, now: number): CrawlerBrainState
	return {
		state = "Idle",
		stateSince = now,
		lastSeenAt = nil,
		lastKnownPosition = nil,
		destination = nil,
		anchor = anchor,
		lastAttackAt = -math.huge,
		idleUntil = now,
	}
end

-- Point de patrouille tire dans un disque autour de l'ancre. Le rng est
-- explicite pour que les tests soient reproductibles.
function CrawlerBrain.pickPatrolPoint(brain: CrawlerBrainState, rng: Random?): Vector3
	local radius = cfg().PatrolRadius
	local angle = if rng then rng:NextNumber(0, math.pi * 2) else math.random() * math.pi * 2
	local distance = if rng then rng:NextNumber(radius * 0.3, radius) else math.random() * radius

	return brain.anchor + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function transition(brain: CrawlerBrainState, state: CrawlerState, now: number)
	brain.state = state
	brain.stateSince = now
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Une cible est perdue quand elle est hors de portee d'abandon, ou qu'elle
-- n'a pas ete vue depuis assez longtemps. Les deux criteres sont distincts :
-- le premier gere la fuite en ligne droite, le second le fait de se cacher.
local function targetLost(brain: CrawlerBrainState, perception: CrawlerPerception): boolean
	if not perception.targetPosition or not perception.targetAlive then
		return true
	end

	local distance = perception.targetDistance or math.huge
	if distance > cfg().LoseTargetRange then
		return true
	end

	if not perception.targetVisible then
		local seen = brain.lastSeenAt
		if not seen or (perception.now - seen) >= cfg().LoseTargetTime then
			return true
		end
	end

	return false
end

function CrawlerBrain.think(brain: CrawlerBrainState, perception: CrawlerPerception, rng: Random?): CrawlerDecision
	local settings = cfg()
	local previousState = brain.state
	local now = perception.now

	-- Memorisation : on ne retient une position que si on voit vraiment la
	-- cible. Poursuivre une position devinee serait de la triche.
	if perception.targetVisible and perception.targetPosition and perception.targetAlive then
		brain.lastSeenAt = now
		brain.lastKnownPosition = perception.targetPosition
	end

	local acquired = perception.targetPosition ~= nil
		and perception.targetAlive
		and perception.targetVisible
		and (perception.targetDistance or math.huge) <= settings.DetectionRange

	local reason = "aucun"
	local attack = false
	local speed = settings.WalkSpeed
	local moveTo: Vector3? = nil

	-- --- Acquisition : prioritaire sur tout etat non offensif -----------
	if acquired and brain.state ~= "Chase" and brain.state ~= "Attack" then
		transition(brain, "Chase", now)
		reason = "cible acquise"
	end

	if brain.state == "Idle" then
		if now >= brain.idleUntil then
			-- La destination part avec la decision qui declenche la
			-- transition. La renvoyer au tick suivant laisserait le crawler
			-- immobile un cycle entier a chaque depart de patrouille.
			local point = CrawlerBrain.pickPatrolPoint(brain, rng)
			brain.destination = point
			transition(brain, "Patrol", now)
			reason = "repos termine"
			moveTo = point
		end
		speed = settings.WalkSpeed
	elseif brain.state == "Patrol" then
		local destination = brain.destination
		local arrived = destination ~= nil
			and horizontalDistance(perception.selfPosition, destination) <= settings.ArriveRadius
		local timedOut = (now - brain.stateSince) >= settings.PatrolTimeout

		if arrived or timedOut or not destination then
			brain.destination = nil
			brain.idleUntil = now
				+ (if rng
					then rng:NextNumber(settings.IdleTime.min, settings.IdleTime.max)
					else settings.IdleTime.min)
			transition(brain, "Idle", now)
			reason = if timedOut then "patrouille expiree" else "point atteint"
		else
			moveTo = destination
			speed = settings.WalkSpeed
			reason = "en patrouille"
		end
	elseif brain.state == "Investigate" then
		local destination = brain.lastKnownPosition
		local arrived = destination ~= nil
			and horizontalDistance(perception.selfPosition, destination) <= settings.ArriveRadius
		local timedOut = (now - brain.stateSince) >= settings.InvestigateTime

		if arrived or timedOut or not destination then
			brain.lastKnownPosition = nil
			local point = CrawlerBrain.pickPatrolPoint(brain, rng)
			brain.destination = point
			transition(brain, "Patrol", now)
			reason = if timedOut then "fouille infructueuse" else "position fouillee"
			moveTo = point
		else
			moveTo = destination
			speed = settings.WalkSpeed
			reason = "fouille en cours"
		end
	elseif brain.state == "Chase" then
		if targetLost(brain, perception) then
			transition(brain, "Investigate", now)
			reason = "cible perdue"
			moveTo = brain.lastKnownPosition
		elseif (perception.targetDistance or math.huge) <= settings.AttackRange then
			transition(brain, "Attack", now)
			reason = "a portee"
			moveTo = nil
			speed = settings.ChaseSpeed
		else
			moveTo = perception.targetPosition or brain.lastKnownPosition
			speed = settings.ChaseSpeed
			reason = "poursuite"
		end
	elseif brain.state == "Attack" then
		if targetLost(brain, perception) then
			transition(brain, "Investigate", now)
			reason = "cible perdue"
			moveTo = brain.lastKnownPosition
		elseif (perception.targetDistance or math.huge) > settings.AttackRange then
			transition(brain, "Chase", now)
			reason = "cible s'eloigne"
			moveTo = perception.targetPosition
			speed = settings.ChaseSpeed
		else
			-- Le temps de recharge est verifie ici, mais la portee est
			-- revalidee cote serveur au moment d'infliger les degats : un
			-- cerveau qui dit "frappe" ne suffit pas a blesser quelqu'un.
			if (now - brain.lastAttackAt) >= settings.AttackCooldown then
				brain.lastAttackAt = now
				attack = true
				reason = "frappe"
			else
				reason = "recharge"
			end
			moveTo = nil
			speed = settings.ChaseSpeed
		end
	end

	local changed = brain.state ~= previousState

	-- On ne recalcule un chemin que si l'etat a change ou si la destination
	-- s'est deplacee de facon significative. Recalculer a chaque decision
	-- serait le poste de cout dominant de tout le systeme.
	local repath = false
	if moveTo then
		if changed or not brain.destination then
			repath = true
		elseif horizontalDistance(moveTo, brain.destination) > settings.RepathThreshold then
			repath = true
		end
	end

	if moveTo then
		brain.destination = moveTo
	end

	return {
		state = brain.state,
		previousState = previousState,
		changed = changed,
		moveTo = moveTo,
		speed = speed,
		attack = attack,
		repath = repath,
		reason = reason,
	}
end

return CrawlerBrain
