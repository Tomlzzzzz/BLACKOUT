--!strict
-- Point d'entree client. Meme contrat que le Bootstrap serveur : les
-- ModuleScripts de Controllers/ sont charges, trie par Priority, Init puis
-- Start. Aucun controller n'existe encore : le boucle tourne a vide sans
-- rien casser.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)

type Service = Types.Service
type ServiceContext = Types.ServiceContext

local log = Logger.new("Client")
local registry: { [string]: Service } = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
local localPlayer = Players.LocalPlayer

local context: ServiceContext = {
	Get = function(name: string): Service?
		return registry[name]
	end,
	Remotes = remotes,
}

local controllers: { Service } = {}

for _, module in script.Parent.Controllers:GetChildren() do
	if not module:IsA("ModuleScript") then
		continue
	end

	local ok, result = pcall(require, module)
	if not ok then
		log:error(`{module.Name} : require a echoue -> {result}`)
		continue
	end

	local controller = result :: Service
	controller.Name = controller.Name or module.Name
	controller.Priority = controller.Priority or 100
	table.insert(controllers, controller)
end

table.sort(controllers, function(a, b)
	return (a.Priority :: number) < (b.Priority :: number)
end)

for _, controller in controllers do
	registry[controller.Name] = controller
	if controller.Init then
		local ok, err = pcall(controller.Init, context)
		if not ok then
			log:error(`{controller.Name}.Init a echoue -> {err}`)
			registry[controller.Name] = nil
		end
	end
end

for _, controller in controllers do
	if registry[controller.Name] and controller.Start then
		local ok, err = pcall(controller.Start)
		if not ok then
			log:error(`{controller.Name}.Start a echoue -> {err}`)
			registry[controller.Name] = nil
		end
	end
end

log:info(`{#controllers} controllers demarres pour {localPlayer.Name}`)
