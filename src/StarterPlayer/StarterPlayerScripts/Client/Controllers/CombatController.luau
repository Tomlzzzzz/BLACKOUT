--!strict
-- Entrees de tir.
--
-- Ce controller n'inflige rien et ne decide rien : il envoie une intention
-- (origine, direction visee) et affiche le retour du serveur. La balle, la
-- dispersion, la portee et les degats sont decides serveur.
--
-- Il n'y a donc rien a tricher ici. Un client modifie qui enverrait mille
-- intentions par seconde se ferait refuser par la cadence, le chargeur et
-- l'anti-rejeu, tous appliques cote serveur.
--
-- Mobile : ContextActionService cree automatiquement un bouton tactile pour
-- les deux actions, sans code de placement a maintenir.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Weapons = require(Shared.Weapons)
local Logger = require(Shared.Utils.Logger)

type ServiceContext = Types.ServiceContext

local CombatController = {}

CombatController.Name = "CombatController"
CombatController.Priority = 20

local log = Logger.new("Combat")
local player = Players.LocalPlayer

local remotes: Folder
local requestFire: RemoteEvent?
local requestReload: RemoteEvent?

local connections: { RBXScriptConnection } = {}
local firing = false
local nextRequestId = 0
local currentWeapon: string? = nil

-- Identifiants croissants : le serveur les refuse en double, ce qui neutralise
-- le rejeu d'un paquet capture.
local function nextId(): number
	nextRequestId += 1
	return nextRequestId
end

local function aim(): (Vector3?, Vector3?)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil, nil
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end

	-- On vise depuis la camera, on tire depuis la tete : le serveur
	-- revalide de toute facon l'origine contre la position reelle.
	return head.Position, camera.CFrame.LookVector
end

local function shoot()
	local remote = requestFire
	if not remote then
		return
	end

	local origin, direction = aim()
	if not origin or not direction then
		return
	end

	remote:FireServer(origin, direction, nextId())
end

-- Tir continu tant que le bouton est maintenu. La cadence reelle est celle
-- de l'arme, appliquee serveur ; on echantillonne un peu plus vite pour ne
-- pas perdre de tirs a cause du pas de boucle.
local function fireLoop()
	while firing do
		shoot()
		task.wait(0.05)
	end
end

local function onFireAction(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		if not firing then
			firing = true
			task.spawn(fireLoop)
		end
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		firing = false
	end
	return Enum.ContextActionResult.Sink
end

local function onReloadAction(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin and requestReload then
		requestReload:FireServer(nextId())
	end
	return Enum.ContextActionResult.Sink
end

function CombatController.Init(context: ServiceContext) end

function CombatController.Start()
	remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	requestFire = remotes:FindFirstChild("RequestFire") :: RemoteEvent?
	requestReload = remotes:FindFirstChild("RequestReload") :: RemoteEvent?

	if not requestFire or not requestReload then
		log:warn("remotes de tir absents, controller inactif")
		return
	end

	ContextActionService:BindAction("BlackoutFire", onFireAction, true, Enum.UserInputType.MouseButton1)
	ContextActionService:SetTitle("BlackoutFire", "TIR")
	ContextActionService:SetPosition("BlackoutFire", UDim2.new(1, -140, 1, -180))

	ContextActionService:BindAction("BlackoutReload", onReloadAction, true, Enum.KeyCode.R)
	ContextActionService:SetTitle("BlackoutReload", "R")
	ContextActionService:SetPosition("BlackoutReload", UDim2.new(1, -140, 1, -290))

	local stateRemote = remotes:FindFirstChild("WeaponStateChanged")
	if stateRemote and stateRemote:IsA("RemoteEvent") then
		table.insert(connections, stateRemote.OnClientEvent:Connect(function(itemId: string?)
			currentWeapon = itemId
		end))
	end

	-- Le tir s'arrete a la mort, sinon la boucle continue a envoyer des
	-- intentions que le serveur refusera une par une.
	table.insert(connections, player.CharacterAdded:Connect(function()
		firing = false
	end))

	log:info(`pret — {if UserInputService.TouchEnabled then "tactile" else "souris"}`)
end

function CombatController.Stop()
	firing = false
	ContextActionService:UnbindAction("BlackoutFire")
	ContextActionService:UnbindAction("BlackoutReload")
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return CombatController
