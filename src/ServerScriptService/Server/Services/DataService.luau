--!strict
-- Profils joueur persistants.
--
-- Seul module autorise a detenir les profils et a parler au DataStore. Les
-- regles (combien de credits, quelle courbe d'XP) appartiennent a
-- EconomyService : ce service range, il ne decide pas.
--
-- Aucune autorite client : rien ici n'est expose par un remote, et aucune
-- fonction n'accepte de valeur venant du client.
--
-- Le coffre est hydrate en objet Inventory vivant au chargement, et
-- deshydrate en liste de piles a la sauvegarde. La capacite n'est pas
-- persistee : elle vient de la configuration, pour rester retouchable.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Inventory = require(Shared.Inventory)
local Logger = require(Shared.Utils.Logger)

local Data = script.Parent.Parent.Data
local MemoryBackend = require(Data.MemoryBackend)
local Schema = require(Data.Schema)
local Store = require(Data.Store)

type ServiceContext = Types.ServiceContext
type PlayerProfile = Types.PlayerProfile

local DataService = {}

DataService.Name = "DataService"
DataService.Priority = 10

local log = Logger.new("DataService")
local ctx: ServiceContext?

local store: Store.Store
local persistent = false

local profiles: { [Player]: PlayerProfile } = {}
local stashes: { [Player]: Types.Inventory } = {}
local loading: { [Player]: boolean } = {}
local connections: { RBXScriptConnection } = {}
local autosaveAccumulator = 0
local lockAccumulator = 0
local heartbeat: RBXScriptConnection?

-- ------------------------------------------------------------- Backend ---

-- Les DataStore sont indisponibles en Studio sans acces aux services API.
-- Plutot que d'echouer joueur par joueur, on teste une fois et on bascule
-- sur la memoire en le disant fort : un serveur qui ne persiste pas doit
-- etre evident, pas silencieux.
local function pickBackend(): (any, boolean)
	local ok, result = pcall(function()
		local dataStore = DataStoreService:GetDataStore(Config.Data.storeName)
		dataStore:UpdateAsync("__probe", function(old)
			return old
		end)
		return dataStore
	end)

	if ok then
		return result, true
	end

	log:error(`DataStore indisponible ({result}) — repli en memoire, RIEN NE SERA CONSERVE`)
	return MemoryBackend.new(), false
end

-- ------------------------------------------------------------ Hydratation ---

local function hydrate(player: Player, profile: PlayerProfile)
	profiles[player] = profile

	local stash = Inventory.new(Constants.STASH_CAPACITY)
	for _, stack in profile.Inventory.Stash do
		if type(stack) == "table" and type(stack.id) == "string" and type(stack.quantity) == "number" then
			table.insert(stash.slots, { id = stack.id, quantity = stack.quantity })
		end
	end
	stashes[player] = stash
end

local function dehydrate(player: Player): PlayerProfile?
	local profile = profiles[player]
	local stash = stashes[player]
	if not profile then
		return nil
	end

	if stash then
		local slots: { Types.ItemStack } = {}
		for _, stack in stash.slots do
			table.insert(slots, { id = stack.id, quantity = stack.quantity })
		end
		profile.Inventory.Stash = slots
	end

	return profile
end

-- ------------------------------------------------------------------ API ---

function DataService.GetProfile(player: Player): PlayerProfile?
	return profiles[player]
end

-- Le coffre vivant. C'est cet objet que manipule InventoryService ; il est
-- recopie dans le profil au moment de la sauvegarde.
function DataService.GetStash(player: Player): Types.Inventory?
	return stashes[player]
end

function DataService.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Sauvegarde immediate, sans relacher le verrou. Utilisee par
-- MonetizationService : un achat ne doit jamais dependre de l'autosave.
function DataService.ForceSave(player: Player): boolean
	return DataService.SavePlayer(player, false)
end

function DataService.IsPersistent(): boolean
	return persistent
end

-- ------------------------------------------------------- Chargement ------

local function loadPlayer(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true

	local key = Store.keyFor(player.UserId)
	local result = Store.load(store, key)

	loading[player] = nil

	if not player.Parent then
		-- Parti pendant le chargement : on relache immediatement, sinon le
		-- verrou survivrait a la session.
		if result.ok then
			Store.save(store, key, result.profile, true)
		end
		return
	end

	if not result.ok then
		-- On refuse de donner un profil neuf : ecraserait la progression
		-- reelle a la premiere sauvegarde. Le joueur est ejecte avec un
		-- motif clair plutot que de jouer une session fantome.
		log:error(`chargement de {player.Name} impossible : {tostring(result.error)}`)
		player:Kick("Impossible de charger ta progression. Reessaie dans une minute.")
		return
	end

	hydrate(player, result.profile)

	if result.migrated > 0 then
		log:warn(`{player.Name} migre sur {result.migrated} version(s) -> v{result.profile.Version}`)
	end

	log:info(
		`{player.Name} charge — v{result.profile.Version}, {result.profile.Credits} credits,`
			.. ` niveau {result.profile.Level}, coffre {#result.profile.Inventory.Stash} pile(s)`
	)
end

function DataService.SavePlayer(player: Player, release: boolean): boolean
	local profile = dehydrate(player)
	if not profile then
		return false
	end

	local key = Store.keyFor(player.UserId)
	local ok, err = Store.save(store, key, profile, release)

	if not ok then
		log:error(`sauvegarde de {player.Name} echouee : {tostring(err)}`)
	elseif release then
		log:info(`{player.Name} sauvegarde et relache`)
	end

	return ok
end

local function releasePlayer(player: Player)
	DataService.SavePlayer(player, true)
	profiles[player] = nil
	stashes[player] = nil
end

-- --------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local existing = ServerStorage:FindFirstChild("DebugData")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugData"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: any): string
		local player = Players:GetPlayers()[1]
		if action == "status" then
			local lines = {
				`persistance : {if persistent then "DataStore" else "MEMOIRE (rien ne sera conserve)"}`,
				`chargements={store.stats.loads} sauvegardes={store.stats.saves}`
					.. ` reprises={store.stats.retries} migrations={store.stats.migrations}`
					.. ` conflits={store.stats.conflicts}`,
			}
			if player then
				local profile = profiles[player]
				if profile then
					table.insert(lines, `{player.Name} : v{profile.Version} {profile.Credits} cr`
						.. ` niveau {profile.Level} xp {profile.XP}`
						.. ` coffre {#(stashes[player] :: any).slots} pile(s)`)
				else
					table.insert(lines, `{player.Name} : aucun profil charge`)
				end
			end
			return table.concat(lines, "\n")
		end

		if action == "stats" and player then
			local profile = profiles[player]
			if not profile then
				return "aucun profil charge"
			end
			local lines = {}
			for _, key in { "Raids", "Extractions", "Deaths", "Kills", "CreditsEarned", "ItemsLooted", "Playtime" } do
				table.insert(lines, `{key} = {(profile.Statistics :: any)[key]}`)
			end
			return table.concat(lines, "\n")
		end

		if action == "save" and player then
			return if DataService.SavePlayer(player, false) then "sauvegarde effectuee" else "sauvegarde echouee"
		end

		return "actions : status | stats | save"
	end

	log:info("debug : ServerStorage.DebugData:Invoke(\"status\"|\"save\")")
end

-- --------------------------------------------------------- Cycle de vie ---

function DataService.Init(context: ServiceContext)
	ctx = context

	local backend, isPersistent = pickBackend()
	persistent = isPersistent
	store = Store.new(backend, game.JobId ~= "" and game.JobId or "studio")
end

function DataService.Start()
	installDebug()

	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		task.spawn(loadPlayer, player)
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(releasePlayer))

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		-- Rafraichissement du verrou de session.
		--
		-- Sans lui, le verrou expirait au bout de son TTL (90 s) alors que
		-- la session etait bien vivante : un autre serveur pouvait alors le
		-- reprendre, et toutes les sauvegardes suivantes de CELUI-CI
		-- etaient refusees. Le joueur continuait a jouer pendant que sa
		-- progression cessait silencieusement d'etre ecrite.
		lockAccumulator += dt
		if lockAccumulator >= Config.Data.session.refreshInterval then
			lockAccumulator = 0
			for _, player in Players:GetPlayers() do
				if profiles[player] then
					task.spawn(function()
						Store.refreshLock(store, Store.keyFor(player.UserId))
					end)
				end
			end
		end

		autosaveAccumulator += dt
		if autosaveAccumulator < Config.Data.autosaveInterval then
			return
		end
		autosaveAccumulator = 0

		for _, player in Players:GetPlayers() do
			if profiles[player] then
				task.spawn(DataService.SavePlayer, player, false)
			end
		end
	end)

	-- Fermeture du serveur : on sauvegarde tout le monde avant de rendre la
	-- main. Roblox accorde quelques secondes a BindToClose ; sans ca, la
	-- derniere session de chaque joueur est perdue a chaque redemarrage.
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			releasePlayer(player)
		end
	end)

	log:info(
		`pret — schema v{Schema.CURRENT_VERSION},`
			.. ` {if persistent then "DataStore " .. Config.Data.storeName else "MEMOIRE SEULE"}`
	)
end

function DataService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	for _, player in Players:GetPlayers() do
		releasePlayer(player)
	end
end

return DataService
