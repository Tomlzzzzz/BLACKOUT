--!strict
-- Zones d'extraction : entree, maintien, sortie reussie.
--
-- C'est le service qui decide qu'un raid se termine en victoire, donc le
-- seul endroit ou du butin devient definitivement acquis. Il est bati sur
-- Shared.Extraction, pur, qu'il se contente d'alimenter en conditions
-- mesurees dans le monde.
--
-- La detection se fait par echantillonnage a `tickRate`, pas par Touched.
-- Touched depend de la physique, se declenche en rafale et se rate quand le
-- personnage glisse le long d'une bordure ; une mesure de distance est
-- deterministe et gratuite au regard du nombre de joueurs vise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Extraction = require(Shared.Extraction)
local ItemDatabase = require(Shared.ItemDatabase)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type ExtractionProgress = Types.ExtractionProgress
type ItemStack = Types.ItemStack

type Zone = {
	name: string,
	position: Vector3,
	radius: number,
	holdTime: number,
	active: boolean,
	part: BasePart,
}

type Session = {
	zone: Zone,
	progress: ExtractionProgress,
	lastPush: number,
}

local ExtractionService = {}

ExtractionService.Name = "ExtractionService"
ExtractionService.Priority = 70

-- Signaux serveur. Le service diffusait deja ces moments au client ; les
-- exposer en interne evite qu'un autre service ait a deviner l'etat d'une
-- extraction en observant des attributs.
ExtractionService.Completed = Signal.new()
ExtractionService.Cancelled = Signal.new()
ExtractionService.ZonesRotated = Signal.new()

local log = Logger.new("ExtractionService")
local ctx: ServiceContext?

local zones: { Zone } = {}
local sessions: { [Player]: Session } = {}

-- Joueurs deja extraits. C'est la garde ultime contre la double
-- recompense : elle survit a la fin de la session d'extraction, la ou le
-- garde-fou de Shared.Extraction ne protege qu'une extraction donnee.
local extracted: { [Player]: boolean } = {}

-- Les sorties sont-elles ouvertes pour la fenetre en cours ?
local opened = false

-- Debut de la course en cours, pour chiffrer sa duree. Renseigne par
-- PlayerService a l'apparition.
local runStartedAt: { [Player]: number } = {}

local folder: Folder?
local heartbeat: RBXScriptConnection?
local connections: { RBXScriptConnection } = {}
local accumulator = 0

-- ------------------------------------------------------------- Remotes ---

local function fire(remoteName: string, player: Player, ...: any)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, ...)
	end
end

-- ---------------------------------------------------------------- Zones ---

local function getFolder(): Folder
	local existing = Workspace:FindFirstChild("ExtractionZones")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local created = Instance.new("Folder")
	created.Name = "ExtractionZones"
	created.Parent = Workspace
	return created
end

local function buildZone(name: string, position: Vector3, radius: number, holdTime: number): Zone
	local part = Instance.new("Part")
	part.Name = `Zone_{name}`
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(1, radius * 2, radius * 2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = Config.Extraction.visual.closedTransparency
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = folder

	-- Balise verticale. C'est ELLE qui rend une sortie ouverte trouvable
	-- de loin ; la dalle au sol ne sert qu'a delimiter la zone une fois
	-- qu'on y est. Eteinte tant que la sortie est verrouillee.
	local visual = Config.Extraction.visual
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Size = Vector3.new(visual.beaconHeight, visual.beaconWidth, visual.beaconWidth)
	beacon.CFrame = CFrame.new(position + Vector3.new(0, visual.beaconHeight / 2, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CastShadow = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = visual.openColor
	beacon.Transparency = 1
	beacon.Parent = part

	return {
		name = name,
		position = position,
		radius = radius,
		holdTime = holdTime,
		active = false,
		part = part,
	}
end

local function setActive(zone: Zone, active: boolean)
	zone.active = active

	-- Attributs replique au client : c'est ce qui lui permet d'indiquer la
	-- sortie ouverte la plus proche sans jamais decider quoi que ce soit.
	zone.part:SetAttribute("ZoneName", zone.name)
	zone.part:SetAttribute("Active", active)
	zone.part:SetAttribute("HoldTime", zone.holdTime)
	-- Vert ouverte, rouge fermee. Le joueur doit pouvoir lire l'etat d'une
	-- zone de loin : courir douze secondes vers une sortie fermee est une
	-- punition qu'aucune regle ne justifie.
	local visual = Config.Extraction.visual
	zone.part.Color = if active then visual.openColor else visual.closedColor
	zone.part.Transparency = if active then visual.openTransparency else visual.closedTransparency
	zone.part.Material = if active then Enum.Material.Neon else Enum.Material.SmoothPlastic

	local beacon = zone.part:FindFirstChild("Beacon")
	if beacon and beacon:IsA("BasePart") then
		beacon.Transparency = if active then visual.beaconTransparency else 1
	end
end

-- Ouvre `activeZonesPerRaid` zones au hasard, ferme les autres.
local function rotateActiveZones()
	local order = table.clone(zones)
	for index = #order, 2, -1 do
		local swap = math.random(index)
		order[index], order[swap] = order[swap], order[index]
	end

	local quota = math.clamp(Config.Extraction.activeZonesPerRaid, 0, #order)
	for index, zone in order do
		setActive(zone, index <= quota)
	end

	local open = {}
	for _, zone in zones do
		if zone.active then
			table.insert(open, zone.name)
		end
	end
	Signal.fire(ExtractionService.ZonesRotated, open)
	log:info(`zones ouvertes : {if #open == 0 then "aucune" else table.concat(open, ", ")}`)
end

-- Ferme TOUTES les sorties. Etat de depart d'une fenetre de contrat : le
-- joueur est largue, il ne repart pas quand il veut.
local function closeAllZones()
	for _, zone in zones do
		setActive(zone, false)
	end
	log:info("sorties verrouillees")
end

-- Retire un nouveau jeu de sorties. Appele par MatchService a chaque
-- redeploiement : garder les memes sorties d'une fenetre a l'autre rendrait
-- la carte apprise par coeur en trois parties.
function ExtractionService.RotateZones()
	if opened then
		rotateActiveZones()
	else
		closeAllZones()
	end
end

-- Ouvre les sorties pour la fenetre en cours. Appele une seule fois, quand
-- le delai d'ouverture est atteint.
function ExtractionService.OpenZones()
	if opened then
		return
	end
	opened = true
	rotateActiveZones()
end

-- Remet le verrou. Appele au redeploiement par MatchService.
function ExtractionService.LockZones()
	opened = false
	closeAllZones()
end

function ExtractionService.IsOpen(): boolean
	return opened
end

local function populate()
	folder = getFolder()
	local root = folder :: Folder

	for _, marker in root:GetChildren() do
		if marker:IsA("BasePart") then
			local radius = marker:GetAttribute("Radius")
			local holdTime = marker:GetAttribute("HoldTime")
			table.insert(zones, buildZone(
				marker.Name,
				marker.Position,
				if type(radius) == "number" then radius else Config.Extraction.defaultRadius,
				if type(holdTime) == "number" then holdTime else Config.Extraction.defaultHoldTime
			))
			marker:Destroy()
		end
	end

	if #zones == 0 then
		for _, def in Config.Extraction.fallbackZones do
			table.insert(zones, buildZone(def.name, def.position, def.radius, def.holdTime))
		end
		log:info(`aucun marqueur dans Workspace.ExtractionZones, {#zones} zones de secours posees`)
	end

	-- Au demarrage les sorties sont FERMEES : elles s'ouvrent au bout de
	-- Config.Extraction.openAfter, pilote par le tick.
	closeAllZones()
end

-- ------------------------------------------------------------ Mesures ----

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function zoneContaining(player: Player): Zone?
	local root = getRoot(player)
	if not root then
		return nil
	end

	for _, zone in zones do
		if (root.Position - zone.position).Magnitude <= zone.radius then
			return zone
		end
	end
	return nil
end

local function isRunValid(): boolean
	local context = ctx
	local matchService = context and context.Get("MatchService")
	if not matchService then
		-- Pas de MatchService : on refuse plutot que de supposer. Extraire
		-- hors d'un raid connu, c'est recompenser sans partie.
		return false
	end
	return (matchService :: any).IsRunning()
end

-- ------------------------------------------------------- Recompense ------

local function stackValue(stacks: { ItemStack }): number
	local total = 0
	for _, stack in stacks do
		local def = ItemDatabase.get(stack.id)
		if def then
			total += def.value * stack.quantity
		end
	end
	return total
end

local function moveToSafety(player: Player)
	local root = getRoot(player)
	if root then
		root.CFrame = CFrame.new(Config.Extraction.safePosition)
	end
	player:SetAttribute("Extracted", true)
end

local function grantReward(player: Player, zone: Zone)
	-- Le drapeau est pose AVANT toute recompense. Tout ce qui suit peut
	-- ceder, se dupliquer ou etre rejoue : rien ne repassera par ici.
	if extracted[player] then
		log:warn(`double extraction bloquee pour {player.Name}`)
		return
	end
	extracted[player] = true

	local context = ctx
	local inventoryService = context and context.Get("InventoryService")
	local economyService = context and context.Get("EconomyService")
	local analyticsService = context and context.Get("AnalyticsService")

	if not inventoryService or not economyService then
		log:error("InventoryService ou EconomyService indisponible : extraction non recompensee")
		return
	end

	local summary = (inventoryService :: any).ExtractToStash(player)
	local lootValue = stackValue(summary.moved)
	local reward = (economyService :: any).GrantExtractionReward(player, lootValue)
	local duration = math.floor(os.clock() - (runStartedAt[player] or os.clock()))

	if analyticsService then
		local threatService = context and context.Get("ThreatService")
		local threat = if threatService then math.floor((threatService :: any):GetThreat()) else 0

		;(analyticsService :: any).Track("RunExtracted", player, {
			zone = zone.name,
			lootValue = lootValue,
			credits = reward.credits,
			stacks = #summary.moved,
			duration = duration,
			threat = threat,
		})

		;(analyticsService :: any).TrackOnce("FirstExtraction", player, {
			zone = zone.name,
			lootValue = lootValue,
			credits = reward.credits,
		})

		-- Fin de l'entonnoir d'accueil. DEFINITION PROVISOIRE : la premiere
		-- extraction reussie tient lieu de tutoriel acheve tant qu'il n'y a
		-- pas de vrai tutoriel. Quand il existera, seul ce point d'appel
		-- bougera.
		;(analyticsService :: any).TrackOnce("TutorialCompleted", player, {
			trigger = "premiere_extraction",
			raids = 1,
		})
	end

	moveToSafety(player)

	fire("ExtractionCompleted", player, {
		zone = zone.name,
		lootValue = reward.lootValue,
		bonus = reward.bonus,
		credits = reward.credits,
		xpGained = reward.xpGained,
		level = reward.level,
		leveledUp = reward.leveledUp,
		moved = summary.moved,
		leftBehind = summary.leftBehind,
	})

	-- Le manifeste voyage AVEC la recompense : le rapport de fin doit
	-- pouvoir nommer ce qui est rentre, pas seulement en donner le prix.
	Signal.fire(ExtractionService.Completed, player, zone.name, reward, summary, duration)

	log:info(`{player.Name} extrait par {zone.name} : {reward.credits} credits`)
end

-- ---------------------------------------------------------------- Tick ---

local function stopSession(player: Player, reason: string)
	sessions[player] = nil
	fire("ExtractionCancelled", player, reason)
	Signal.fire(ExtractionService.Cancelled, player, reason)
end

local function tick(dt: number)
	local runValid = isRunValid()

	-- Ouverture des sorties au bout du delai. On lit l'horloge de MatchService
	-- plutot que de compter ici : deux compteurs du meme temps finiraient par
	-- diverger, et c'est MatchService qui fait autorite sur la fenetre.
	if not opened and runValid then
		local context = ctx
		local matchService = context and context.Get("MatchService")
		if matchService then
			local remaining = (matchService :: any).TimeRemaining()
			local elapsed = Config.Match.windowDuration - remaining
			if elapsed >= Config.Extraction.openAfter then
				ExtractionService.OpenZones()
				log:info(`sorties ouvertes apres {math.floor(elapsed)}s`)
			end
		end
	end

	for _, player in Players:GetPlayers() do
		if extracted[player] then
			continue
		end

		local session = sessions[player]
		local zone = zoneContaining(player)

		-- Entree dans une zone ouverte : on demarre.
		if not session then
			if zone and zone.active and runValid and isAlive(player) then
				sessions[player] = {
					zone = zone,
					progress = Extraction.begin(zone.name, zone.holdTime),
					lastPush = 0,
				}
				fire("ExtractionStarted", player, zone.name, zone.holdTime)
				log:info(`{player.Name} entame l'extraction en {zone.name}`)

				-- Une extraction en cours est bruyante et immobile : c'est
				-- le moment ou la carte doit reagir.
				local threatService = ctx and ctx.Get("ThreatService")
				if threatService then
					(threatService :: any):AddSource("EXTRACTION_STARTED")
				end
			end
			continue
		end

		local outcome, reason = Extraction.step(session.progress, dt, {
			-- On exige la meme zone : sortir d'une sortie pour entrer dans
			-- une autre ne doit pas conserver la progression acquise.
			inZone = zone ~= nil and zone.name == session.zone.name,
			alive = isAlive(player),
			zoneActive = session.zone.active,
			runValid = runValid,
		})

		if outcome == "completed" then
			grantReward(player, session.zone)
			sessions[player] = nil
		elseif outcome == "cancelled" then
			log:info(`{player.Name} : extraction annulee ({tostring(reason)})`)
			stopSession(player, tostring(reason))
		elseif outcome == "running" then
			session.lastPush += dt
			if session.lastPush >= Config.Extraction.progressInterval then
				session.lastPush = 0
				fire(
					"ExtractionProgress",
					player,
					session.zone.name,
					Extraction.fraction(session.progress),
					Extraction.remaining(session.progress)
				)
			end
		end
	end

	-- Un joueur parti en cours d'extraction laisse une session orpheline.
	for player in sessions do
		if not player.Parent then
			sessions[player] = nil
		end
	end
end

-- --------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local existing = ServerStorage:FindFirstChild("DebugExtraction")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugExtraction"
	bindable.Parent = ServerStorage

	-- "teleport" pose le joueur dans une zone ouverte, "status" rend l'etat
	-- courant, "reset" annule le drapeau d'extraction pour rejouer le cas.
	bindable.OnInvoke = function(action: any, argument: any): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "aucun joueur"
		end

		if action == "status" then
			local lines = {}
			for _, zone in zones do
				table.insert(lines, `{zone.name} : {if zone.active then "OUVERTE" else "fermee"} r={zone.radius} t={zone.holdTime}s`)
			end
			local session = sessions[player]
			table.insert(lines, `session : {if session then `{session.zone.name} {math.floor(Extraction.fraction(session.progress) * 100)}%` else "aucune"}`)
			table.insert(lines, `deja extrait : {tostring(extracted[player] == true)}`)
			return table.concat(lines, "\n")
		end

		if action == "teleport" then
			local target
			for _, zone in zones do
				if zone.active and (argument == nil or zone.name == argument) then
					target = zone
					break
				end
			end
			if not target then
				return "aucune zone ouverte correspondante"
			end
			local root = getRoot(player)
			if not root then
				return "pas de personnage"
			end
			root.CFrame = CFrame.new(target.position + Vector3.new(0, 3, 0))
			return `pose dans {target.name} (maintien {target.holdTime}s)`
		end

		if action == "reset" then
			ExtractionService.ResetPlayer(player)
			return "drapeau d'extraction efface"
		end

		return "actions : status | teleport [zone] | reset"
	end

	log:info("debug : ServerStorage.DebugExtraction:Invoke(\"status\"|\"teleport\"|\"reset\")")
end

-- -------------------------------------------------------- Cycle de vie ---

-- Efface tout ce qui est par-course chez un joueur. Appele au
-- redeploiement par MatchService, et par l'affordance de debug.
--
-- Sans lui, un joueur extrait avant la fermeture de la fenetre resterait
-- marque `Extracted` a la fenetre suivante : invulnerable, invisible pour
-- les ennemis, et incapable d'extraire a nouveau.
function ExtractionService.ResetPlayer(player: Player)
	extracted[player] = nil
	sessions[player] = nil
	player:SetAttribute("Extracted", nil)
end

-- Appele par PlayerService : c'est lui qui sait quand une course commence.
function ExtractionService.MarkRunStart(player: Player, at: number)
	runStartedAt[player] = at
end

function ExtractionService.GetRunStart(player: Player): number?
	return runStartedAt[player]
end

function ExtractionService.Init(context: ServiceContext)
	ctx = context
end

function ExtractionService.Start()
	populate()
	installDebug()

	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		extracted[player] = nil
		-- Sans cette ligne, la table gardait une entree par joueur ayant
		-- jamais rejoint, pour toute la duree du serveur.
		runStartedAt[player] = nil
	end))

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.Extraction.tickRate then
			return
		end
		local step = accumulator
		accumulator = 0
		tick(step)
	end)

	log:info(`pret — {#zones} zones, tick {Config.Extraction.tickRate}s`)
end

function ExtractionService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(sessions)
	table.clear(extracted)
	table.clear(zones)
end

return ExtractionService
