--!strict
-- Tir, degats aux ennemis, munitions.
--
-- AUTORITE — le serveur tire, le client vise.
-- Le client envoie une INTENTION : une origine et une direction. Le serveur
-- refait son propre raycast et n'accepte aucune revendication de touche.
-- C'est plus couteux en latence qu'un raycast client valide apres coup,
-- mais c'est la seule forme ou « ne jamais faire confiance au client » est
-- litteralement vraie plutot que approximativement.
--
-- Quatre verifications avant qu'une balle existe :
--   1. le joueur tient bien cette arme (emplacement equipe, cote serveur)
--   2. la cadence et le chargeur le permettent (Shared.Weapons, pur)
--   3. l'origine annoncee est proche du personnage reel
--   4. la requete n'est pas un rejeu
--
-- Les degats partent ensuite par EnemyService.DamageEnemy, qui attribue le
-- kill. Aucun autre chemin n'existe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local RequestGuard = require(Shared.Utils.RequestGuard)

type ServiceContext = Types.ServiceContext
type WeaponState = Types.WeaponState

local CombatService = {}

CombatService.Name = "CombatService"
CombatService.Priority = 55

local log = Logger.new("CombatService")
local ctx: ServiceContext?

local states: { [Player]: WeaponState } = {}
local guards: { [Player]: RequestGuard.Guard } = {}
local connections: { RBXScriptConnection } = {}
local rayParams = RaycastParams.new()
local rng = Random.new()

local function fire(remoteName: string, player: Player, ...: any)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, ...)
	end
end

-- Emis a chaque tir valide. Sert au commanditaire pour relayer « coups de
-- feu releves » aux AUTRES joueurs : entendre tirer sans savoir ou est la
-- moitie de l'information en zone.
CombatService.ShotFired = Signal.new()

local function broadcastShot(player: Player, origin: Vector3, hit: Vector3)
	Signal.fire(CombatService.ShotFired, player, origin)

	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("ShotFired")
	if remote and remote:IsA("RemoteEvent") then
		-- Diffuse a tous SAUF au tireur : lui a deja affiche sa propre
		-- trace localement, la lui renvoyer ferait double.
		for _, other in Players:GetPlayers() do
			if other ~= player then
				remote:FireClient(other, origin, hit)
			end
		end
	end
end

-- ------------------------------------------------------------ Etat arme ---

local function equippedWeaponId(player: Player): string?
	local context = ctx
	local inventoryService = context and context.Get("InventoryService")
	local equipped = inventoryService and (inventoryService :: any).GetEquipped(player)

	if equipped and Weapons.isWeapon(equipped) then
		return equipped
	end

	-- Arme de secours : personne ne doit se retrouver totalement desarme
	-- face a un crawler, sinon mourir n'est plus une decision mais une
	-- fatalite.
	return Config.Weapons.defaultWeapon
end

local function pushState(player: Player)
	local state = states[player]
	if not state then
		fire("WeaponStateChanged", player, nil, 0, 0, false)
		return
	end

	local definition = Weapons.definition(state.itemId)
	fire(
		"WeaponStateChanged",
		player,
		state.itemId,
		state.ammoInMagazine,
		if definition then definition.magazine else 0,
		Weapons.isReloading(state, os.clock())
	)
end

-- Reconstruit l'etat quand l'arme equipee change. Le chargeur repart plein :
-- suivre le chargeur de chaque arme possedee est un raffinement qui n'a pas
-- sa place dans une premiere version.
local function syncWeapon(player: Player)
	local itemId = equippedWeaponId(player)
	local current = states[player]

	if not itemId then
		states[player] = nil
		pushState(player)
		return
	end

	if current and current.itemId == itemId then
		return
	end

	states[player] = Weapons.new(itemId, os.clock())
	pushState(player)
end

-- --------------------------------------------------------------- Tir -----

local function characterOrigin(player: Player): Vector3?
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end

	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Applique la dispersion cote serveur. La confier au client reviendrait a
-- le laisser choisir de ne pas disperser.
local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end

	local radians = math.rad(degrees)
	local angle = rng:NextNumber(0, math.pi * 2)
	local magnitude = rng:NextNumber(0, radians)

	local perpendicular = direction:Cross(Vector3.new(0, 1, 0))
	if perpendicular.Magnitude < 0.001 then
		perpendicular = direction:Cross(Vector3.new(1, 0, 0))
	end
	perpendicular = perpendicular.Unit

	local rotated = CFrame.fromAxisAngle(perpendicular, magnitude)
		* CFrame.fromAxisAngle(direction.Unit, angle)
	return (rotated * direction.Unit)
end

local function onFireRequested(player: Player, origin: any, direction: any, requestId: any)
	local guard = guards[player]
	local state = states[player]
	if not guard or not state then
		return
	end

	-- Frontiere client : tout est hostile jusqu'a verification.
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or type(requestId) ~= "number" then
		return
	end
	if direction.Magnitude < 0.001 or direction.Magnitude ~= direction.Magnitude then
		return
	end
	if not RequestGuard.accept(guard, requestId) then
		return
	end
	if not isAlive(player) or player:GetAttribute("Extracted") == true then
		return
	end

	local now = os.clock()
	Weapons.finishReload(state, now)

	-- Origine : on tolere la derive due a la latence, pas un tir depuis
	-- l'autre bout de la carte.
	local realOrigin = characterOrigin(player)
	if not realOrigin then
		return
	end
	if (origin - realOrigin).Magnitude > Config.Weapons.validation.maxOriginDrift then
		log:warn(`{player.Name} : origine de tir a {math.floor((origin - realOrigin).Magnitude)} studs de son personnage`)
		return
	end

	local decision = Weapons.fire(state, now)
	if not decision.ok then
		pushState(player)
		return
	end

	local definition = Weapons.definition(state.itemId)
	if not definition then
		return
	end

	-- Le raycast part de la position REELLE, pas de celle annoncee.
	local aim = spreadDirection(direction.Unit, definition.spread)
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { player.Character :: Instance }

	local result = Workspace:Raycast(realOrigin, aim * definition.range, rayParams)
	local impact = if result then result.Position else realOrigin + aim * definition.range

	local context = ctx
	local threatService = context and context.Get("ThreatService")
	if threatService then
		(threatService :: any):AddSource("GUNSHOT")
	end

	if result then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		local enemyService = context and context.Get("EnemyService")
		if model and enemyService then
			local landed, killed = (enemyService :: any).DamageEnemy(model, definition.damage, player)

			-- Retour visuel. Emis apres coup et uniquement au tireur : c'est
			-- une confirmation de ce que le serveur vient de decider, pas une
			-- revendication du client.
			if landed then
				local feedback = context and context.Remotes:FindFirstChild("CombatFeedback")
				if feedback and feedback:IsA("RemoteEvent") then
					feedback:FireClient(player, if killed then "kill" else "hit", definition.damage)
				end
			end
		end
	end

	broadcastShot(player, realOrigin, impact)
	pushState(player)
end

-- ---------------------------------------------------------- Rechargement --

local function onReloadRequested(player: Player, requestId: any)
	local guard = guards[player]
	local state = states[player]
	if not guard or not state or type(requestId) ~= "number" then
		return
	end
	if not RequestGuard.accept(guard, requestId) then
		return
	end

	local now = os.clock()
	Weapons.finishReload(state, now)

	local definition = Weapons.definition(state.itemId)
	local context = ctx
	local inventoryService = context and context.Get("InventoryService")
	if not definition or not inventoryService then
		return
	end

	-- Les munitions viennent du SAC DE RAID, jamais du coffre : recharger
	-- depuis son stockage a l'abri viderait l'interet d'en emporter.
	local contents = (inventoryService :: any).GetContents(player)
	local available = 0
	for _, item in contents do
		if item.id == definition.ammoId then
			available += item.quantity
		end
	end

	local started, taken = Weapons.beginReload(state, now, available)
	if not started then
		pushState(player)
		return
	end

	-- Retrait immediat. Si le retrait echoue, on annule : mieux vaut un
	-- rechargement rate qu'un chargeur rempli avec des balles qu'on n'avait
	-- pas.
	local removal = (inventoryService :: any).Remove(player, definition.ammoId, taken)
	if not removal.ok then
		Weapons.cancelReload(state)
		pushState(player)
		return
	end

	pushState(player)

	task.delay(definition.reloadTime, function()
		if states[player] == state and Weapons.finishReload(state, os.clock()) then
			pushState(player)
		end
	end)
end

-- ---------------------------------------------------------------- API ----

function CombatService.GetWeapon(player: Player): string?
	local state = states[player]
	return if state then state.itemId else nil
end

function CombatService.GetAmmo(player: Player): number
	local state = states[player]
	return if state then state.ammoInMagazine else 0
end

-- Appelee par InventoryService quand l'equipement change.
function CombatService.OnEquipmentChanged(player: Player)
	syncWeapon(player)
end

-- ---------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local existing = ServerStorage:FindFirstChild("DebugCombat")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugCombat"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: any, argument: any): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "aucun joueur"
		end

		if action == "status" then
			local state = states[player]
			if not state then
				return "aucune arme"
			end
			local definition = Weapons.definition(state.itemId)
			return `arme : {state.itemId}`
				.. `\nchargeur : {state.ammoInMagazine} / {if definition then definition.magazine else 0}`
				.. `\nrechargement : {tostring(Weapons.isReloading(state, os.clock()))}`
		end

		-- Tire au nom du joueur, dans la direction de son personnage.
		if action == "fire" then
			local origin = characterOrigin(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not origin or not root or not root:IsA("BasePart") then
				return "pas de personnage"
			end
			local shots = tonumber(argument) or 1
			for _ = 1, shots do
				onFireRequested(player, origin, root.CFrame.LookVector, math.random(1, 1e9))
				task.wait(0.15)
			end
			local state = states[player]
			return `{shots} tir(s) demandes — chargeur {if state then state.ammoInMagazine else 0}`
		end

		-- Tire sur l'ennemi vivant le plus proche.
		--
		-- L'action "fire" vise dans la direction du personnage, que
		-- l'AutoRotate du Humanoid reoriente en permanence : impossible de
		-- viser de facon reproductible depuis un script. Celle-ci calcule
		-- la direction, ce qui rend le chemin de degats testable.
		if action == "fireat" then
			local origin = characterOrigin(player)
			if not origin then
				return "pas de personnage"
			end

			local enemies = Workspace:FindFirstChild("Enemies")
			if not enemies then
				return "aucun ennemi"
			end

			local best, bestDistance = nil, math.huge
			for _, model in enemies:GetChildren() do
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local part = model:FindFirstChild("HumanoidRootPart")
				if humanoid and humanoid.Health > 0 and part and part:IsA("BasePart") then
					local distance = (part.Position - origin).Magnitude
					if distance < bestDistance then
						best, bestDistance = part, distance
					end
				end
			end

			if not best then
				return "aucun ennemi vivant"
			end

			local shots = tonumber(argument) or 1
			for _ = 1, shots do
				onFireRequested(player, characterOrigin(player), (best.Position - origin).Unit, math.random(1, 1e9))
				task.wait(0.15)
			end

			local humanoid = best.Parent and best.Parent:FindFirstChildOfClass("Humanoid")
			return `{shots} tir(s) vers {best.Parent.Name} a {math.floor(bestDistance)} studs`
				.. ` — cible {if humanoid then math.floor(humanoid.Health) else 0} pv`
				.. `, chargeur {CombatService.GetAmmo(player)}`
		end

		if action == "reload" then
			onReloadRequested(player, math.random(1, 1e9))
			return "rechargement demande"
		end

		return "actions : status | fire [n] | fireat [n] | reload"
	end

	log:info("debug : ServerStorage.DebugCombat:Invoke(\"status\"|\"fire\"|\"reload\")")
end

-- ---------------------------------------------------------- Cycle de vie ---

local function onPlayerAdded(player: Player)
	guards[player] = RequestGuard.new(Config.Weapons.validation.requestHistory)
	syncWeapon(player)

	table.insert(connections, player.CharacterAdded:Connect(function()
		-- Nouveau personnage, nouveau chargeur : mourir doit couter.
		states[player] = nil
		syncWeapon(player)
	end))
end

function CombatService.Init(context: ServiceContext)
	ctx = context
end

function CombatService.Start()
	local context = ctx
	if not context then
		return
	end

	installDebug()

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		guards[player] = nil
	end))

	local fireRemote = context.Remotes:FindFirstChild("RequestFire")
	if fireRemote and fireRemote:IsA("RemoteEvent") then
		table.insert(connections, fireRemote.OnServerEvent:Connect(onFireRequested))
	end

	local reloadRemote = context.Remotes:FindFirstChild("RequestReload")
	if reloadRemote and reloadRemote:IsA("RemoteEvent") then
		table.insert(connections, reloadRemote.OnServerEvent:Connect(onReloadRequested))
	end

	local count = 0
	for _ in Config.Weapons.weapons do
		count += 1
	end
	log:info(`pret — {count} arme(s), arme par defaut {tostring(Config.Weapons.defaultWeapon)}`)
end

function CombatService.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(states)
	table.clear(guards)
end

return CombatService
