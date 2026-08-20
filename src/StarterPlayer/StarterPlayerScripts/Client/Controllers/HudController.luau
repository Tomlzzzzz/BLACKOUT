--!strict
-- Controller du HUD.
--
-- Volontairement mince : il ne fait que respecter le contrat Init/Start/Stop
-- du Bootstrap et deleguer a UI/HUD/HUDController, qui monte les widgets et
-- les cable.
--
-- Toute la presentation vit dans UI/HUD/. Aucune logique de jeu ici, aucune
-- decision : le HUD lit un etat replique et l'affiche.
--
-- POURQUOI Heartbeat ET PAS RenderStepped
--
-- RenderStepped ne se declenche que si le client rend effectivement une
-- image : des que la fenetre Studio affiche la vue serveur, il ne part
-- jamais et toute l'animation du HUD se fige sans lever la moindre erreur.
-- Mesure : 0 image contre 60 Heartbeat sur la meme seconde.
--
-- Interpoler des opacites n'a aucun besoin de s'executer avant le rendu ;
-- RenderStepped n'est indispensable que pour manipuler la camera, ce que
-- fait CameraController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)

local Hud = require(script.Parent.Parent.UI.HUD.HUDController)

type ServiceContext = Types.ServiceContext

local HudController = {}

HudController.Name = "HudController"
HudController.Priority = 10

local log = Logger.new("Hud")
local player = Players.LocalPlayer

local hud: Hud.Hud? = nil
local connections: { RBXScriptConnection } = {}
local render: RBXScriptConnection?

function HudController.Init(context: ServiceContext) end

function HudController.Start()
	local playerGui = player:WaitForChild("PlayerGui")

	hud = Hud.mount(playerGui :: PlayerGui)
	local current = hud :: Hud.Hud

	-- Les abonnements avant toute chose : les RemoteEvent sans ecouteur sont
	-- mis en file par Roblox et delivres d'un coup a la connexion.
	connections = Hud.bind(current)
	Hud.bindInput(current)

	-- Allumage du terminal. Rejoue a chaque apparition : reprendre le controle
	-- d'un corps neuf, c'est rallumer l'equipement.
	Hud.boot(current)
	table.insert(
		connections,
		player.CharacterAdded:Connect(function()
			Hud.boot(current)
		end)
	)

	-- Boucle gardee : une erreur dans `step` se produirait a chaque image et
	-- noierait la console. On la signale une fois et on s'arrete, ce qui rend
	-- le defaut lisible au lieu de le rendre bruyant.
	local reported = false
	local frames = 0

	render = RunService.Heartbeat:Connect(function(dt)
		frames += 1
		local ok, err = pcall(Hud.step, current, dt)
		if not ok and not reported then
			reported = true
			log:error(`step a leve a l'image {frames} : {tostring(err)}`)
		end
	end)

	log:info("pret")
end

function HudController.Stop()
	if render then
		render:Disconnect()
		render = nil
	end

	Hud.unbindInput()

	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	local current = hud
	if current then
		Hud.destroy(current)
		hud = nil
	end
end

return HudController
