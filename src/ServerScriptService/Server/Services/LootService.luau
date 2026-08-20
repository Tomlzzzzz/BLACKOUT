--!strict
-- Conteneurs de butin physiques et distribution du loot.
--
-- Le tirage est integralement serveur. Le client ne fait que declencher un
-- ProximityPrompt ; tout le reste — quoi, combien, a quelle distance, a
-- quelle frequence — est decide et verifie ici.
--
-- Un conteneur garde son contenu entre deux interactions : le tirage a lieu
-- a la premiere ouverture, pas a chaque clic. Sinon un sac plein qui refuse
-- la moitie du butin ferait disparaitre le reste, et le joueur paierait sa
-- capacite deux fois.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local ItemDatabase = require(Shared.ItemDatabase)
local Loot = require(Shared.Loot)
local Logger = require(Shared.Utils.Logger)

type ServiceContext = Types.ServiceContext
type ItemStack = Types.ItemStack

type ContainerState = {
	kindId: string,
	part: BasePart,
	prompt: ProximityPrompt,
	contents: { ItemStack }?,
	busy: boolean,
	readyAt: number,
}

local LootService = {}

LootService.Name = "LootService"
LootService.Priority = 50

local log = Logger.new("LootService")
local ctx: ServiceContext?

local containers: { [BasePart]: ContainerState } = {}
local connections: { RBXScriptConnection } = {}
local folder: Folder?
local rng = Random.new()

-- Compteur de nommage. Deux conteneurs homonymes rendent les logs
-- inexploitables : impossible de savoir lequel a ete fouille.
local nextId = 0

local function getFolder(): Folder
	local existing = Workspace:FindFirstChild("LootSpawns")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local created = Instance.new("Folder")
	created.Name = "LootSpawns"
	created.Parent = Workspace
	return created
end

-- ------------------------------------------------------- Construction ----

local function buildContainer(kindId: string, position: Vector3): ContainerState?
	local kind = Loot.getContainerKind(kindId)
	if not kind then
		log:warn(`type de conteneur inconnu : {kindId}`)
		return nil
	end

	nextId += 1

	local part = Instance.new("Part")
	part.Name = `Container_{kindId}_{nextId}`
	part.Size = kind.size
	part.Position = position
	part.Color = kind.color
	part.Anchored = true
	part.Material = Enum.Material.Metal
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("LootKind", kindId)

	local prompt = Instance.new("ProximityPrompt")
	-- CLES de localisation, pas du texte : le prompt est lu par des clients
	-- qui peuvent etre dans des langues differentes. Le HUD traduit.
	prompt.ActionText = "prompt.search"
	prompt.ObjectText = kind.labelKey or "prompt.container"
	prompt.HoldDuration = 0.6
	-- La portee du prompt est un confort client : elle est contournable.
	-- La verification qui compte est celle faite dans onTriggered.
	prompt.MaxActivationDistance = kind.range
	prompt.RequiresLineOfSight = false
	-- Style personnalise : le HUD dessine son propre indicateur central,
	-- l'interface par defaut ferait doublon.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = part

	part.Parent = folder

	local state: ContainerState = {
		kindId = kindId,
		part = part,
		prompt = prompt,
		contents = nil,
		busy = false,
		readyAt = 0,
	}

	containers[part] = state
	return state
end

-- ------------------------------------------------------- Interaction ----

local function describe(stacks: { ItemStack }): string
	local parts = {}
	for _, stack in stacks do
		local def = ItemDatabase.get(stack.id)
		table.insert(parts, `{if def then def.name else stack.id} x{stack.quantity}`)
	end
	return if #parts == 0 then "(rien)" else table.concat(parts, ", ")
end

local function onTriggered(state: ContainerState, player: Player)
	-- Protection contre le double-declenchement : un ProximityPrompt peut
	-- etre retire deux fois en quelques millisecondes, et deux traitements
	-- concurrents videraient le conteneur en double.
	if state.busy then
		return
	end
	state.busy = true

	local function finish()
		state.busy = false
	end

	local kind = Loot.getContainerKind(state.kindId)
	if not kind then
		return finish()
	end

	if os.clock() < state.readyAt then
		return finish()
	end

	-- Un joueur extrait est sorti de la carte : EnemyService l'ignore deja,
	-- donc le laisser fouiller en ferait un pillard invulnerable capable de
	-- vider tous les conteneurs jusqu'a la fin du serveur.
	if player:GetAttribute("Extracted") == true then
		return finish()
	end

	-- Revalidation serveur de la distance. MaxActivationDistance est
	-- applique cote client et ne prouve rien : un client modifie declenche
	-- le prompt depuis l'autre bout de la carte.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return finish()
	end

	local distance = (root.Position - state.part.Position).Magnitude
	if distance > kind.range then
		log:warn(`{player.Name} a tente de fouiller a {math.floor(distance)} studs (max {kind.range})`)
		return finish()
	end

	local context = ctx
	local inventoryService = context and context.Get("InventoryService")
	if not inventoryService then
		log:error("InventoryService indisponible : butin non distribue")
		return finish()
	end

	-- Tirage a la premiere ouverture seulement.
	if not state.contents then
		state.contents = Loot.rollContainer(state.kindId, rng)
		log:info(`{state.part.Name} tire : {describe(state.contents :: { ItemStack })}`)
	end

	local contents = state.contents :: { ItemStack }
	local granted: { ItemStack } = {}
	local blocked = false

	for index = #contents, 1, -1 do
		local stack = contents[index]
		local result = (inventoryService :: any).Add(player, stack.id, stack.quantity)
		if result.ok then
			table.insert(granted, stack)
			table.remove(contents, index)
		elseif result.error == "OVER_CAPACITY" then
			-- Le reste demeure dans le conteneur : le joueur reviendra.
			blocked = true
		else
			log:warn(`{stack.id} x{stack.quantity} refuse : {tostring(result.error)}`)
			table.remove(contents, index)
		end
	end

	if #granted > 0 then
		log:info(`{player.Name} recupere {describe(granted)}`)

		local remotes = context and context.Remotes
		local remote = remotes and remotes:FindFirstChild("LootGranted")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireClient(player, granted)
		end

		-- Equipement automatique de la premiere arme ramassee. Sans
		-- interface d'inventaire, un joueur qui trouve un fusil et ne peut
		-- pas l'equiper a juste ramasse un objet lourd et inutile.
		local Weapons = require(Shared.Weapons)
		for _, stack in granted do
			if Weapons.isWeapon(stack.id) then
				local current = (inventoryService :: any).GetEquipped(player)
				if not current or not Weapons.isWeapon(current) then
					(inventoryService :: any).SetEquipped(player, stack.id)
					log:info(`{player.Name} equipe {stack.id}`)
				end
				break
			end
		end

		-- Statistique de butin : on compte les unites, pas les piles. Une
		-- pile de 58 munitions et une chaine en or ne representent pas le
		-- meme effort de fouille.
		local dataService = context and context.Get("DataService")
		local profile = dataService and (dataService :: any).GetProfile(player)
		if profile then
			local units = 0
			for _, stack in granted do
				units += stack.quantity
			end
			profile.Statistics.ItemsLooted += units
		end

		local analytics = context and context.Get("AnalyticsService")
		if analytics then
			local first = granted[1]
			local def = first and ItemDatabase.get(first.id)
			-- Le point-virgule est indispensable : sans lui, Luau lit
			-- `ItemDatabase.get(...)(analytics)` comme un appel de fonction.
			;(analytics :: any).TrackOnce("FirstLoot", player, {
				itemId = if first then first.id else "inconnu",
				rarity = if def then def.rarity else "inconnu",
				quantity = if first then first.quantity else 0,
			})
		end

		-- Fouiller fait du bruit, et emporter une piece rare en fait
		-- beaucoup plus. Les montants vivent dans ThreatConfig : on passe
		-- des identifiants de source, jamais des nombres.
		local threatService = context and context.Get("ThreatService")
		if threatService then
			(threatService :: any):AddSource("LOOT_PICKUP", #granted)
			for _, stack in granted do
				local def = ItemDatabase.get(stack.id)
				if def then
					(threatService :: any):AddMajorLoot(def.rarity, stack.quantity)
				end
			end
		end
	end

	if #contents == 0 then
		state.contents = nil
		state.readyAt = os.clock() + kind.cooldown
		state.prompt.Enabled = false

		task.delay(kind.cooldown, function()
			if containers[state.part] == state then
				state.prompt.Enabled = true
			end
		end)
	elseif blocked then
		log:info(`{player.Name} : sac plein, {#contents} pile(s) restent dans {state.part.Name}`)
	end

	finish()
end

local function wire(state: ContainerState)
	table.insert(connections, state.prompt.Triggered:Connect(function(player)
		onTriggered(state, player)
	end))
end

-- ---------------------------------------------------------- Peuplement ----

local function populate(): number
	local built = 0
	local root = folder :: Folder

	-- Marqueurs poses par un level designer : n'importe quel BasePart dans
	-- Workspace.LootSpawns, avec un attribut LootKind optionnel.
	for _, marker in root:GetChildren() do
		if marker:IsA("BasePart") and not containers[marker] then
			local kindId = marker:GetAttribute(Config.Loot.kindAttribute)
			local state = buildContainer(
				if type(kindId) == "string" then kindId else Config.Loot.defaultKind,
				marker.Position
			)
			if state then
				wire(state)
				built += 1
			end
			marker:Destroy()
		end
	end

	-- Aucun marqueur : on retombe sur les positions de secours, pour que le
	-- systeme reste demontrable sur une carte vide.
	if built == 0 then
		for _, spawn in Config.Loot.fallbackSpawns do
			local state = buildContainer(spawn.kind, spawn.position)
			if state then
				wire(state)
				built += 1
			end
		end
		log:info(`aucun marqueur dans Workspace.LootSpawns, {built} conteneurs de secours poses`)
	end

	return built
end

-- -------------------------------------------------------------- Debug ----

-- Commande de debug, Studio uniquement. Passe par un BindableFunction parce
-- qu'un require depuis la barre de commande rend une *copie* du module et
-- pas l'instance vivante : seul un Instance traverse la frontiere.
--
--   game.ServerStorage.DebugSpawnLoot:Invoke("Safe")
local function installDebugCommand()
	if not RunService:IsStudio() then
		return
	end

	local existing = ServerStorage:FindFirstChild("DebugSpawnLoot")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugSpawnLoot"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(kindId: any, offset: any): string
		local kind = if type(kindId) == "string" then kindId else "Crate"
		if not Loot.getContainerKind(kind) then
			return `type inconnu : {kind}`
		end

		local position = Vector3.new(0, 5, 0)
		local player = Players:GetPlayers()[1]
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			position = root.Position + (if typeof(offset) == "Vector3" then offset else Vector3.new(0, 0, -6))
		end

		local state = buildContainer(kind, position)
		if not state then
			return "echec de creation"
		end
		wire(state)

		local preview = Loot.rollContainer(kind, rng)
		return `{state.part.Name} pose en {math.floor(position.X)},{math.floor(position.Y)},{math.floor(position.Z)}`
			.. ` — un tirage d'exemple donnerait : {describe(preview)}`
	end

	-- Second point d'entree : declenche onTriggered directement, c'est-a-dire
	-- exactement le chemin de production. Il ne court-circuite que le routage
	-- d'input du moteur, qui n'est pas notre code et refuse d'etre pilote
	-- depuis un script apres une teleportation.
	local interactExisting = ServerStorage:FindFirstChild("DebugLootInteract")
	if interactExisting then
		interactExisting:Destroy()
	end

	local interact = Instance.new("BindableFunction")
	interact.Name = "DebugLootInteract"
	interact.Parent = ServerStorage

	interact.OnInvoke = function(containerName: any): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "aucun joueur"
		end

		for part, state in containers do
			if part.Name == containerName then
				local before = if state.contents then #state.contents else -1
				onTriggered(state, player)
				local after = if state.contents then #state.contents else -1
				return `{part.Name} : piles avant={before} apres={after},`
					.. ` prompt actif={state.prompt.Enabled},`
					.. ` cooldown restant={math.max(0, math.floor(state.readyAt - os.clock()))}s`
			end
		end

		return `conteneur introuvable : {tostring(containerName)}`
	end

	log:info("debug : ServerStorage.DebugSpawnLoot:Invoke(\"Crate\") / DebugLootInteract:Invoke(nom)")
end

-- ------------------------------------------------------- Cycle de vie ----

function LootService.Init(context: ServiceContext)
	ctx = context
	folder = getFolder()
end

function LootService.Start()
	local built = populate()
	installDebugCommand()
	log:info(`pret — {built} conteneurs`)
end

function LootService.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	for part in containers do
		part:Destroy()
	end
	table.clear(containers)
end

return LootService
