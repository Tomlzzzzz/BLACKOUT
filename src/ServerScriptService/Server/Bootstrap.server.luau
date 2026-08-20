--!strict
-- Point d'entree serveur.
--
-- Charge tous les ModuleScripts de Services/, les trie par Priority
-- croissante, appelle Init sur tous, puis Start sur tous. Un service qui
-- explose est retire du registre et journalise : le boot continue sans lui,
-- plutot que de laisser le serveur a moitie demarre sans le dire.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)

type Service = Types.Service
type ServiceContext = Types.ServiceContext

local log = Logger.new("Bootstrap")
local registry: { [string]: Service } = {}

local function buildRemotes(): Folder
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	for name, className in Constants.REMOTES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end

	return folder :: Folder
end

local function collectServices(): { Service }
	local services: { Service } = {}

	for _, module in script.Parent.Services:GetChildren() do
		if not module:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, module)
		if not ok then
			log:error(`{module.Name} : require a echoue -> {result}`)
			continue
		end

		local service = result :: Service
		service.Name = service.Name or module.Name
		service.Priority = service.Priority or 100
		table.insert(services, service)
	end

	table.sort(services, function(a, b)
		return (a.Priority :: number) < (b.Priority :: number)
	end)

	return services
end

local remotes = buildRemotes()

local context: ServiceContext = {
	Get = function(name: string): Service?
		return registry[name]
	end,
	Remotes = remotes,
}

local services = collectServices()

-- Phase 1 : Init. Chaque service prepare son etat interne et s'enregistre.
-- Interdiction d'appeler un autre service ici : l'ordre n'est garanti que
-- par Priority, et les dependances croisees se resolvent en phase 2.
for _, service in services do
	registry[service.Name] = service

	if service.Init then
		local ok, err = pcall(service.Init, context)
		if not ok then
			log:error(`{service.Name}.Init a echoue -> {err}`)
			registry[service.Name] = nil
		end
	end
end

-- Phase 2 : Start. Tout le monde est enregistre, ctx.Get repond.
for _, service in services do
	if registry[service.Name] == nil then
		continue
	end

	if service.Start then
		local ok, err = pcall(service.Start)
		if not ok then
			log:error(`{service.Name}.Start a echoue -> {err}`)
			registry[service.Name] = nil
		end
	end
end

local loaded = 0
for _ in registry do
	loaded += 1
end

log:info(`{loaded}/{#services} services demarres`)

game:BindToClose(function()
	for _, service in services do
		if registry[service.Name] and service.Stop then
			pcall(service.Stop)
		end
	end
end)
