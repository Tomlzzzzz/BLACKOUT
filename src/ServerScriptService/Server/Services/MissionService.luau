--!strict
-- Contrats a objectifs.
--
-- Le service etait un talon : une seule fonction, CompleteMission, que
-- personne n'appelait. Il porte maintenant le contrat que la maquette du HUD
-- affiche en haut a gauche — trois objectifs, une progression, une prime.
--
-- POURQUOI ICI ET PAS DANS HandlerService
--
-- Le commanditaire PARLE des objectifs, il ne les tient pas. Separer les deux
-- evite qu'on se retrouve avec deux listes concurrentes a l'ecran : la
-- directive du commanditaire est devenue le premier objectif du contrat, et
-- HandlerService se contente de commenter ce que ce service decide.
--
-- Trois types d'objectif, et ils se completent sur des evenements reellement
-- emis par le jeu :
--   collect   InventoryService.ItemAdded
--   reach     echantillonnage de distance aux zones ouvertes
--   extract   ExtractionService.Completed

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type Contract = Types.Contract
type ContractObjective = Types.ContractObjective

local MissionService = {}

MissionService.Name = "MissionService"
MissionService.Priority = 80

-- Emis quand un objectif passe a l'etat rempli, et quand le contrat entier
-- l'est. HandlerService s'y abonne pour faire parler le commanditaire.
MissionService.ContractAssigned = Signal.new()
MissionService.ObjectiveCompleted = Signal.new()
MissionService.ContractCompleted = Signal.new()

local log = Logger.new("MissionService")
local ctx: ServiceContext?

local contracts: { [Player]: Contract } = {}
local subscriptions: { any } = {}
local connections: { RBXScriptConnection } = {}
local heartbeat: RBXScriptConnection?
local accumulator = 0

-- Cadence de verification des objectifs `reach`. La distance a une sortie ne
-- change pas assez vite pour justifier mieux.
local REACH_RATE = 0.5

local function service(name: string): any?
	local context = ctx
	return context and context.Get(name)
end

-- --------------------------------------------------------- Attribution ---

local function push(player: Player)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("ContractChanged")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, contracts[player])
	end
end

MissionService.Push = push

function MissionService.GetContract(player: Player): Contract?
	return contracts[player]
end

-- Tire un contrat pour ce joueur. Les definitions de config sont copiees en
-- profondeur : sans cela, la progression d'un joueur ecrirait dans la table
-- partagee et tous les autres la verraient.
function MissionService.Assign(player: Player, rng: ((number) -> number)?): Contract
	local pool = Config.Contracts.contracts
	local definition = pool[(rng or math.random)(#pool)]

	-- Les libelles sont des CLES, resolues par chaque client dans sa langue.
	-- Elles suivent la position de l'objectif : « contract.C001.obj1 ».
	local objectives: { ContractObjective } = {}
	for index, spec in definition.objectives do
		table.insert(objectives, {
			kind = spec.kind,
			labelKey = `contract.{definition.id}.obj{index}`,
			item = spec.item,
			quantity = spec.quantity,
			progress = 0,
			done = false,
		})
	end

	local contract: Contract = {
		id = definition.id,
		titleKey = `contract.{definition.id}.title`,
		subtitleKey = `contract.{definition.id}.subtitle`,
		objectives = objectives,
		reward = definition.reward,
		complete = false,
	}

	contracts[player] = contract
	push(player)
	Signal.fire(MissionService.ContractAssigned, player, contract)
	log:info(`{player.Name} recoit {contract.id} ({#objectives} objectifs)`)
	return contract
end

-- ---------------------------------------------------------- Progression --

-- Marque un objectif rempli et regarde si le contrat entier l'est. Toute
-- completion passe par ici : c'est le seul endroit qui verse la prime, donc
-- le seul endroit ou une double recompense pourrait naitre.
local function completeObjective(player: Player, contract: Contract, objective: ContractObjective)
	if objective.done then
		return
	end
	objective.done = true

	Signal.fire(MissionService.ObjectiveCompleted, player, contract, objective)
	log:info(`{player.Name} : objectif rempli — {objective.labelKey}`)

	for _, other in contract.objectives do
		if not other.done then
			push(player)
			return
		end
	end

	if contract.complete then
		return
	end
	contract.complete = true

	local economy = service("EconomyService")
	if economy then
		economy.AddCredits(player, contract.reward)
	end

	MissionService.CompleteMission(player, contract.id, contract.reward, 0)
	Signal.fire(MissionService.ContractCompleted, player, contract)
	push(player)
end

local function onItemAdded(player: Player, itemId: string, quantity: number)
	local contract = contracts[player]
	if not contract or contract.complete then
		return
	end

	local touched = false
	for _, objective in contract.objectives do
		if objective.kind == "collect" and objective.item == itemId and not objective.done then
			local target = objective.quantity or 1
			objective.progress = math.min(target, objective.progress + math.max(0, math.floor(quantity)))
			touched = true
			if objective.progress >= target then
				completeObjective(player, contract, objective)
			end
		end
	end

	if touched and not contract.complete then
		push(player)
	end
end

local function onExtracted(player: Player)
	local contract = contracts[player]
	if not contract then
		return
	end

	for _, objective in contract.objectives do
		if objective.kind == "extract" and not objective.done then
			objective.progress = 1
			completeObjective(player, contract, objective)
		end
	end
end

-- Objectif `reach` : le joueur doit s'etre approche d'une sortie OUVERTE.
-- On echantillonne plutot que d'attendre un evenement, parce qu'aucun
-- evenement n'existe pour « etre passe a cote ».
local function checkReach()
	local folder = Workspace:FindFirstChild("ExtractionZones")
	if not folder then
		return
	end

	for player, contract in contracts do
		if contract.complete then
			continue
		end

		local pending = nil
		for _, objective in contract.objectives do
			if objective.kind == "reach" and not objective.done then
				pending = objective
				break
			end
		end
		if not pending then
			continue
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Active") == true then
				if (part.Position - root.Position).Magnitude <= Config.Contracts.reachRadius then
					pending.progress = 1
					completeObjective(player, contract, pending)
					break
				end
			end
		end
	end
end

-- --------------------------------------------------------- Analytique ---

-- Point d'entree de l'achevement d'une mission. Il avait ete ecrit sans
-- appelant, en attendant que les missions existent ; elles existent, et il
-- est desormais appele depuis completeObjective.
function MissionService.CompleteMission(player: Player, missionId: string, reward: number, duration: number)
	local analytics = service("AnalyticsService")
	if analytics then
		analytics.Track("MissionCompleted", player, {
			missionId = missionId,
			reward = math.floor(reward),
			duration = math.floor(duration),
		})
	end

	log:info(`{player.Name} termine {missionId} (+{math.floor(reward)} cr)`)
end

-- -------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local ServerStorage = game:GetService("ServerStorage")
	local existing = ServerStorage:FindFirstChild("DebugContract")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugContract"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: string?, argument: string?): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "aucun joueur"
		end

		if action == "assign" then
			local contract = MissionService.Assign(player)
			return `attribue : {contract.id}`
		end

		if action == "complete" then
			local contract = contracts[player]
			if not contract then
				return "aucun contrat"
			end
			local index = tonumber(argument or "1") or 1
			local objective = contract.objectives[index]
			if not objective then
				return `objectif {index} inexistant`
			end
			objective.progress = objective.quantity or 1
			completeObjective(player, contract, objective)
			return `objectif {index} force : {objective.label}`
		end

		local contract = contracts[player]
		if not contract then
			return "aucun contrat"
		end

		local lines = { `{contract.id} (prime {contract.reward})` }
		for index, objective in contract.objectives do
			table.insert(
				lines,
				string.format(
					"  %d %-32s %s %s",
					index,
					objective.labelKey,
					if objective.quantity then `{objective.progress}/{objective.quantity}` else "",
					if objective.done then "OK" else ""
				)
			)
		end
		table.insert(lines, "actions : status | assign | complete <n>")
		return table.concat(lines, "\n")
	end

	log:info('debug : ServerStorage.DebugContract:Invoke("status"|"assign"|"complete <n>")')
end

-- -------------------------------------------------------- Cycle de vie ---

function MissionService.Init(context: ServiceContext)
	ctx = context
end

function MissionService.Start()
	local inventory = service("InventoryService")
	local extraction = service("ExtractionService")
	local match = service("MatchService")

	if inventory then
		table.insert(subscriptions, Signal.connect(inventory.ItemAdded, onItemAdded))
	end

	if extraction then
		table.insert(subscriptions, Signal.connect(extraction.Completed, onExtracted))
	end

	if match then
		-- Nouvelle fenetre, nouveau contrat. Sans cela le second raid
		-- reutiliserait un contrat deja rempli.
		table.insert(
			subscriptions,
			Signal.connect(match.Redeployed, function()
				for _, player in Players:GetPlayers() do
					MissionService.Assign(player)
				end
			end)
		)
	end

	table.insert(
		connections,
		Players.PlayerAdded:Connect(function(player)
			MissionService.Assign(player)
		end)
	)

	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			contracts[player] = nil
		end)
	)

	for _, player in Players:GetPlayers() do
		MissionService.Assign(player)
	end

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < REACH_RATE then
			return
		end
		accumulator = 0
		local ok, err = pcall(checkReach)
		if not ok then
			log:error(`checkReach a leve -> {err}`)
		end
	end)

	installDebug()
	log:info(`pret — {#Config.Contracts.contracts} contrats au catalogue`)
end

function MissionService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, subscription in subscriptions do
		Signal.disconnect(subscription)
	end
	table.clear(subscriptions)
	table.clear(contracts)
	Signal.clear(MissionService.ContractAssigned)
	Signal.clear(MissionService.ObjectiveCompleted)
	Signal.clear(MissionService.ContractCompleted)
end

return MissionService
