--!strict
-- Ennemis : construction, perception, execution des decisions, degats.
--
-- L'IA elle-meme vit dans Shared.CrawlerBrain, pur. Ce service ne fait que
-- trois choses : mesurer le monde, faire tourner le cerveau, appliquer ce
-- qu'il decide.
--
-- Rien ne tourne par image. Trois cadences decouplees, toutes reglables :
--   SenseRate  (0.30s) — raycast de visibilite, le poste le plus cher
--   ThinkRate  (0.20s) — machine a etats, bon marche
--   RepathRate (0.70s) — PathfindingService, le plus lourd
--
-- Les degats sont infliges ici et nulle part ailleurs, apres revalidation
-- de la portee et de l'etat de la cible : la decision du cerveau est une
-- intention, pas une autorisation.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local CrawlerBrain = require(Shared.CrawlerBrain)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type CrawlerBrainState = Types.CrawlerBrainState
type TargetCandidate = Types.TargetCandidate

type Crawler = {
	id: number,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	brain: CrawlerBrainState,
	target: Player?,
	targetPosition: Vector3?,
	targetDistance: number?,
	targetVisible: boolean,
	nextSense: number,
	nextThink: number,
	nextRepath: number,
	waypoints: { PathWaypoint },
	waypointIndex: number,
	isBoss: boolean,
	spawnedAt: number,
	-- Dernier joueur a avoir inflige des degats. Sert a attribuer le kill.
	lastAttacker: Player?,
}

local EnemyService = {}

EnemyService.Name = "EnemyService"
EnemyService.Priority = 60

-- Emis quand un ennemi VERROUILLE un joueur (passage en poursuite). C'est
-- l'evenement que le commanditaire relaie : « vous etes suivi ».
EnemyService.TargetAcquired = Signal.new()

local log = Logger.new("EnemyService")
local ctx: ServiceContext?

local crawlers: { [number]: Crawler } = {}
local nextId = 0
local folder: Folder?
local heartbeat: RBXScriptConnection?
local connections: { RBXScriptConnection } = {}
local rng = Random.new()
local rayParams = RaycastParams.new()

-- Multiplicateur de portee de detection, releve pendant The Hunt.
local detectionMultiplier = 1

-- Instant de la derniere reapparition, par joueur. Sert au delai de grace.
local spawnedAt: { [Player]: number } = {}

local function settings()
	return Config.Enemies.crawler
end

-- Journalisation derriere le drapeau de configuration. Sans ce garde-fou,
-- six crawlers produiraient plusieurs lignes par seconde chacun.
local function trace(message: string)
	if Config.Enemies.debugLogging then
		log:info(message)
	end
end

-- ---------------------------------------------------------- Sanctuaire ---

-- Points de reapparition des joueurs, mis en cache.
--
-- La version naive relisait Workspace:GetDescendants() a chaque appel. Comme
-- le sanctuaire est consulte pour chaque joueur, pour chaque crawler, a
-- chaque cycle de perception, ca faisait plusieurs parcours complets du
-- monde par seconde — assez pour figer le serveur. Mesure : le playtest ne
-- repondait plus.
--
-- Le cache expire au bout de `SPAWN_CACHE_TTL` : un SpawnLocation pose en
-- cours de partie est pris en compte en quelques secondes, ce qui est
-- largement suffisant pour du placement de niveau.
local SPAWN_CACHE_TTL = 5

local cachedSpawnPoints: { Vector3 } = {}
local spawnCacheExpiry = 0

local function spawnPoints(): { Vector3 }
	local now = os.clock()
	if now < spawnCacheExpiry then
		return cachedSpawnPoints
	end

	local points: { Vector3 } = {}
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			table.insert(points, descendant.Position)
		end
	end

	cachedSpawnPoints = points
	spawnCacheExpiry = now + SPAWN_CACHE_TTL
	return points
end

local function isInSanctuary(position: Vector3): boolean
	local radius = Config.Enemies.spawnGuard.radius
	for _, point in spawnPoints() do
		if (position - point).Magnitude <= radius then
			return true
		end
	end
	return false
end

-- Un joueur est protege s'il se trouve dans le sanctuaire, ou s'il vient de
-- reapparaitre. Le second cas couvre celui qui court hors de la bulle avant
-- d'avoir repris le controle.
local function isProtected(player: Player, position: Vector3): boolean
	local since = spawnedAt[player]
	if since and (os.clock() - since) < Config.Enemies.spawnGuard.graceTime then
		return true
	end
	return isInSanctuary(position)
end

-- ------------------------------------------------------------ Fabrique ---

local function getFolder(): Folder
	local existing = Workspace:FindFirstChild("Enemies")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local created = Instance.new("Folder")
	created.Name = "Enemies"
	created.Parent = Workspace
	return created
end

local function buildCrawler(position: Vector3, isBoss: boolean?): Crawler?
	nextId += 1
	local id = nextId

	local boss = Config.Enemies.boss
	local scale = if isBoss then boss.scale else 1

	local model = Instance.new("Model")
	model.Name = if isBoss then `{boss.name}_{id}` else `Crawler_{id}`

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 1.2, 3) * scale
	root.Color = if isBoss then boss.color else Color3.fromRGB(70, 45, 45)
	root.Material = Enum.Material.Slate
	root.CanCollide = true
	root.Position = position
	root.Parent = model

	local eye = Instance.new("Part")
	eye.Name = "Eye"
	eye.Size = Vector3.new(0.5, 0.5, 0.5)
	eye.Color = Color3.fromRGB(230, 60, 40)
	eye.Material = Enum.Material.Neon
	eye.CanCollide = false
	eye.Massless = true
	eye.Position = position + Vector3.new(0, 0.5, -1.4)
	eye.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = eye
	weld.Parent = root

	local humanoid = Instance.new("Humanoid")
	-- Sans cou, un Humanoid meurt instantanement quand RequiresNeck est
	-- laisse a true. Ce rig n'a pas de tete : il faut le desactiver.
	humanoid.RequiresNeck = false
	local maxHealth = settings().Health * (if isBoss then boss.healthMultiplier else 1)
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = settings().WalkSpeed
	humanoid.HipHeight = 0.6
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = folder

	local crawler: Crawler = {
		id = id,
		model = model,
		humanoid = humanoid,
		root = root,
		brain = CrawlerBrain.new(position, os.clock()),
		target = nil,
		targetPosition = nil,
		targetDistance = nil,
		targetVisible = false,
		nextSense = 0,
		nextThink = 0,
		nextRepath = 0,
		waypoints = {},
		waypointIndex = 1,
		isBoss = isBoss == true,
		spawnedAt = os.clock(),
		lastAttacker = nil,
	}

	crawlers[id] = crawler

	humanoid.Died:Connect(function()
		crawlers[id] = nil
		trace(`{model.Name} mort`)

		local context = ctx
		local threatService = context and context.Get("ThreatService")
		if threatService then
			(threatService :: any):AddSource("ENEMY_KILLED")
		end

		-- Attribution du kill au dernier agresseur connu. Un crawler mort
		-- sans agresseur (commande de debug, chute, despawn) ne credite
		-- personne : gonfler la statistique serait pire que la laisser a
		-- zero.
		local killer = crawler.lastAttacker
		if killer and killer.Parent then
			local dataService = context and context.Get("DataService")
			local profile = dataService and (dataService :: any).GetProfile(killer)
			if profile then
				profile.Statistics.Kills += 1
			end
		end

		if isBoss then
			local analytics = context and context.Get("AnalyticsService")
			if analytics then
				(analytics :: any).Track("BossKilled", nil, {
					boss = boss.name,
					duration = math.floor(os.clock() - crawler.spawnedAt),
					players = #Players:GetPlayers(),
				})
			end
		end

		task.delay(4, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)

	if isBoss then
		local context = ctx
		local analytics = context and context.Get("AnalyticsService")
		local threatService = context and context.Get("ThreatService")
		if analytics then
			(analytics :: any).Track("BossSpawned", nil, {
				boss = boss.name,
				threat = if threatService then math.floor((threatService :: any):GetThreat()) else 0,
				players = #Players:GetPlayers(),
			})
		end
		log:warn(`{model.Name} apparait — {math.floor(maxHealth)} pv`)
	end

	return crawler
end

-- ---------------------------------------------------------- Perception ---

local function candidatesFor(crawler: Crawler): { TargetCandidate }
	local list: { TargetCandidate } = {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		-- Un joueur extrait est hors de la carte : il ne doit ni etre vu,
		-- ni etre poursuivi.
		local valid = root ~= nil
			and root:IsA("BasePart")
			and humanoid ~= nil
			and humanoid.Health > 0
			and player:GetAttribute("Extracted") ~= true

		-- Ni vu, ni poursuivi tant qu'il est protege. On l'ecarte des
		-- candidats plutot que d'annuler l'attaque plus tard : un crawler
		-- qui campe la bordure du sanctuaire est presque aussi punitif
		-- qu'un crawler qui frappe dedans.
		if valid and root and root:IsA("BasePart") and isProtected(player, root.Position) then
			valid = false
		end

		if valid and root and root:IsA("BasePart") then
			table.insert(list, {
				id = tostring(player.UserId),
				position = root.Position,
				valid = true,
			})
		end
	end

	return list
end

local function playerFromCandidate(candidate: TargetCandidate): Player?
	for _, player in Players:GetPlayers() do
		if tostring(player.UserId) == candidate.id then
			return player
		end
	end
	return nil
end

local function hasLineOfSight(crawler: Crawler, position: Vector3): boolean
	local origin = crawler.root.Position + Vector3.new(0, 1, 0)
	local direction = position - origin

	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { crawler.model }

	local result = Workspace:Raycast(origin, direction, rayParams)
	if not result then
		return true
	end

	-- On touche quelque chose : c'est bloque, sauf si l'obstacle est le
	-- personnage vise lui-meme.
	local hitCharacter = result.Instance:FindFirstAncestorOfClass("Model")
	if hitCharacter and hitCharacter:FindFirstChildOfClass("Humanoid") then
		return true
	end

	return false
end

local function sense(crawler: Crawler, now: number)
	-- Le boss voit plus loin : sa valeur de config etait declaree et jamais
	-- lue, si bien qu'il avait exactement la meme perception qu'un crawler
	-- ordinaire.
	local bossFactor = if crawler.isBoss then Config.Enemies.boss.detectionMultiplier else 1
	local range = settings().DetectionRange * detectionMultiplier * bossFactor
	local candidates = candidatesFor(crawler)
	local chosen = CrawlerBrain.selectTarget(candidates, crawler.root.Position, math.max(range, settings().LoseTargetRange))

	if not chosen then
		crawler.target = nil
		crawler.targetPosition = nil
		crawler.targetDistance = nil
		crawler.targetVisible = false
		return
	end

	local player = playerFromCandidate(chosen)
	crawler.target = player
	crawler.targetPosition = chosen.position
	crawler.targetDistance = (chosen.position - crawler.root.Position).Magnitude
	-- ACCROUPI : la portee effective se reduit pour CE joueur.
	--
	-- C'est ici, et nulle part ailleurs, que s'accroupir sert a quelque
	-- chose. La reduction s'applique a la visibilite, pas a la selection
	-- de cible : une creature deja lancee ne perd pas sa proie parce que
	-- celle-ci s'accroupit, elle cesse seulement de la REPERER de loin.
	local effectiveRange = range
	if player and player:GetAttribute("Crouched") == true then
		effectiveRange *= Config.Player.crouch.detectionMultiplier
	end

	crawler.targetVisible = crawler.targetDistance <= effectiveRange
		and hasLineOfSight(crawler, chosen.position)

	-- Premiere fois qu'un ennemi voit ce joueur. TrackOnce se charge de
	-- n'en garder qu'une par joueur, a vie.
	if crawler.targetVisible and player then
		local context = ctx
		local analytics = context and context.Get("AnalyticsService")
		if analytics then
			(analytics :: any).TrackOnce("FirstEnemyEncounter", player, {
				enemy = if crawler.isBoss then Config.Enemies.boss.name else "Crawler",
				distance = math.floor(crawler.targetDistance :: number),
			})
		end
	end
end

-- --------------------------------------------------------- Deplacement ---

local function repath(crawler: Crawler, destination: Vector3)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 2,
		AgentCanJump = false,
	})

	local ok = pcall(function()
		path:ComputeAsync(crawler.root.Position, destination)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		crawler.waypoints = path:GetWaypoints()
		crawler.waypointIndex = 1
		trace(`Crawler_{crawler.id} chemin de {#crawler.waypoints} points`)
		return
	end

	-- Chemin impraticable : on vise en direct plutot que de rester plante.
	-- Un crawler qui ne bouge plus est pire qu'un crawler qui bute contre
	-- un mur, parce qu'il n'a l'air de rien plutot que d'avoir l'air bete.
	crawler.waypoints = {}
	crawler.waypointIndex = 1
	crawler.humanoid:MoveTo(destination)
	trace(`Crawler_{crawler.id} chemin indisponible, approche directe`)
end

local function advance(crawler: Crawler)
	local waypoints = crawler.waypoints
	if #waypoints == 0 then
		return
	end

	local waypoint = waypoints[crawler.waypointIndex]
	if not waypoint then
		crawler.waypoints = {}
		return
	end

	local flat = Vector3.new(waypoint.Position.X, crawler.root.Position.Y, waypoint.Position.Z)
	if (flat - crawler.root.Position).Magnitude <= 3 then
		crawler.waypointIndex += 1
		local nextPoint = waypoints[crawler.waypointIndex]
		if nextPoint then
			crawler.humanoid:MoveTo(nextPoint.Position)
		else
			crawler.waypoints = {}
		end
	else
		crawler.humanoid:MoveTo(waypoint.Position)
	end
end

-- -------------------------------------------------------------- Degats ---

-- Seul endroit du projet ou un joueur perd de la vie a cause d'un ennemi.
-- La decision du cerveau ne suffit pas : on revalide la portee et l'etat
-- de la cible au moment d'appliquer, avec les positions courantes.
local function applyDamage(crawler: Crawler)
	local player = crawler.target
	if not player then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	if humanoid.Health <= 0 or player:GetAttribute("Extracted") == true then
		return
	end

	local distance = (root.Position - crawler.root.Position).Magnitude
	if distance > settings().AttackRange then
		trace(`Crawler_{crawler.id} frappe refusee : {math.floor(distance)} studs`)
		return
	end

	local damage = settings().Damage * (if crawler.isBoss then Config.Enemies.boss.damageMultiplier else 1)

	-- On ne touche plus le Humanoid directement.
	--
	-- PlayerService.ApplyDamage est le seul endroit ou l'armure s'interpose
	-- et ou la severite du coup est classee. Frapper le Humanoid ici
	-- rendrait l'armure inoperante contre les crawlers — c'est-a-dire contre
	-- la seule source de degats du jeu.
	local context = ctx
	local playerService = context and context.Get("PlayerService")
	if not playerService then
		return
	end

	local report = (playerService :: any).ApplyDamage(player, damage, crawler.model.Name, crawler.root.Position)
	if not report then
		return
	end

	trace(`{crawler.model.Name} inflige {damage} a {player.Name} ({math.floor(report.remaining)} restants)`)

	local analytics = context and context.Get("AnalyticsService")
	if analytics then
		(analytics :: any).Record("crawler_hit", player, {
			damage = damage,
			absorbed = math.floor(report.toArmor),
			remaining = math.floor(report.remaining),
			severity = report.severity,
		})
	end
end

-- --------------------------------------------------------- Degats subis ---

-- Point d'entree des degats INFLIGES A un ennemi.
--
-- ATTENTION : personne ne l'appelle encore — il n'existe aucune arme dans le
-- jeu. La couture existe pour que le jour ou le combat arrivera, le kill
-- soit attribue au bon joueur sans avoir a retoucher EnemyService.
--
-- Retourne false si la cible est inconnue ou deja morte.
-- Contacts hostiles autour d'une position.
--
-- Le serveur est le seul a connaitre la position des ennemis : le client ne
-- peut pas la deviner, et c'est voulu. Cette fonction est la SEULE porte par
-- laquelle une information de position ennemie sort — elle ne rend qu'un
-- releve grossier (distance, cap, gabarit), jamais l'instance.
export type Contact = {
	distance: number,
	bearing: number,
	isBoss: boolean,
	chasing: boolean,
}

function EnemyService.QueryNear(position: Vector3, radius: number): { Contact }
	local contacts: { Contact } = {}

	for _, crawler in crawlers do
		if crawler.humanoid.Health <= 0 then
			continue
		end

		local offset = crawler.root.Position - position
		local distance = offset.Magnitude
		if distance > radius then
			continue
		end

		-- Cap absolu, 0 = nord. Le meme repere que la boussole du HUD : le
		-- joueur peut lire « secteur NE » et tourner la tete au bon endroit.
		local bearing = math.deg(math.atan2(offset.X, -offset.Z))

		table.insert(contacts, {
			distance = distance,
			bearing = (bearing % 360 + 360) % 360,
			isBoss = crawler.isBoss,
			chasing = crawler.brain.state == "Chase",
		})
	end

	table.sort(contacts, function(a, b)
		return a.distance < b.distance
	end)

	return contacts
end

function EnemyService.DamageEnemy(model: Instance, amount: number, attacker: Player?): boolean
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end

	for _, crawler in crawlers do
		if crawler.model == model then
			if crawler.humanoid.Health <= 0 then
				return false
			end
			if attacker then
				crawler.lastAttacker = attacker
			end
			crawler.humanoid:TakeDamage(amount)
			-- Deuxieme valeur : la cible est-elle tombee sur CE coup. Sans
			-- elle, le client ne saurait pas distinguer un marqueur de touche
			-- d'une confirmation d'elimination.
			return true, crawler.humanoid.Health <= 0
		end
	end

	return false, false
end

-- ---------------------------------------------------------------- Tick ---

local function updateCrawler(crawler: Crawler, now: number)
	if crawler.humanoid.Health <= 0 then
		return
	end

	if now >= crawler.nextSense then
		crawler.nextSense = now + settings().SenseRate
		sense(crawler, now)
	end

	if now < crawler.nextThink then
		advance(crawler)
		return
	end
	crawler.nextThink = now + settings().ThinkRate

	local decision = CrawlerBrain.think(crawler.brain, {
		now = now,
		selfPosition = crawler.root.Position,
		targetPosition = crawler.targetPosition,
		targetDistance = crawler.targetDistance,
		targetVisible = crawler.targetVisible,
		targetAlive = crawler.target ~= nil,
	}, rng)

	if decision.changed then
		trace(`Crawler_{crawler.id} {decision.previousState} -> {decision.state} ({decision.reason})`)

		-- Entree en poursuite : la cible vient d'etre verrouillee. On ne
		-- signale que la TRANSITION, pas l'etat : un crawler qui poursuit
		-- pendant vingt secondes ne doit produire qu'une alerte.
		if decision.state == "Chase" and decision.previousState ~= "Chase" and crawler.target then
			Signal.fire(EnemyService.TargetAcquired, crawler.target, crawler.root.Position, crawler.isBoss)
		end
	end

	crawler.humanoid.WalkSpeed = decision.speed

	if decision.attack then
		applyDamage(crawler)
	end

	if decision.moveTo and decision.repath and now >= crawler.nextRepath then
		crawler.nextRepath = now + settings().RepathRate
		repath(crawler, decision.moveTo)
	end

	advance(crawler)
end

-- ------------------------------------------------------- Repeuplement ----

local repopulateAt = 0

local function aliveCount(): number
	local count = 0
	for _ in crawlers do
		count += 1
	end
	return count
end

-- Point d'apparition tire au hasard sur un anneau autour d'un joueur.
--
-- Trois conditions, toutes necessaires :
--   assez LOIN de tous les joueurs (jamais dans un champ de vision) ;
--   hors sanctuaire d'apparition ;
--   sur du sol (sonde verticale, sinon la creature tombe dans le vide).
local function findSpawnPosition(): Vector3?
	local players = Players:GetPlayers()
	if #players == 0 then
		return nil
	end

	local settings = Config.Enemies.population

	for _ = 1, settings.attempts do
		local anchor = players[math.random(#players)]
		local root = anchor.Character and anchor.Character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		local angle = math.random() * math.pi * 2
		local radius = settings.minDistance + math.random() * (settings.maxDistance - settings.minDistance)
		local candidate = root.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

		-- Aucun joueur trop pres, pas seulement celui qui a servi d'ancre.
		local tooClose = false
		for _, other in players do
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				local flat = (otherRoot.Position - candidate) * Vector3.new(1, 0, 1)
				if flat.Magnitude < settings.minDistance then
					tooClose = true
					break
				end
			end
		end
		if tooClose then
			continue
		end

		if isInSanctuary(candidate) then
			continue
		end

		-- Sonde du sol. On ignore les creatures deja posees, sinon deux
		-- crawlers finissent empiles.
		local parameters = RaycastParams.new()
		parameters.FilterType = Enum.RaycastFilterType.Exclude
		parameters.FilterDescendantsInstances = { folder :: any }

		local from = candidate + Vector3.new(0, settings.probeHeight, 0)
		local hit = Workspace:Raycast(from, Vector3.new(0, -settings.probeDepth, 0), parameters)

		local y = if hit then hit.Position.Y + 2 else settings.fallbackY
		return Vector3.new(candidate.X, y, candidate.Z)
	end

	return nil
end

local function repopulate(now: number)
	local settings = Config.Enemies.population
	if now < repopulateAt then
		return
	end
	repopulateAt = now + settings.interval

	local alive = aliveCount()
	local wanted = math.min(settings.targetAlive, Config.Enemies.maxAlive)
	if alive >= wanted then
		return
	end

	local built = 0
	for _ = 1, math.min(settings.batch, wanted - alive) do
		local position = findSpawnPosition()
		if not position then
			break
		end
		if buildCrawler(position) then
			built += 1
		end
	end

	if built > 0 then
		trace(`repeuplement : {built} crawler(s), effectif {alive} -> {aliveCount()}`)
	end
end

local function tick()
	local now = os.clock()
	for _, crawler in crawlers do
		updateCrawler(crawler, now)
	end
	repopulate(now)
end

-- --------------------------------------------------------------- Spawn ---

local function populate(): number
	folder = getFolder()

	local markers: { Vector3 } = {}
	local spawnFolder = Workspace:FindFirstChild("EnemySpawns")
	if spawnFolder then
		for _, marker in spawnFolder:GetChildren() do
			if marker:IsA("BasePart") then
				table.insert(markers, marker.Position)
				marker:Destroy()
			end
		end
	end

	if #markers == 0 then
		markers = Config.Enemies.fallbackSpawns
		log:info(`aucun marqueur dans Workspace.EnemySpawns, {#markers} positions de secours`)
	end

	local built = 0
	local rejected = 0

	for _, position in markers do
		if built >= Config.Enemies.maxAlive then
			break
		end

		if isInSanctuary(position) then
			rejected += 1
			continue
		end

		if buildCrawler(position) then
			built += 1
		end
	end

	if rejected > 0 then
		log:warn(
			`{rejected} position(s) d'apparition rejetee(s) : trop pres d'un point de`
				.. ` reapparition joueur (sanctuaire de {Config.Enemies.spawnGuard.radius} studs)`
		)
	end

	return built
end

-- ---------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local existing = ServerStorage:FindFirstChild("DebugEnemy")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugEnemy"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: any, argument: any): string
		if action == "sanctuaire" then
			local lines = {
				`rayon : {Config.Enemies.spawnGuard.radius} studs`,
				`grace : {Config.Enemies.spawnGuard.graceTime}s`,
			}
			for _, point in spawnPoints() do
				table.insert(lines, `point de reapparition : {math.floor(point.X)},{math.floor(point.Y)},{math.floor(point.Z)}`)
			end
			for _, crawler in crawlers do
				if isInSanctuary(crawler.root.Position) then
					table.insert(lines, `INTRUS : {crawler.model.Name} dans le sanctuaire`)
				end
			end
			return table.concat(lines, "\n")
		end

		if action == "status" then
			local lines = { `journalisation IA : {tostring(Config.Enemies.debugLogging)}` }
			for _, crawler in crawlers do
				-- Le nom du modele, pas un libelle reconstruit : le boss
				-- s'affichait sous "Crawler_N" et devenait indistinguable
				-- d'un ennemi ordinaire dans les diagnostics.
				table.insert(lines, `{crawler.model.Name} : {crawler.brain.state}`
					.. ` pv={math.floor(crawler.humanoid.Health)}`
					.. ` cible={if crawler.target then crawler.target.Name else "aucune"}`
					.. ` dist={if crawler.targetDistance then math.floor(crawler.targetDistance) else "-"}`
					.. ` vue={tostring(crawler.targetVisible)}`)
			end
			return table.concat(lines, "\n")
		end

		if action == "spawn" then
			local player = Players:GetPlayers()[1]
			local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local position = if root and root:IsA("BasePart")
				then root.Position + Vector3.new(0, 3, -(tonumber(argument) or 25))
				else Vector3.new(0, 5, 0)
			local crawler = buildCrawler(position)
			return if crawler then `Crawler_{crawler.id} pose a {math.floor((tonumber(argument) or 25))} studs` else "echec"
		end

		if action == "boss" then
			local player = Players:GetPlayers()[1]
			local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local position = if root and root:IsA("BasePart")
				then root.Position + Vector3.new(0, 4, -(tonumber(argument) or 30))
				else Vector3.new(0, 8, 0)
			local crawler = buildCrawler(position, true)
			return if crawler then `{crawler.model.Name} pose` else "echec"
		end

		if action == "kill" then
			for _, crawler in crawlers do
				crawler.humanoid.Health = 0
			end
			return "tous les crawlers elimines"
		end

		-- Eprouve l'attribution du kill : degats portes au nom du joueur.
		if action == "killby" then
			local player = Players:GetPlayers()[1]
			if not player then
				return "aucun joueur"
			end
			for _, crawler in crawlers do
				if crawler.humanoid.Health > 0 then
					EnemyService.DamageEnemy(crawler.model, crawler.humanoid.MaxHealth, player)
					return `{crawler.model.Name} elimine par {player.Name}`
				end
			end
			return "aucun crawler vivant"
		end

		return "actions : status | sanctuaire | spawn [distance] | boss [distance] | kill | killby"
	end

	log:info("debug : ServerStorage.DebugEnemy:Invoke(\"status\"|\"spawn\"|\"kill\")")
end

-- ---------------------------------------------------------- Cycle de vie ---

function EnemyService.Init(context: ServiceContext)
	ctx = context
end

function EnemyService.Start()
	local built = populate()
	installDebug()

	-- Pendant The Hunt, les crawlers voient bien plus loin. C'est le seul
	-- effet concret de la traque pour l'instant.
	local context = ctx
	local threatService = context and context.Get("ThreatService")
	if threatService then
		local Signal = require(Shared.Utils.Signal)
		Signal.connect((threatService :: any).HuntStarted, function()
			detectionMultiplier = 2
			log:warn("traque en cours : portee de detection doublee")
		end)
		Signal.connect((threatService :: any).HuntEnded, function()
			detectionMultiplier = 1
			log:info("traque terminee : portee de detection normale")
		end)
	end

	local function watch(player: Player)
		spawnedAt[player] = os.clock()
		table.insert(connections, player.CharacterAdded:Connect(function()
			spawnedAt[player] = os.clock()
		end))
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watch))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		spawnedAt[player] = nil
	end))

	heartbeat = RunService.Heartbeat:Connect(tick)

	log:info(
		`pret — {built} crawlers, detection {settings().DetectionRange},`
			.. ` degats {settings().Damage}, journalisation {tostring(Config.Enemies.debugLogging)}`
	)
end

function EnemyService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	for _, crawler in crawlers do
		crawler.model:Destroy()
	end
	table.clear(crawlers)
end

return EnemyService
