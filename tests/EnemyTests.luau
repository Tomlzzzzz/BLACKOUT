--!strict
-- Tests du cerveau du Crawler.
--
-- Portent sur Shared.CrawlerBrain, pur. C'est ce qui rend testable le
-- "1-6 players" demande : six joueurs fictifs et six crawlers se simulent
-- ici, la ou Studio ne fournit qu'un seul client.
--
--   require(game.ServerStorage.Tests.EnemyTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrawlerBrain = require(Shared.CrawlerBrain)
local Config = require(Shared.Config)

local EnemyTests = {}

type Report = {
	passed: number,
	failed: number,
	lines: { string },
}

local function check(report: Report, name: string, condition: boolean, detail: string?)
	if condition then
		report.passed += 1
		table.insert(report.lines, `  PASS  {name}`)
	else
		report.failed += 1
		table.insert(report.lines, `  FAIL  {name}` .. (if detail then ` -> {detail}` else ""))
	end
end

local function cfg()
	return Config.Enemies.crawler
end

-- Perception nominale : cible visible, vivante, a la distance donnee.
local function seen(now: number, selfPos: Vector3, targetPos: Vector3)
	return {
		now = now,
		selfPosition = selfPos,
		targetPosition = targetPos,
		targetDistance = (targetPos - selfPos).Magnitude,
		targetVisible = true,
		targetAlive = true,
	}
end

local function blind(now: number, selfPos: Vector3)
	return {
		now = now,
		selfPosition = selfPos,
		targetPosition = nil,
		targetDistance = nil,
		targetVisible = false,
		targetAlive = false,
	}
end

-- ------------------------------------------------- Selection de cible ----

local function testTargeting(report: Report)
	table.insert(report.lines, "selection de cible")

	local origin = Vector3.new(0, 0, 0)

	-- Six joueurs, distances croissantes : le plus proche doit gagner.
	local six = {}
	for index = 1, 6 do
		table.insert(six, {
			id = `joueur{index}`,
			position = Vector3.new(index * 10, 0, 0),
			valid = true,
		})
	end

	local chosen = CrawlerBrain.selectTarget(six, origin, 100)
	check(report, "6 joueurs : le plus proche est choisi", chosen ~= nil and chosen.id == "joueur1", chosen and chosen.id)

	-- Le plus proche est invalide (mort ou extrait) : on prend le suivant.
	six[1].valid = false
	chosen = CrawlerBrain.selectTarget(six, origin, 100)
	check(report, "le plus proche invalide est ignore", chosen ~= nil and chosen.id == "joueur2", chosen and chosen.id)

	-- Portee : au-dela de la detection, personne.
	chosen = CrawlerBrain.selectTarget(six, origin, 15)
	check(report, "hors portee : aucune cible", chosen == nil, chosen and chosen.id)

	-- Un seul joueur.
	chosen = CrawlerBrain.selectTarget({ { id = "solo", position = Vector3.new(5, 0, 0), valid = true } }, origin, 60)
	check(report, "1 joueur : choisi", chosen ~= nil and chosen.id == "solo")

	-- Aucun joueur.
	check(report, "0 joueur : nil", CrawlerBrain.selectTarget({}, origin, 60) == nil)

	-- Tous invalides.
	local dead = {}
	for index = 1, 6 do
		table.insert(dead, { id = `mort{index}`, position = Vector3.new(index, 0, 0), valid = false })
	end
	check(report, "6 joueurs tous invalides : nil", CrawlerBrain.selectTarget(dead, origin, 60) == nil)

	-- Distance mesuree en 3D, pas seulement au sol.
	local vertical = {
		{ id = "sol", position = Vector3.new(20, 0, 0), valid = true },
		{ id = "haut", position = Vector3.new(0, 40, 0), valid = true },
	}
	chosen = CrawlerBrain.selectTarget(vertical, origin, 60)
	check(report, "distance 3D respectee", chosen ~= nil and chosen.id == "sol", chosen and chosen.id)
end

-- ------------------------------------------------ Cycle Idle / Patrol ----

local function testIdlePatrol(report: Report)
	table.insert(report.lines, "repos et patrouille")

	local rng = Random.new(11)
	local brain = CrawlerBrain.new(Vector3.new(0, 0, 0), 0)
	check(report, "demarre en Idle", brain.state == "Idle")

	-- Le repos initial est ecoule des le premier appel : on part patrouiller.
	local decision = CrawlerBrain.think(brain, blind(1, Vector3.new(0, 0, 0)), rng)
	check(report, "Idle -> Patrol", decision.state == "Patrol", decision.state)
	check(report, "une destination est choisie", decision.moveTo ~= nil)
	check(report, "vitesse de marche", decision.speed == cfg().WalkSpeed, tostring(decision.speed))
	check(report, "changement d'etat signale", decision.changed)

	local destination = decision.moveTo :: Vector3
	check(
		report,
		"point de patrouille dans le rayon",
		(destination - brain.anchor).Magnitude <= cfg().PatrolRadius + 0.001,
		tostring((destination - brain.anchor).Magnitude)
	)

	-- Arrive sur place : retour au repos.
	local arrived = CrawlerBrain.think(brain, blind(2, destination), rng)
	check(report, "Patrol -> Idle a l'arrivee", arrived.state == "Idle", arrived.state)
	check(report, "aucun deplacement en Idle", arrived.moveTo == nil)

	-- Patrouille qui n'aboutit pas : delai de garde.
	local stuck = CrawlerBrain.new(Vector3.new(0, 0, 0), 0)
	CrawlerBrain.think(stuck, blind(1, Vector3.new(0, 0, 0)), rng)
	local timedOut = CrawlerBrain.think(stuck, blind(1 + cfg().PatrolTimeout + 1, Vector3.new(0, 0, 0)), rng)
	check(report, "patrouille bloquee expire", timedOut.state == "Idle", timedOut.state)
	check(report, "raison patrouille expiree", timedOut.reason == "patrouille expiree", timedOut.reason)
end

-- ------------------------------------ Acquisition, poursuite, attaque ----

local function testChaseAttack(report: Report)
	table.insert(report.lines, "poursuite et attaque")

	local rng = Random.new(5)
	local brain = CrawlerBrain.new(Vector3.new(0, 0, 0), 0)
	local selfPos = Vector3.new(0, 0, 0)

	-- Cible hors de portee de detection : rien ne se passe.
	local far = Vector3.new(cfg().DetectionRange + 20, 0, 0)
	local ignored = CrawlerBrain.think(brain, seen(1, selfPos, far), rng)
	check(report, "cible trop loin : pas de poursuite", ignored.state ~= "Chase", ignored.state)

	-- Cible dans la portee : acquisition immediate.
	local near = Vector3.new(30, 0, 0)
	local acquired = CrawlerBrain.think(brain, seen(2, selfPos, near), rng)
	check(report, "cible acquise -> Chase", acquired.state == "Chase", acquired.state)
	check(report, "vitesse de course", acquired.speed == cfg().ChaseSpeed, tostring(acquired.speed))
	check(report, "se dirige vers la cible", acquired.moveTo == near)
	check(report, "recalcul de chemin demande", acquired.repath)

	-- Approche jusqu'a portee de frappe.
	local close = Vector3.new(cfg().AttackRange - 1, 0, 0)
	local reached = CrawlerBrain.think(brain, seen(3, selfPos, close), rng)
	check(report, "a portee -> Attack", reached.state == "Attack", reached.state)
	check(report, "pas encore de frappe au changement d'etat", not reached.attack)

	-- La frappe suivante passe (temps de recharge jamais consomme).
	local strike = CrawlerBrain.think(brain, seen(4, selfPos, close), rng)
	check(report, "frappe autorisee", strike.attack)
	check(report, "raison frappe", strike.reason == "frappe", strike.reason)

	-- Immediatement apres : recharge.
	local recharging = CrawlerBrain.think(brain, seen(4.1, selfPos, close), rng)
	check(report, "recharge bloque la frappe", not recharging.attack)
	check(report, "raison recharge", recharging.reason == "recharge", recharging.reason)

	-- Une fois le delai ecoule : de nouveau autorisee.
	local again = CrawlerBrain.think(brain, seen(4 + cfg().AttackCooldown + 0.1, selfPos, close), rng)
	check(report, "frappe de nouveau autorisee apres recharge", again.attack)

	-- La cible s'ecarte : retour en poursuite.
	local fleeing = Vector3.new(cfg().AttackRange + 10, 0, 0)
	local backToChase = CrawlerBrain.think(brain, seen(10, selfPos, fleeing), rng)
	check(report, "Attack -> Chase quand la cible s'ecarte", backToChase.state == "Chase", backToChase.state)
	check(report, "raison cible s'eloigne", backToChase.reason == "cible s'eloigne", backToChase.reason)
end

-- -------------------------------- Perte de cible et retour a la patrouille --

local function testLoseTarget(report: Report)
	table.insert(report.lines, "perte de cible et retour")

	local rng = Random.new(7)
	local brain = CrawlerBrain.new(Vector3.new(0, 0, 0), 0)
	local selfPos = Vector3.new(0, 0, 0)
	local targetPos = Vector3.new(25, 0, 0)

	CrawlerBrain.think(brain, seen(1, selfPos, targetPos), rng)
	check(report, "en poursuite", brain.state == "Chase")
	check(report, "derniere position memorisee", brain.lastKnownPosition == targetPos)

	-- La cible se cache : invisible mais toujours proche. La poursuite
	-- continue tant que le delai d'abandon n'est pas ecoule.
	local hiding = {
		now = 2,
		selfPosition = selfPos,
		targetPosition = targetPos,
		targetDistance = 25,
		targetVisible = false,
		targetAlive = true,
	}
	local stillChasing = CrawlerBrain.think(brain, hiding, rng)
	check(report, "cachee brievement : poursuite maintenue", stillChasing.state == "Chase", stillChasing.state)

	-- Delai depasse : abandon et fouille.
	hiding.now = 1 + cfg().LoseTargetTime + 0.5
	local lost = CrawlerBrain.think(brain, hiding, rng)
	check(report, "cible perdue -> Investigate", lost.state == "Investigate", lost.state)
	check(report, "raison cible perdue", lost.reason == "cible perdue", lost.reason)
	check(report, "fouille la derniere position connue", lost.moveTo == targetPos)

	-- Fouille infructueuse : retour en patrouille.
	local giveUp = CrawlerBrain.think(
		brain,
		blind(1 + cfg().LoseTargetTime + 0.5 + cfg().InvestigateTime + 1, selfPos),
		rng
	)
	check(report, "Investigate -> Patrol", giveUp.state == "Patrol", giveUp.state)
	check(report, "raison fouille infructueuse", giveUp.reason == "fouille infructueuse", giveUp.reason)

	-- Fuite en ligne droite : au-dela de la portee d'abandon, on lache
	-- immediatement, meme si la cible reste visible.
	local runner = CrawlerBrain.new(Vector3.new(0, 0, 0), 0)
	CrawlerBrain.think(runner, seen(1, selfPos, Vector3.new(20, 0, 0)), rng)
	local escaped = CrawlerBrain.think(runner, seen(2, selfPos, Vector3.new(cfg().LoseTargetRange + 5, 0, 0)), rng)
	check(report, "fuite au-dela de la portee d'abandon", escaped.state == "Investigate", escaped.state)

	-- Hysteresis : entre DetectionRange et LoseTargetRange, on ne lache pas.
	local sticky = CrawlerBrain.new(Vector3.new(0, 0, 0), 0)
	CrawlerBrain.think(sticky, seen(1, selfPos, Vector3.new(20, 0, 0)), rng)
	local between = (cfg().DetectionRange + cfg().LoseTargetRange) / 2
	local held = CrawlerBrain.think(sticky, seen(2, selfPos, Vector3.new(between, 0, 0)), rng)
	check(report, "hysteresis : poursuite maintenue entre les deux portees", held.state == "Chase", held.state)

	-- Mort de la cible pendant l'attaque.
	local killer = CrawlerBrain.new(Vector3.new(0, 0, 0), 0)
	CrawlerBrain.think(killer, seen(1, selfPos, Vector3.new(3, 0, 0)), rng)
	CrawlerBrain.think(killer, seen(2, selfPos, Vector3.new(3, 0, 0)), rng)
	check(report, "en attaque", killer.state == "Attack", killer.state)
	local dead = CrawlerBrain.think(killer, {
		now = 3,
		selfPosition = selfPos,
		targetPosition = Vector3.new(3, 0, 0),
		targetDistance = 3,
		targetVisible = true,
		targetAlive = false,
	}, rng)
	check(report, "cible morte -> Investigate", dead.state == "Investigate", dead.state)
end

-- -------------------------------------------- Six crawlers, six joueurs --

local function testSixPlayers(report: Report)
	table.insert(report.lines, "6 crawlers face a 6 joueurs")

	local rng = Random.new(99)

	-- Six crawlers ancres en cercle, six joueurs disperses.
	local brains = {}
	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2
		table.insert(brains, CrawlerBrain.new(Vector3.new(math.cos(angle) * 40, 0, math.sin(angle) * 40), 0))
	end

	local players = {}
	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2 + 0.4
		table.insert(players, {
			id = `joueur{index}`,
			position = Vector3.new(math.cos(angle) * 45, 0, math.sin(angle) * 45),
			valid = true,
		})
	end

	-- Chaque crawler doit verrouiller le joueur le plus proche de LUI.
	local picks: { [string]: number } = {}
	for index, brain in brains do
		local chosen = CrawlerBrain.selectTarget(players, brain.anchor, cfg().DetectionRange)
		check(report, `crawler {index} trouve une cible`, chosen ~= nil)
		if chosen then
			picks[chosen.id] = (picks[chosen.id] or 0) + 1

			-- Verification independante : aucun autre joueur n'est plus proche.
			local best = math.huge
			local bestId = ""
			for _, candidate in players do
				local d = (candidate.position - brain.anchor).Magnitude
				if d < best then
					best = d
					bestId = candidate.id
				end
			end
			check(report, `crawler {index} choisit bien le plus proche`, chosen.id == bestId, `{chosen.id} vs {bestId}`)
		end
	end

	-- Etats independants : on fait avancer les six et on verifie qu'aucun
	-- n'a contamine son voisin.
	for index, brain in brains do
		local target = players[index]
		CrawlerBrain.think(brain, seen(1, brain.anchor, target.position), rng)
	end

	local states: { [string]: number } = {}
	for _, brain in brains do
		states[brain.state] = (states[brain.state] or 0) + 1
	end
	check(report, "les 6 cerveaux ont un etat propre", #brains == 6)
	check(report, "aucun etat partage par accident", states["Chase"] ~= nil, tostring(states["Chase"]))

	-- Un crawler qui perd sa cible n'affecte pas les autres.
	CrawlerBrain.think(brains[1], blind(1 + cfg().LoseTargetTime + 1, brains[1].anchor), rng)
	check(report, "crawler 1 abandonne", brains[1].state == "Investigate", brains[1].state)
	check(report, "crawler 2 poursuit toujours", brains[2].state == "Chase", brains[2].state)
end

-- ----------------------------------------------------- Configuration ----

local function testConfig(report: Report)
	table.insert(report.lines, "configuration")

	local required = {
		"DetectionRange",
		"AttackRange",
		"Damage",
		"AttackCooldown",
		"WalkSpeed",
		"ChaseSpeed",
	}
	for _, key in required do
		check(report, `{key} configure`, (cfg() :: any)[key] ~= nil, "absent")
	end

	check(report, "drapeau de journalisation present", Config.Enemies.debugLogging ~= nil)
	check(report, "journalisation desactivee par defaut", Config.Enemies.debugLogging == false)
	check(report, "course plus rapide que marche", cfg().ChaseSpeed > cfg().WalkSpeed)
	check(report, "portee d'attaque sous portee de detection", cfg().AttackRange < cfg().DetectionRange)
	check(
		report,
		"hysteresis : abandon au-dela de la detection",
		cfg().LoseTargetRange > cfg().DetectionRange,
		`{cfg().LoseTargetRange} vs {cfg().DetectionRange}`
	)
	check(report, "cadences decouplees et non nulles", cfg().SenseRate > 0 and cfg().ThinkRate > 0 and cfg().RepathRate > 0)
	check(
		report,
		"recalcul de chemin moins frequent que la decision",
		cfg().RepathRate > cfg().ThinkRate,
		`{cfg().RepathRate} vs {cfg().ThinkRate}`
	)
end

-- ------------------------------------------------------------- Run ------

function EnemyTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testTargeting(report)
	testIdlePatrol(report)
	testChaseAttack(report)
	testLoseTarget(report)
	testSixPlayers(report)
	testConfig(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return EnemyTests
