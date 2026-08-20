--!strict
-- Achats : gamepasses et produits developpeur.
--
-- CHEMIN D'OCTROI UNIQUE — ProcessReceipt.
-- Rien d'autre n'accorde quoi que ce soit. Le seul remote entrant,
-- RequestPurchase, ne fait qu'AFFICHER une invite d'achat : il ne touche
-- jamais un profil. Meme si un client le sature d'appels forges, il ne peut
-- obtenir qu'une fenetre d'achat.
--
-- IDEMPOTENCE — le point delicat.
-- Roblox rappelle ProcessReceipt tant qu'on n'a pas repondu PurchaseGranted.
-- Deux pieges symetriques :
--   accorder deux fois  -> le joueur recoit le double de ce qu'il a paye
--   accorder sans sauver -> le joueur perd ce qu'il a paye au prochain crash
-- La reponse est donc : accorder, SAUVEGARDER, et ne repondre PurchaseGranted
-- qu'apres confirmation de l'ecriture. Tant que la sauvegarde echoue, on
-- rend NotProcessedYet et Roblox reessaiera.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Logger = require(Shared.Utils.Logger)
local RequestGuard = require(Shared.Utils.RequestGuard)

local Grants = require(script.Parent.Parent.Monetization.Grants)

type ServiceContext = Types.ServiceContext

local MonetizationService = {}

MonetizationService.Name = "MonetizationService"
MonetizationService.Priority = 95

local log = Logger.new("Monetization")
local ctx: ServiceContext?

-- Identifiants d'achat dont la SAUVEGARDE est confirmee. Distinct de
-- l'historique du profil : celui-ci peut contenir un achat applique en
-- memoire mais jamais ecrit, qu'il faut retenter plutot que valider.
local confirmed: { [string]: boolean } = {}

local guards: { [Player]: RequestGuard.Guard } = {}
local connections: { RBXScriptConnection } = {}

-- Index identifiant Roblox -> cle de produit, construit au demarrage.
local productsById: { [number]: string } = {}
local passesById: { [number]: string } = {}

-- --------------------------------------------------------- Journalisation ---

-- Passe par Track, donc par le catalogue et le filtre anti-PII. Aucun
-- service ne parle aux API Roblox d'analytique en direct.
local function record(event: string, player: Player?, payload: { [string]: any })
	local context = ctx
	local analytics = context and context.Get("AnalyticsService")
	if not analytics then
		return
	end

	if Config.Analytics.events[event] then
		(analytics :: any).Track(event, player, payload)
	else
		(analytics :: any).Record(event, player, payload)
	end
end

local function purchaseStarted(player: Player, productKey: string, kind: string)
	log:info(`PurchaseStarted — {player.Name} / {productKey} ({kind})`)
	record("PurchaseStarted", player, { product = productKey, kind = kind })
end

local function purchaseCompleted(player: Player, productKey: string, summary: string)
	log:info(`PurchaseCompleted — {player.Name} / {productKey} : {summary}`)
	record("PurchaseCompleted", player, { product = productKey, summary = summary })
end

local function purchaseFailed(player: Player?, productKey: string, reason: string)
	local who = if player then player.Name else "inconnu"
	log:warn(`PurchaseFailed — {who} / {productKey} : {reason}`)
	record("PurchaseFailed", player, { product = productKey, reason = reason })
end

-- ------------------------------------------------------------- Catalogue ---

local function indexCatalogue()
	local unconfigured: { string } = {}

	for key, product in Config.Monetization.developerProducts do
		if type(product.id) == "number" and product.id > 0 then
			productsById[product.id] = key
		else
			table.insert(unconfigured, `produit {key}`)
		end
	end

	for key, pass in Config.Monetization.gamepasses do
		if type(pass.id) == "number" and pass.id > 0 then
			passesById[pass.id] = key
		else
			table.insert(unconfigured, `gamepass {key}`)
		end
	end

	if #unconfigured > 0 then
		log:warn(
			`{#unconfigured} produit(s) sans identifiant Roblox : {table.concat(unconfigured, ", ")}`
				.. " — renseigne-les dans Shared/Config/MonetizationConfig"
		)
	end
end

-- ------------------------------------------------------- ProcessReceipt ---

local function grantProduct(player: Player, productKey: string, purchaseId: string): boolean
	local context = ctx
	local dataService = context and context.Get("DataService")
	if not dataService then
		purchaseFailed(player, productKey, "DataService indisponible")
		return false
	end

	local profile = (dataService :: any).GetProfile(player)
	if not profile then
		purchaseFailed(player, productKey, "profil non charge")
		return false
	end

	-- Deja applique en memoire mais jamais ecrit : on ne rejoue pas
	-- l'octroi, on retente uniquement la sauvegarde.
	if not Grants.wasPurchased(profile, purchaseId) then
		local product = Config.Monetization.developerProducts[productKey]
		local result = Grants.apply(profile, product.grant, os.time())

		if not result.ok then
			purchaseFailed(player, productKey, tostring(result.error))
			return false
		end

		Grants.rememberPurchase(profile, purchaseId)
		purchaseCompleted(player, productKey, tostring(result.summary))
	end

	-- La reponse PurchaseGranted engage Roblox a ne plus rejouer le recu.
	-- On ne la donne qu'une fois l'ecriture confirmee.
	if not (dataService :: any).ForceSave(player) then
		purchaseFailed(player, productKey, "sauvegarde impossible, Roblox reessaiera")
		return false
	end

	confirmed[purchaseId] = true

	local remote = context and context.Remotes:FindFirstChild("PurchaseResult")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, productKey, true)
	end

	return true
end

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local purchaseId = tostring(receiptInfo.PurchaseId)

	if confirmed[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Parti avant qu'on ait pu honorer. On ne valide surtout pas :
		-- Roblox rejouera le recu a sa prochaine connexion.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productKey = productsById[receiptInfo.ProductId]
	if not productKey then
		-- Produit inconnu de notre catalogue : identifiant pas encore
		-- renseigne, ou produit retire. Encaisser sans savoir quoi donner
		-- serait pire que faire patienter.
		purchaseFailed(player, `id:{receiptInfo.ProductId}`, "produit absent du catalogue")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok = false
	local success, err = pcall(function()
		ok = grantProduct(player, productKey, purchaseId)
	end)

	if not success then
		purchaseFailed(player, productKey, `exception : {tostring(err)}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return if ok
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ------------------------------------------------------------ Gamepasses ---

local function applyGamepasses(player: Player)
	local context = ctx
	local dataService = context and context.Get("DataService")
	if not dataService then
		return
	end

	local profile = (dataService :: any).GetProfile(player)
	if not profile then
		return
	end

	profile.Gamepasses = profile.Gamepasses or {}

	for key, pass in Config.Monetization.gamepasses do
		if type(pass.id) ~= "number" or pass.id <= 0 then
			continue
		end

		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
		end)

		if not ok then
			-- On ne retire jamais un avantage sur un echec de verification :
			-- une panne reseau ne doit pas depouiller un joueur payant.
			log:warn(`verification du gamepass {key} impossible pour {player.Name}`)
			continue
		end

		profile.Gamepasses[key] = owns

		if owns then
			local result = Grants.apply(profile, pass.grant, os.time())
			if result.ok then
				log:info(`{player.Name} possede {key} : {tostring(result.summary)}`)
			else
				purchaseFailed(player, key, tostring(result.error))
			end
		end
	end
end

-- ---------------------------------------------------------------- API ----

function MonetizationService.GetBlackTokens(player: Player): number
	local context = ctx
	local dataService = context and context.Get("DataService")
	local profile = dataService and (dataService :: any).GetProfile(player)
	return if profile then (profile.BlackTokens or 0) else 0
end

function MonetizationService.GetCreditMultiplier(player: Player): number
	local context = ctx
	local dataService = context and context.Get("DataService")
	local profile = dataService and (dataService :: any).GetProfile(player)
	return if profile then Grants.creditMultiplier(profile, os.time()) else 1
end

function MonetizationService.OwnsGamepass(player: Player, key: string): boolean
	local context = ctx
	local dataService = context and context.Get("DataService")
	local profile = dataService and (dataService :: any).GetProfile(player)
	return profile ~= nil and profile.Gamepasses ~= nil and profile.Gamepasses[key] == true
end

-- ---------------------------------------------------- Invite d'achat -----

-- N'ACCORDE RIEN. Ouvre une fenetre d'achat, point. Le client pourrait
-- appeler PromptProductPurchase lui-meme ; on passe par le serveur pour
-- disposer d'un evenement PurchaseStarted fiable et pour valider la cle
-- contre le catalogue.
local function onPurchaseRequested(player: Player, productKey: any, requestId: any)
	local guard = guards[player]
	if not guard or type(productKey) ~= "string" or type(requestId) ~= "number" then
		return
	end
	if not RequestGuard.accept(guard, requestId) then
		return
	end

	local product = Config.Monetization.developerProducts[productKey]
	if product then
		if product.id <= 0 then
			purchaseFailed(player, productKey, "identifiant Roblox non renseigne")
			return
		end
		purchaseStarted(player, productKey, "produit")
		MarketplaceService:PromptProductPurchase(player, product.id)
		return
	end

	local pass = Config.Monetization.gamepasses[productKey]
	if pass then
		if pass.id <= 0 then
			purchaseFailed(player, productKey, "identifiant Roblox non renseigne")
			return
		end
		purchaseStarted(player, productKey, "gamepass")
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
		return
	end

	purchaseFailed(player, tostring(productKey), "cle absente du catalogue")
end

-- ---------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local existing = ServerStorage:FindFirstChild("DebugMonetization")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugMonetization"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: any, argument: any): string
		local player = Players:GetPlayers()[1]

		if action == "catalogue" then
			local lines = {}
			for key, product in Config.Monetization.developerProducts do
				table.insert(lines, `produit  {key} : id={product.id}`
					.. `{if product.id <= 0 then "  <-- NON RENSEIGNE" else ""}`)
			end
			for key, pass in Config.Monetization.gamepasses do
				table.insert(lines, `gamepass {key} : id={pass.id}`
					.. `{if pass.id <= 0 then "  <-- NON RENSEIGNE" else ""}`)
			end
			table.sort(lines)
			return table.concat(lines, "\n")
		end

		if action == "status" and player then
			return `Black Tokens : {MonetizationService.GetBlackTokens(player)}`
				.. `\nmultiplicateur credits : {MonetizationService.GetCreditMultiplier(player)}`
				.. `\nrecus confirmes : {(function()
					local n = 0
					for _ in confirmed do n += 1 end
					return n
				end)()}`
		end

		-- Simule un recu SANS passer par Roblox, pour eprouver le chemin
		-- d'octroi et son idempotence. Studio uniquement.
		if action == "receipt" and player then
			local productKey = tostring(argument)
			local product = Config.Monetization.developerProducts[productKey]
			if not product then
				return `produit inconnu : {productKey}`
			end

			local fakeId = `debug-{productKey}`
			local granted = grantProduct(player, productKey, fakeId)
			if granted then
				confirmed[fakeId] = true
			end
			return `octroi {if granted then "accorde" else "refuse"} pour {productKey}`
		end

		return "actions : catalogue | status | receipt <cle>"
	end

	log:info("debug : ServerStorage.DebugMonetization:Invoke(\"catalogue\"|\"status\"|\"receipt\")")
end

-- ---------------------------------------------------------- Cycle de vie ---

function MonetizationService.Init(context: ServiceContext)
	ctx = context
	indexCatalogue()
end

function MonetizationService.Start()
	installDebug()

	local context = ctx
	if not context then
		return
	end

	-- Un seul rappel ProcessReceipt peut exister par serveur : c'est le
	-- point d'entree unique et il doit rester ici.
	MarketplaceService.ProcessReceipt = processReceipt

	local function onPlayerAdded(player: Player)
		guards[player] = RequestGuard.new()
		task.spawn(function()
			-- On attend que le profil soit charge : appliquer un gamepass
			-- sur un profil absent le perdrait silencieusement.
			for _ = 1, 40 do
				local dataService = context.Get("DataService")
				if dataService and (dataService :: any).IsLoaded(player) then
					applyGamepasses(player)
					return
				end
				task.wait(0.25)
			end
			log:warn(`profil de {player.Name} jamais charge, gamepasses non appliques`)
		end)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		guards[player] = nil
	end))

	local remote = context.Remotes:FindFirstChild("RequestPurchase")
	if remote and remote:IsA("RemoteEvent") then
		table.insert(connections, remote.OnServerEvent:Connect(onPurchaseRequested))
	end

	-- Journalisation des invites refermees, achat ou non.
	table.insert(
		connections,
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
			local key = passesById[passId]
			if not key then
				return
			end
			if wasPurchased then
				applyGamepasses(player)
				local dataService = context.Get("DataService")
				if dataService then
					(dataService :: any).ForceSave(player)
				end
				purchaseCompleted(player, key, "gamepass acquis")
			else
				purchaseFailed(player, key, "invite fermee sans achat")
			end
		end)
	)

	local products = 0
	for _ in productsById do
		products += 1
	end
	local passes = 0
	for _ in passesById do
		passes += 1
	end

	log:info(`pret — {products} produit(s) et {passes} gamepass(es) avec identifiant valide`)
end

function MonetizationService.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(guards)
end

return MonetizationService
