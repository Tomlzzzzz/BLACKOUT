--!strict
-- Sortie definitive du raid, et vue spectateur.
--
-- REGLE DE JEU : ON NE REVIENT PAS.
--
-- Un actif mort ne reapparait pas. Sa fenetre de contrat est terminee — il
-- ne rejoue qu'au redeploiement suivant, comme celui qui s'est extrait. Sans
-- cette regle, mourir ne coute que le sac et la mort cesse d'etre une
-- decision : on repart, on recommence, la menace n'a plus de sens.
--
-- Ce que ca implique techniquement : `Players.CharacterAutoLoads` est coupe
-- (voir PlayerService), et PERSONNE n'appelle LoadCharacter en dehors du
-- redeploiement.
--
-- CE QUE VOIT LE JOUEUR SORTI
--
-- S'il reste des coequipiers en zone : leur flux, en camera de surveillance,
-- degrade. C'est la meme idee que le reste du jeu — on ne lui rend pas la
-- main, on le fait passer de l'autre cote de l'ecran, du cote de ceux qui
-- regardent.
--
-- S'il est seul : aucun signal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Spectate = require(Shared.Spectate)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext

local SpectatorService = {}

SpectatorService.Name = "SpectatorService"

-- Apres DebriefService : le rapport part en premier, la bascule en vue
-- spectateur ensuite. L'ordre inverse afficherait le flux d'un coequipier
-- sous le rapport, ce qui donne l'impression que le rapport concerne l'autre.
SpectatorService.Priority = 95

local log = Logger.new("Spectator")
local ctx: ServiceContext?
local connections: { RBXScriptConnection } = {}
local signalConnections: { any } = {}

-- Actifs sortis du raid, et pourquoi. Videe au redeploiement.
local out: { [Player]: string } = {}

local function service(name: string): any?
	local context = ctx
	return context and context.Get(name)
end

-- ------------------------------------------------------------- Etat -----

-- Un joueur est-il encore debout, en zone ?
local function isAlive(player: Player): boolean
	if out[player] then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and (humanoid :: Humanoid).Health > 0
end

local function entries(): { Spectate.Entry }
	local list: { Spectate.Entry } = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, {
			userId = player.UserId,
			name = player.Name,
			alive = isAlive(player),
			extracted = player:GetAttribute("Extracted") == true,
		})
	end
	return list
end

local function push(player: Player)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("SpectateChanged")
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end

	local reason = out[player]
	local state: Types.SpectateState = {
		active = reason ~= nil,
		reason = reason or "",
		targets = if reason then Spectate.targets(entries(), player.UserId) else {},
	}

	remote:FireClient(player, state)
end

-- Rediffuse a TOUS les sortis, pas seulement au dernier.
--
-- Quand quelqu'un meurt, la liste des regardables retrecit pour tout le
-- monde. Ne prevenir que le nouveau mort laisserait les autres braques sur
-- une cible qui n'existe plus.
local function pushAll()
	for player in out do
		if player.Parent then
			push(player)
		end
	end
end

local function markOut(player: Player, reason: string)
	if out[player] == reason then
		return
	end
	out[player] = reason
	log:info(`{player.Name} sort du raid ({reason})`)
	pushAll()
end

function SpectatorService.IsOut(player: Player): boolean
	return out[player] ~= nil
end

-- ---------------------------------------------------------- Abonnements --

local function bindSignals()
	local playerService = service("PlayerService")
	local extraction = service("ExtractionService")
	local match = service("MatchService")

	local function subscribe(owner: any?, name: string, handler: (...any) -> ())
		if not owner then
			log:warn(`service absent, signal {name} non branche`)
			return
		end
		local signal = (owner :: any)[name]
		if not signal then
			log:warn(`signal absent : {name}`)
			return
		end
		table.insert(signalConnections, Signal.connect(signal, handler))
	end

	subscribe(playerService, "Died", function(player: Player)
		markOut(player, "KIA")
	end)

	subscribe(extraction, "Completed", function(player: Player)
		markOut(player, "EXTRACTED")
	end)

	-- Nouvelle fenetre de contrat : tout le monde revient. C'est le SEUL
	-- chemin de retour en jeu.
	subscribe(match, "Redeployed", function()
		local returning = {}
		for player in out do
			table.insert(returning, player)
		end
		table.clear(out)

		for _, player in returning do
			if player.Parent then
				push(player)
			end
		end
		log:info(`redeploiement : {#returning} actif(s) de retour`)
	end)
end

-- --------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local ServerStorage = game:GetService("ServerStorage")

	local existing = ServerStorage:FindFirstChild("DebugSpectate")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugSpectate"
	bindable.Parent = ServerStorage

	-- Tester la vue spectateur demande normalement deux joueurs et une mort.
	-- « force » bascule le premier joueur sans le tuer, ce qui permet de
	-- regarder l'ecran ; « clear » le fait revenir.
	bindable.OnInvoke = function(action: string?): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "aucun joueur"
		end

		if action == "force" then
			markOut(player, "KIA")
			return `{player.Name} bascule en spectateur`
		end

		if action == "clear" then
			out[player] = nil
			push(player)
			return `{player.Name} rendu au jeu`
		end

		local lines = { "actifs :" }
		for _, other in Players:GetPlayers() do
			table.insert(
				lines,
				string.format(
					"  %-18s %-10s vivant=%s extrait=%s",
					other.Name,
					out[other] or "-",
					tostring(isAlive(other)),
					tostring(other:GetAttribute("Extracted") == true)
				)
			)
		end
		table.insert(lines, "actions : status | force | clear")
		return table.concat(lines, "\n")
	end

	log:info('debug : ServerStorage.DebugSpectate:Invoke("status"|"force"|"clear")')
end

-- -------------------------------------------------------- Cycle de vie ---

function SpectatorService.Init(context: ServiceContext)
	ctx = context
end

function SpectatorService.Start()
	bindSignals()

	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			if out[player] then
				out[player] = nil
				pushAll()
			end
		end)
	)

	-- Un joueur qui arrive en cours de partie doit recevoir un etat, ne
	-- serait-ce que pour savoir qu'il n'est PAS spectateur.
	table.insert(
		connections,
		Players.PlayerAdded:Connect(function(player)
			task.defer(push, player)
		end)
	)

	installDebug()
	log:info("pret — la mort est definitive jusqu'au redeploiement")
end

function SpectatorService.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	for _, connection in signalConnections do
		Signal.disconnect(connection)
	end
	table.clear(signalConnections)
	table.clear(out)
end

return SpectatorService
