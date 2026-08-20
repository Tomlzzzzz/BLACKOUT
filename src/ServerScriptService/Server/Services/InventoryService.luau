--!strict
-- Enveloppe serveur du coeur d'inventaire.
--
-- Chaque joueur possede deux contenants, et c'est toute la mecanique du
-- genre :
--   - le SAC DE RAID, leger, emporte en partie, perdu a la mort
--   - le COFFRE, vaste, persistant, jamais expose au danger
--
-- Le sac se deverse dans le coffre a l'extraction. C'est le seul moment ou
-- le butin devient acquis. Les fonctions sans prefixe (Add, Remove, Has...)
-- visent toujours le sac de raid : c'est sur lui que porte le jeu.
--
-- Toute mutation passe par ce service. Le client dispose d'un seul point
-- d'entree, RequestMoveItem, et ne peut y demander qu'une chose : jeter.
-- Ajouter reste strictement serveur — exposer un "add" au client, c'est
-- offrir la duplication d'items le jour meme du lancement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Constants)
local Inventory = require(Shared.Inventory)
local Logger = require(Shared.Utils.Logger)
local RequestGuard = require(Shared.Utils.RequestGuard)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type InventoryResult = Types.InventoryResult
type ItemId = Types.ItemId
type ItemStack = Types.ItemStack
type ResolvedItem = Types.ResolvedItem
type TransferSummary = Types.TransferSummary

local InventoryService = {}

InventoryService.Name = "InventoryService"
InventoryService.Priority = 30

-- Emis a chaque entree reelle dans le sac de raid : (player, itemId,
-- quantite, valeur totale du sac apres ajout).
--
-- Existe pour HandlerService, qui doit savoir que le joueur produit — c'est
-- ce qui distingue un Scavenger qui travaille d'un qui traine, et donc ce
-- qui declenche les rappels de rendement du commanditaire. Passer par un
-- signal plutot que d'aller sonder l'inventaire evite a la fois le polling
-- et une dependance de InventoryService vers Handler.
InventoryService.ItemAdded = Signal.new()

local log = Logger.new("InventoryService")
local ctx: ServiceContext?

local raidBags: { [Player]: Types.Inventory } = {}
local stashes: { [Player]: Types.Inventory } = {}
local guards: { [Player]: RequestGuard.Guard } = {}

-- L'objet equipe est un etat serveur, pas une preference d'affichage : le
-- jour ou equiper aura un effet, c'est cette valeur qui fera foi. Le HUD ne
-- fait que la lire. Declare ici, avec les autres tables indexees par joueur,
-- pour etre visible du liberateur ci-dessous.
local equipped: { [Player]: ItemId? } = {}

local connections: { RBXScriptConnection } = {}

local function onPlayerAdded(player: Player)
	raidBags[player] = Inventory.new(Constants.BASE_CARRY_WEIGHT)
	stashes[player] = Inventory.new(Constants.STASH_CAPACITY)
	guards[player] = RequestGuard.new()
end

-- Le coffre appartient au profil : c'est lui qui sera persiste, et deux
-- proprietaires pour la meme donnee finiraient par diverger. Le coffre
-- local ne sert que si DataService est absent — un service casse ne doit
-- pas priver le joueur de son inventaire de raid.
local function getStash(player: Player): Types.Inventory?
	local context = ctx
	local dataService = context and context.Get("DataService")
	if dataService then
		local stash = (dataService :: any).GetStash(player)
		if stash then
			return stash
		end
	end
	return stashes[player]
end

local function onPlayerRemoving(player: Player)
	raidBags[player] = nil
	stashes[player] = nil
	guards[player] = nil
	-- `equipped` etait la seule table indexee par joueur a ne pas etre
	-- liberee : elle gardait une entree par joueur ayant jamais rejoint.
	equipped[player] = nil
end

-- Notifie le proprietaire, et lui seul : le contenu d'un sac n'a aucune
-- raison d'etre replique aux autres joueurs.
local function pushChanged(player: Player)
	local context = ctx
	local bag = raidBags[player]
	if not context or not bag then
		return
	end

	local remote = context.Remotes:FindFirstChild("InventoryChanged")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, Inventory.contents(bag), Inventory.weight(bag), bag.capacity)
	end
end

-- ------------------------------------------------- API — sac de raid ----

function InventoryService.Add(player: Player, itemId: ItemId, quantity: number): InventoryResult
	local bag = raidBags[player]
	if not bag then
		return { ok = false, error = "NO_INVENTORY" }
	end

	local result = Inventory.add(bag, itemId, quantity)
	if result.ok then
		pushChanged(player)
		Signal.fire(InventoryService.ItemAdded, player, itemId, quantity, Inventory.value(bag))
	end
	return result
end

function InventoryService.Remove(player: Player, itemId: ItemId, quantity: number): InventoryResult
	local bag = raidBags[player]
	if not bag then
		return { ok = false, error = "NO_INVENTORY" }
	end

	local result = Inventory.remove(bag, itemId, quantity)
	if result.ok then
		pushChanged(player)
	end
	return result
end

-- ------------------------------------------- Emplacement equipe ---------

function InventoryService.GetEquipped(player: Player): ItemId?
	return equipped[player]
end

function InventoryService.SetEquipped(player: Player, itemId: ItemId?): boolean
	-- On n'equipe que ce qu'on possede reellement.
	if itemId ~= nil and not InventoryService.Has(player, itemId, 1) then
		return false
	end

	equipped[player] = itemId

	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("EquippedChanged")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, itemId)
	end

	-- CombatService reconstruit l'etat de tir : c'est l'emplacement equipe
	-- qui determine l'arme, et il doit le savoir au moment ou il change,
	-- pas au tir suivant.
	local combatService = context and context.Get("CombatService")
	if combatService then
		(combatService :: any).OnEquipmentChanged(player)
	end

	return true
end

function InventoryService.Has(player: Player, itemId: ItemId, quantity: number?): boolean
	local bag = raidBags[player]
	return if bag then Inventory.has(bag, itemId, quantity) else false
end

function InventoryService.GetWeight(player: Player): number
	local bag = raidBags[player]
	return if bag then Inventory.weight(bag) else 0
end

function InventoryService.GetCapacity(player: Player): number
	local bag = raidBags[player]
	return if bag then bag.capacity else 0
end

function InventoryService.GetContents(player: Player): { ResolvedItem }
	local bag = raidBags[player]
	return if bag then Inventory.contents(bag) else {}
end

-- ----------------------------------------------------- API — coffre ----

function InventoryService.AddToStash(player: Player, itemId: ItemId, quantity: number): InventoryResult
	local stash = getStash(player)
	if not stash then
		return { ok = false, error = "NO_INVENTORY" }
	end
	return Inventory.add(stash, itemId, quantity)
end

-- Valeur du seul sac de raid : ce que le joueur perd s'il meurt maintenant.
-- A ne pas confondre avec GetStashValue, qui chiffre ce qui est deja a
-- l'abri.
function InventoryService.GetRaidValue(player: Player): number
	local bag = raidBags[player]
	return if bag then Inventory.value(bag) else 0
end

function InventoryService.GetStashContents(player: Player): { ResolvedItem }
	local stash = getStash(player)
	return if stash then Inventory.contents(stash) else {}
end

function InventoryService.GetStashValue(player: Player): number
	local stash = getStash(player)
	return if stash then Inventory.value(stash) else 0
end

-- ------------------------------------------- Extraction et mort ---------

-- Extraction reussie : le sac se deverse dans le coffre. Ce qui ne rentre
-- pas y reste — un coffre plein ne detruit rien, il refuse, et le joueur
-- doit pouvoir l'apprendre plutot que de constater une disparition.
function InventoryService.ExtractToStash(player: Player): TransferSummary
	local bag = raidBags[player]
	local stash = getStash(player)
	if not bag or not stash then
		return { moved = {}, leftBehind = {} }
	end

	local summary = Inventory.transfer(bag, stash)
	pushChanged(player)

	if #summary.leftBehind > 0 then
		log:warn(`{player.Name} : coffre plein, {#summary.leftBehind} pile(s) restent dans le sac`)
	end
	return summary
end

-- Mort : le sac est perdu, le coffre est intact. Retourne ce qui a ete
-- perdu et sa valeur, pour que l'ecran de fin puisse le chiffrer.
function InventoryService.LoseRaidBag(player: Player): (number, { ItemStack })
	local bag = raidBags[player]
	if not bag then
		return 0, {}
	end

	local lost: { ItemStack } = {}
	for _, stack in bag.slots do
		table.insert(lost, { id = stack.id, quantity = stack.quantity })
	end

	local value = Inventory.value(bag)
	Inventory.clear(bag)
	pushChanged(player)

	return value, lost
end

-- ------------------------------------------------------------ Remote ----

-- Frontiere client. Tout ce qui arrive ici est hostile jusqu'a preuve du
-- contraire : types verifies un par un avant le moindre usage, car un
-- client modifie envoie ce qu'il veut, y compris des tables la ou on
-- attend un nombre.
local function onRequest(player: Player, action: any, itemId: any, quantity: any, requestId: any): InventoryResult
	local guard = guards[player]
	if not guard then
		return { ok = false, error = "NO_INVENTORY" }
	end

	if type(action) ~= "string" or type(itemId) ~= "string" or type(requestId) ~= "number" then
		return { ok = false, error = "BAD_REQUEST" }
	end

	-- Le controle d'unicite passe avant l'execution : un rejeu doit etre
	-- refuse meme quand la demande est par ailleurs parfaitement valide.
	if not RequestGuard.accept(guard, requestId) then
		return { ok = false, error = "DUPLICATE_REQUEST" }
	end

	-- Seul "drop" est recevable. Toute autre action (add, set, swap, et
	-- surtout tout ce qui toucherait au coffre) est refusee par principe.
	if action ~= "drop" then
		log:warn(`{player.Name} a demande l'action interdite "{action}"`)
		return { ok = false, error = "BAD_REQUEST" }
	end

	return InventoryService.Remove(player, itemId, quantity)
end

-- ------------------------------------------------------- Cycle de vie ----

function InventoryService.Init(context: ServiceContext)
	ctx = context
end

function InventoryService.Start()
	local context = ctx
	if not context then
		log:error("aucun contexte fourni par Init")
		return
	end

	-- Les joueurs deja connectes au moment du Start ne declencheront jamais
	-- PlayerAdded : en playtest Studio, le joueur local arrive souvent
	-- avant que les services soient prets.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))

	local remote = context.Remotes:FindFirstChild("RequestMoveItem")
	if remote and remote:IsA("RemoteFunction") then
		remote.OnServerInvoke = onRequest
	else
		log:error("RequestMoveItem introuvable : le client n'a aucun moyen de jeter")
	end

	log:info(`pret — sac {Constants.BASE_CARRY_WEIGHT}, coffre {Constants.STASH_CAPACITY}`)
end

function InventoryService.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(raidBags)
	table.clear(stashes)
	table.clear(guards)
end

return InventoryService
