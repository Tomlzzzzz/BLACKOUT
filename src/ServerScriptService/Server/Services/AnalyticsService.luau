--!strict
-- Telemetrie centrale.
--
-- POINT DE PASSAGE UNIQUE. Aucun autre service ne parle aux API Roblox
-- d'analytique : ils appellent Track, TrackOnce ou TrackRun, et c'est tout.
-- Cette contrainte n'est pas cosmetique — c'est ce qui garantit qu'un seul
-- endroit filtre les donnees personnelles, valide les noms d'evenements et
-- decide du format. Quinze appelants qui construisent chacun leur payload,
-- c'est quinze occasions de laisser fuir un nom d'utilisateur.
--
-- Trois protections, toutes appliquees a l'execution :
--   1. evenement absent du catalogue -> refuse
--   2. cle ou valeur personnelle     -> refuse (pas nettoye en silence)
--   3. jalon deja franchi            -> ignore, une seule fois par joueur
--
-- Demarre en dernier (Priority 99) pour observer tout le reste.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Logger = require(Shared.Utils.Logger)

local Sanitize = require(script.Parent.Parent.Analytics.Sanitize)

type ServiceContext = Types.ServiceContext

export type Event = {
	name: string,
	userId: number?,
	at: number,
	payload: { [string]: any },
}

local AnalyticsService = {}

AnalyticsService.Name = "AnalyticsService"
AnalyticsService.Priority = 99

local log = Logger.new("Analytics")
local ctx: ServiceContext?

local events: { Event } = {}
local counts: { [string]: number } = {}
local rejected = 0

-- API Roblox, resolue une fois. Peut etre absente selon le contexte : on
-- degrade sans bruit plutot que de faire echouer chaque evenement.
local robloxAnalytics: any = nil

local function summarize(payload: { [string]: any }): string
	local keys = {}
	for key in payload do
		table.insert(keys, key)
	end
	if #keys == 0 then
		return ""
	end
	table.sort(keys)

	local parts = {}
	for _, key in keys do
		table.insert(parts, `{key}={tostring(payload[key])}`)
	end
	return " { " .. table.concat(parts, ", ") .. " }"
end

local function forward(eventName: string, player: Player?, payload: { [string]: any })
	if not Config.Analytics.forwardToRoblox or not robloxAnalytics or not player then
		return
	end

	local funnelName, step = Sanitize.funnelStep(eventName)

	-- Enveloppe systematique : ces API refusent selon le contexte (Studio,
	-- parametres du jeu) et leur echec ne doit jamais interrompre une
	-- action de gameplay.
	pcall(function()
		if funnelName and step then
			robloxAnalytics:LogFunnelStepEvent(player, funnelName, nil, step, eventName)
		else
			robloxAnalytics:LogCustomEvent(player, eventName, 1, payload)
		end
	end)
end

-- ------------------------------------------------------------------ API ---

-- Emission generique. Retourne false si l'evenement a ete refuse, avec la
-- raison journalisee : un appelant peut ignorer le retour, mais le refus
-- laisse une trace.
function AnalyticsService.Track(eventName: string, player: Player?, payload: { [string]: any }?): boolean
	local definition = Config.Analytics.events[eventName]
	if not definition then
		rejected += 1
		log:warn(`evenement absent du catalogue, refuse : {tostring(eventName)}`)
		return false
	end

	local forbiddenValues: { string }? = nil
	if player then
		forbiddenValues = { player.Name, player.DisplayName }
	end

	local result = Sanitize.payload(payload, forbiddenValues)
	if not result.ok then
		rejected += 1
		log:warn(`{eventName} refuse : {tostring(result.error)}`)
		return false
	end

	local clean = result.payload :: { [string]: any }

	local event: Event = {
		name = eventName,
		-- L'identifiant technique, jamais le nom. C'est ce que les API
		-- Roblox attendent et il ne revele rien par lui-meme.
		userId = if player then player.UserId else nil,
		at = os.clock(),
		payload = clean,
	}

	table.insert(events, event)
	counts[eventName] = (counts[eventName] or 0) + 1

	if #events > Config.Analytics.bufferSize then
		table.remove(events, 1)
	end

	log:info(`{eventName}{if player then ` <{player.UserId}>` else ""}{summarize(clean)}`)
	forward(eventName, player, clean)

	return true
end

-- Jalon : une seule fois par joueur, a vie. L'etat vit dans le profil, donc
-- il survit a la deconnexion — sinon chaque reconnexion rejouerait
-- "premiere extraction" et l'entonnoir d'accueil ne voudrait plus rien dire.
function AnalyticsService.TrackOnce(eventName: string, player: Player, payload: { [string]: any }?): boolean
	local context = ctx
	local dataService = context and context.Get("DataService")
	if not dataService then
		return false
	end

	local profile = (dataService :: any).GetProfile(player)
	if not profile then
		-- Profil pas encore charge : on renonce plutot que de marquer un
		-- jalon qu'on ne saurait pas persister.
		return false
	end

	profile.Milestones = profile.Milestones or {}
	if profile.Milestones[eventName] then
		return false
	end

	local sent = AnalyticsService.Track(eventName, player, payload)
	if sent then
		profile.Milestones[eventName] = true
	end
	return sent
end

function AnalyticsService.HasMilestone(player: Player, eventName: string): boolean
	local context = ctx
	local dataService = context and context.Get("DataService")
	local profile = dataService and (dataService :: any).GetProfile(player)
	return profile ~= nil
		and profile.Milestones ~= nil
		and profile.Milestones[eventName] == true
end

-- Conserve pour compatibilite avec les appels existants qui utilisaient des
-- noms libres (crawler_hit, threat_band_changed...). Ceux-la ne passent pas
-- par le catalogue et restent purement locaux : ils ne partent pas chez
-- Roblox.
function AnalyticsService.Record(name: string, player: Player?, payload: { [string]: any }?)
	if type(name) ~= "string" or name == "" then
		return
	end

	local result = Sanitize.payload(payload, if player then { player.Name, player.DisplayName } else nil)
	local clean = if result.ok then result.payload :: { [string]: any } else {}

	table.insert(events, {
		name = name,
		userId = if player then player.UserId else nil,
		at = os.clock(),
		payload = clean,
	})
	counts[name] = (counts[name] or 0) + 1

	if #events > Config.Analytics.bufferSize then
		table.remove(events, 1)
	end

	log:info(`{name}{if player then ` <{player.UserId}>` else ""}{summarize(clean)}`)
end

function AnalyticsService.GetEvents(): { Event }
	return events
end

function AnalyticsService.CountOf(name: string): number
	return counts[name] or 0
end

-- --------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local existing = ServerStorage:FindFirstChild("DebugAnalytics")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugAnalytics"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: any): string
		if action == "counts" then
			local lines = {}
			for name, count in counts do
				table.insert(lines, `{name} : {count}`)
			end
			table.sort(lines)
			table.insert(lines, `refuses : {rejected}`)
			return table.concat(lines, "\n")
		end

		if action == "catalogue" then
			local lines = {}
			for name, definition in Config.Analytics.events do
				local funnel, step = Sanitize.funnelStep(name)
				table.insert(lines, `{name}{if definition.once then "  [jalon]" else ""}`
					.. `{if funnel then `  [{funnel} #{step}]` else ""}`)
			end
			table.sort(lines)
			return table.concat(lines, "\n")
		end

		if action == "milestones" then
			local player = Players:GetPlayers()[1]
			local context = ctx
			local dataService = context and context.Get("DataService")
			local profile = player and dataService and (dataService :: any).GetProfile(player)
			if not profile then
				return "aucun profil"
			end
			local lines = {}
			for name in profile.Milestones do
				table.insert(lines, name)
			end
			table.sort(lines)
			return if #lines == 0 then "aucun jalon franchi" else table.concat(lines, "\n")
		end

		return "actions : counts | catalogue | milestones"
	end

	log:info("debug : ServerStorage.DebugAnalytics:Invoke(\"counts\"|\"catalogue\"|\"milestones\")")
end

-- ---------------------------------------------------------- Cycle de vie ---

function AnalyticsService.Init(context: ServiceContext)
	ctx = context

	local ok, service = pcall(function()
		return game:GetService("AnalyticsService")
	end)
	robloxAnalytics = if ok then service else nil
end

function AnalyticsService.Start()
	installDebug()

	local count = 0
	for _ in Config.Analytics.events do
		count += 1
	end

	log:info(
		`pret — {count} evenements au catalogue,`
			.. ` relais Roblox {if robloxAnalytics and Config.Analytics.forwardToRoblox then "actif" else "inactif"}`
	)
end

function AnalyticsService.Stop()
	table.clear(events)
	table.clear(counts)
end

return AnalyticsService
