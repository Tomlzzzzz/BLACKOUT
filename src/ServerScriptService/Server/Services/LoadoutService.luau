--!strict
-- Barre d'equipement a cinq emplacements.
--
-- La maquette du HUD v2 impose une barre 1-5. Ce service la produit, mais il
-- ne STOCKE rien : les emplacements sont une projection du sac de raid, relu
-- a chaque changement. InventoryService reste le seul proprietaire du
-- contenu ; dupliquer l'etat ici garantirait qu'il derive.
--
-- Le seul canal montant du HUD arrive ici : RequestSlot. Le client dit
-- « le joueur a appuye sur 3 », le serveur decide ce que ca veut dire et si
-- c'est permis. Aucune consommation, aucun soin, aucun equipement n'est
-- decide cote client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local ItemDatabase = require(Shared.ItemDatabase)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type LoadoutSlot = Types.LoadoutSlot
type ResolvedItem = Types.ResolvedItem

local LoadoutService = {}

LoadoutService.Name = "LoadoutService"
-- Apres InventoryService (30) et CombatService (55) : il lit les deux.
LoadoutService.Priority = 58

local log = Logger.new("Loadout")
local ctx: ServiceContext?

local connections: { RBXScriptConnection } = {}
local subscriptions: { any } = {}
local lastRequestAt: { [Player]: number } = {}

local function service(name: string): any?
	local context = ctx
	return context and context.Get(name)
end

-- --------------------------------------------------------- Projection ----

-- Construit les cinq cases a partir du sac. Rien n'est memorise : appeler
-- deux fois de suite donne deux fois le meme resultat, et le seul moyen de
-- le changer est de changer le sac.
function LoadoutService.Build(player: Player): { LoadoutSlot }
	local inventory = service("InventoryService")
	local combat = service("CombatService")
	local playerService = service("PlayerService")

	local contents: { ResolvedItem } = if inventory then inventory.GetContents(player) else {}
	local byId: { [string]: ResolvedItem } = {}
	for _, item in contents do
		byId[item.id] = item
	end

	local equipped = if inventory then inventory.GetEquipped(player) else nil

	-- Arme de secours.
	--
	-- CombatService garantit que personne n'est jamais totalement desarme :
	-- sans arme dans le sac, il rabat sur `defaultWeapon`. Cette arme-la
	-- n'existe donc dans aucun inventaire, et la barre affichait une case
	-- vide alors que le joueur avait un pistolet en main.
	--
	-- On projette donc l'arme REELLEMENT portee, pas seulement le contenu du
	-- sac. La barre doit dire ce que le joueur tient.
	local carried = if combat then combat.GetWeapon(player) else nil
	local vitals = if playerService then playerService.GetVitals(player) else nil

	local slots: { LoadoutSlot } = {}

	for _, spec in Config.Loadout.slots do
		local slot: LoadoutSlot = {
			index = spec.index,
			key = spec.key,
			label = spec.label,
			counter = spec.counter,
			itemId = nil,
			name = nil,
			quantity = 0,
			ammo = nil,
			magazine = nil,
			percent = nil,
			selected = false,
		}

		-- Premier item accepte present dans le sac : l'ordre de `accepts`
		-- est un ordre de preference, pas une liste indifferente.
		for _, candidate in spec.accepts do
			local found = byId[candidate]
			if found then
				slot.itemId = found.id
				slot.name = found.name
				slot.quantity = found.quantity
				break
			end
		end

		-- Rien dans le sac pour cet emplacement, mais l'arme de secours y
		-- correspond : on l'affiche avec une quantite nulle, ce qui la
		-- distingue d'une arme reellement possedee.
		if not slot.itemId and carried then
			for _, candidate in spec.accepts do
				if candidate == carried then
					local def = ItemDatabase.get(carried)
					slot.itemId = carried
					slot.name = if def then def.name else carried
					slot.quantity = 0
					break
				end
			end
		end

		if slot.itemId then
			local def = ItemDatabase.get(slot.itemId)

			if spec.counter == "ammo" then
				local weapon = Config.Weapons.weapons[slot.itemId]
				slot.magazine = if weapon then weapon.magazine else nil
				-- Les munitions du chargeur ne concernent que l'arme active :
				-- une arme rangee n'a pas de chargeur engage.
				slot.ammo = if (equipped or carried) == slot.itemId and combat then combat.GetAmmo(player) else nil
			elseif spec.counter == "percent" then
				-- L'emplacement utilitaire affiche la charge de la lampe, pas
				-- le nombre de piles : c'est la lecture utile en jeu.
				slot.percent = if vitals then math.floor(vitals.battery) else nil
			end

			slot.selected = (equipped or carried) == slot.itemId
			if def and not slot.name then
				slot.name = def.name
			end
		end

		table.insert(slots, slot)
	end

	return slots
end

local function push(player: Player)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("LoadoutChanged")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, LoadoutService.Build(player))
	end
end

LoadoutService.Push = push

-- ------------------------------------------------------ Utilisation ------

-- Consomme un exemplaire et applique son effet. Renvoie un motif d'echec
-- lisible, jamais un booleen nu : les refus doivent pouvoir se journaliser.
local function useItem(player: Player, itemId: string): (boolean, string)
	local inventory = service("InventoryService")
	local playerService = service("PlayerService")
	if not inventory or not playerService then
		return false, "SERVICE_INDISPONIBLE"
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "MORT"
	end

	local healing = Config.Vitals.healing[itemId]
	if healing then
		if humanoid.Health >= humanoid.MaxHealth then
			return false, "VIE_PLEINE"
		end
		local result = inventory.Remove(player, itemId, 1)
		if not result.ok then
			return false, result.error or "RETRAIT_REFUSE"
		end
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healing)
		return true, "SOIN"
	end

	if itemId == Config.Vitals.battery.cellItem then
		local vitals = playerService.GetVitals(player)
		if vitals and vitals.battery >= vitals.maxBattery then
			return false, "BATTERIE_PLEINE"
		end
		local result = inventory.Remove(player, itemId, 1)
		if not result.ok then
			return false, result.error or "RETRAIT_REFUSE"
		end
		playerService.AddBattery(player, Config.Vitals.battery.perCell)
		playerService.SetLight(player, true)
		return true, "RECHARGE"
	end

	return false, "NON_UTILISABLE"
end

-- --------------------------------------------------- Demande client ------

local function onRequestSlot(player: Player, rawIndex: any)
	-- Validation stricte. Le client n'envoie qu'un nombre, et on ne suppose
	-- meme pas que c'en est un.
	if type(rawIndex) ~= "number" or rawIndex ~= rawIndex then
		return
	end

	local index = math.floor(rawIndex)
	if index < 1 or index > #Config.Loadout.slots then
		return
	end

	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < Config.Loadout.requestCooldown then
		return
	end
	lastRequestAt[player] = now

	local spec = Config.Loadout.slots[index]
	local slots = LoadoutService.Build(player)
	local slot = slots[index]
	if not slot or not slot.itemId then
		local context = ctx
		local remote = context and context.Remotes:FindFirstChild("SlotResult")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireClient(player, "VIDE")
		end
		return
	end

	local inventory = service("InventoryService")
	if not inventory then
		return
	end

	local function verdict(reason: string)
		local context = ctx
		local remote = context and context.Remotes:FindFirstChild("SlotResult")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireClient(player, reason)
		end
	end

	if Config.Loadout.equippable[spec.key] then
		-- Rappuyer sur l'emplacement deja actif ne fait rien : degainer une
		-- arme deja en main rechargerait l'etat de tir pour rien.
		if inventory.GetEquipped(player) ~= slot.itemId then
			inventory.SetEquipped(player, slot.itemId)
		end
	else
		local ok, reason = useItem(player, slot.itemId)
		if not ok then
			-- TOUT refus remonte au joueur. Les silencieux etaient les pires :
			-- presser 3 avec une trousse et la vie pleine ne produisait
			-- strictement rien, ce qui se lit comme une touche cassee.
			verdict(reason)
			log:info(`{player.Name} : emplacement {index} refuse ({reason})`)
		end
	end

	push(player)
end

-- ------------------------------------------------------- Abonnements -----

local function subscribe()
	local inventory = service("InventoryService")
	local playerService = service("PlayerService")
	if not inventory then
		return
	end

	table.insert(
		subscriptions,
		Signal.connect(inventory.ItemAdded, function(player: Player, itemId: string)
			-- Plaque balistique : posee tout de suite si l'armure n'est pas
			-- pleine. Elle quitte alors le sac — c'est un consommable, pas un
			-- objet a transporter jusqu'a l'extraction.
			if itemId == Config.Vitals.armor.plateItem and playerService then
				local vitals = playerService.GetVitals(player)
				if vitals and vitals.armor < vitals.maxArmor then
					local applied = playerService.AddArmor(player, Config.Vitals.armor.perPlate)
					if applied > 0 then
						inventory.Remove(player, itemId, 1)
					end
				end
			end

			push(player)
		end)
	)
end

-- ------------------------------------------------------------- Debug -----

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local ServerStorage = game:GetService("ServerStorage")
	local existing = ServerStorage:FindFirstChild("DebugLoadout")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugLoadout"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: string?, argument: string?): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "aucun joueur"
		end

		if action == "use" then
			local index = tonumber(argument or "")
			if not index then
				return "usage : use <1-5>"
			end
			onRequestSlot(player, index)
			return `emplacement {index} demande`
		end

		local lines = {}
		for _, slot in LoadoutService.Build(player) do
			local counter = if slot.ammo
				then `{slot.ammo}/{slot.magazine or 0}`
				elseif slot.percent then `{slot.percent}%`
				else `x{slot.quantity}`
			table.insert(
				lines,
				string.format(
					"  %d %-10s %-20s %-10s %s",
					slot.index,
					slot.key,
					slot.name or "(vide)",
					if slot.itemId then counter else "-",
					if slot.selected then "ACTIF" else ""
				)
			)
		end
		table.insert(lines, "actions : status | use <1-5>")
		return table.concat(lines, "\n")
	end

	log:info('debug : ServerStorage.DebugLoadout:Invoke("status"|"use <1-5>")')
end

-- -------------------------------------------------------- Cycle de vie ---

function LoadoutService.Init(context: ServiceContext)
	ctx = context
end

function LoadoutService.Start()
	subscribe()

	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("RequestSlot")
	if remote and remote:IsA("RemoteEvent") then
		table.insert(connections, remote.OnServerEvent:Connect(onRequestSlot))
	else
		log:warn("remote RequestSlot absent : la barre sera en lecture seule")
	end

	table.insert(
		connections,
		Players.PlayerAdded:Connect(function(player)
			player.CharacterAdded:Connect(function()
				task.defer(push, player)
			end)
		end)
	)

	for _, player in Players:GetPlayers() do
		task.defer(push, player)
	end

	installDebug()
	log:info(`pret — {#Config.Loadout.slots} emplacements`)
end

function LoadoutService.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, subscription in subscriptions do
		Signal.disconnect(subscription)
	end
	table.clear(subscriptions)
	table.clear(lastRequestAt)
end

return LoadoutService
