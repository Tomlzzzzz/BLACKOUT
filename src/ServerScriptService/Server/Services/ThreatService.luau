--!strict
-- Niveau de menace du raid.
--
-- Valeur unique, bornee a [0, 100], autorite serveur stricte : le client la
-- recoit, il ne la propose jamais. Elle monte avec le temps, le bruit, les
-- generateurs et le butin majeur, et redescend au calme. A 100, The Hunt.
--
-- Toutes les valeurs numeriques viennent de Config.Threat. Ce fichier ne
-- contient aucun nombre de gameplay — s'il t'en faut un nouveau, il va dans
-- ThreatConfig, pas ici.
--
-- NOTE D'INTERFACE : les quatre fonctions de la specification s'appellent
-- avec deux-points (ThreatService:GetThreat()), contrairement au reste du
-- projet qui utilise le point. C'est deliberé pour coller a la spec ; les
-- appelants internes doivent donc ecrire `(threat :: any):AddThreat(...)`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Threat = require(Shared.Threat)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type ThreatBand = Types.ThreatBand
type ThreatChange = Types.ThreatChange

local ThreatService = {}

ThreatService.Name = "ThreatService"
ThreatService.Priority = 65

local log = Logger.new("ThreatService")
local ctx: ServiceContext?

local meter = Threat.new(Config.Threat.min, 0)
local heartbeat: RBXScriptConnection?
local accumulator = 0
local huntActive = false

-- Signaux serveur. EnemyService s'abonnera a BandChanged pour durcir son
-- comportement, et a HuntStarted pour lancer la traque.
ThreatService.BandChanged = Signal.new()
ThreatService.HuntStarted = Signal.new()
ThreatService.HuntEnded = Signal.new()

-- ---------------------------------------------------------------- Sortie ---

local lastBroadcastAt = -math.huge

-- `force` court-circuite l'etranglement : un changement de palier doit
-- partir tout de suite, c'est lui qui pilote l'avertissement visuel.
local function broadcast(change: ThreatChange, force: boolean?)
	local now = os.clock()
	if not force and (now - lastBroadcastAt) < Config.Threat.broadcastInterval then
		return
	end
	lastBroadcastAt = now

	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("ThreatLevelChanged")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(change.value, change.band, change.previousBand)
	end
end

local function fireAll(remoteName: string, ...: any)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(...)
	end
end

local function record(name: string, payload: { [string]: any })
	local context = ctx
	local analytics = context and context.Get("AnalyticsService")
	if analytics then
		(analytics :: any).Record(name, nil, payload)
	end
end

local function endHunt(now: number)
	if not huntActive then
		return
	end
	huntActive = false

	local change = Threat.set(meter, Config.Threat.hunt.postValue, "hunt_ended")
	log:info(`traque terminee — menace ramenee a {math.floor(change.value)} ({change.band})`)

	Signal.fire(ThreatService.HuntEnded, change)
	fireAll("HuntEnded", change.value, change.band)
	record("hunt_ended", { value = change.value, band = change.band })
	broadcast(change)
end

local function beginHunt(now: number)
	huntActive = true
	Threat.markHuntTriggered(meter, now)

	log:warn(`THE HUNT declenchee — menace {math.floor(meter.value)}, duree {Config.Threat.hunt.duration}s`)

	Signal.fire(ThreatService.HuntStarted, Config.Threat.hunt.duration)
	fireAll("HuntStarted", Config.Threat.hunt.duration)
	record("hunt_started", {
		duration = Config.Threat.hunt.duration,
		value = meter.value,
	})
end

-- Publie un changement : signal de palier si le palier a bouge, remote a
-- chaque fois que la valeur bouge, et declenchement de la traque si on
-- vient d'entrer dans HUNT.
-- Pic de menace atteint depuis le debut de la fenetre de contrat.
--
-- Releve ICI parce que `publish` est le passage oblige de toute variation.
-- Lire la menace en fin de raid donnerait sa valeur a l'instant de la
-- sortie, pas ce que le joueur a reellement traverse — c'est exactement
-- l'inverse de ce qu'un rapport doit raconter. Quelqu'un qui a survecu a la
-- traque avant de se cacher vingt minutes sortirait avec « MENACE 4 ».
local peak = 0

local function publish(change: ThreatChange, now: number)
	local bandChanged = change.band ~= change.previousBand

	if change.value > peak then
		peak = change.value
	end

	if bandChanged then
		log:info(`{change.previousBand} -> {change.band} ({math.floor(change.value)}) [{change.reason}]`)
		Signal.fire(ThreatService.BandChanged, change)
		record("threat_band_changed", {
			band = change.band,
			previousBand = change.previousBand,
			value = math.floor(change.value),
			reason = change.reason,
		})
	end

	if change.value ~= change.previous then
		broadcast(change, bandChanged)
	end

	if Threat.shouldTriggerHunt(meter, change, now) then
		beginHunt(now)
	end
end

-- ------------------------------------------------------------------ API ---
-- Notation a deux-points, conformement a la specification.

function ThreatService:GetThreat(): number
	return meter.value
end

function ThreatService:GetState(): ThreatBand
	return Threat.bandFor(meter.value)
end

function ThreatService:AddThreat(amount: number, reason: string?): ThreatChange
	local now = os.clock()
	local change = Threat.add(meter, amount, reason or "unspecified", now)
	publish(change, now)
	return change
end

function ThreatService:SetThreat(value: number, reason: string?): ThreatChange
	local now = os.clock()
	local change = Threat.set(meter, value, reason or "set")
	publish(change, now)
	return change
end

-- ------------------------------------------------------- API de confort ---

-- Ajout par identifiant de source. C'est la voie que les autres services
-- doivent emprunter : elle garde les montants dans la config, la ou un
-- AddThreat(14, "generator") les recoderait en dur chez l'appelant.
function ThreatService:AddSource(sourceId: string, multiplier: number?): ThreatChange?
	local amount = Config.Threat.sources[sourceId]
	if not amount then
		log:warn(`source de menace inconnue : {tostring(sourceId)}`)
		return nil
	end

	local factor = if type(multiplier) == "number" and multiplier > 0 then multiplier else 1
	return self:AddThreat(amount * factor, sourceId)
end

-- Butin majeur : seules les raretes listees dans la config comptent.
-- Ramasser de la ferraille n'alerte personne.
function ThreatService:AddMajorLoot(rarity: string, quantity: number?): ThreatChange?
	local amount = Config.Threat.majorLoot[rarity]
	if not amount then
		return nil
	end

	local count = if type(quantity) == "number" and quantity > 0 then math.min(quantity, 10) else 1
	return self:AddThreat(amount * count, `major_loot:{rarity}`)
end

function ThreatService:IsHuntActive(): boolean
	return huntActive
end

function ThreatService:GetPeak(): number
	return peak
end

-- Le pic appartient a UNE fenetre de contrat. MatchService le remet a zero
-- au redeploiement, en meme temps que la menace elle-meme ; sans cela le
-- deuxieme rapport d'une session afficherait le pic du premier raid.
function ThreatService:ResetPeak()
	peak = meter.value
end

-- ----------------------------------------------------------------- Tick ---

local function tick(dt: number)
	local now = os.clock()

	if huntActive and not Threat.isHuntActive(meter, now) then
		endHunt(now)
		return
	end

	-- Pendant la traque la menace reste au plafond : elle ne redescend pas
	-- pendant qu'on se fait chasser.
	if huntActive then
		return
	end

	local change = Threat.step(meter, dt, now)
	publish(change, now)
end

-- ---------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local existing = ServerStorage:FindFirstChild("DebugThreat")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugThreat"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: any, argument: any): string
		if action == "status" then
			return `menace {string.format("%.1f", meter.value)} / {Config.Threat.max}`
				.. ` — palier {ThreatService:GetState()}`
				.. ` — traque {if huntActive then "EN COURS" else "inactive"}`
				.. ` — abonnes palier {Signal.count(ThreatService.BandChanged)}`
		end
		if action == "add" then
			local change = ThreatService:AddThreat(tonumber(argument) or 0, "debug")
			return `{string.format("%.1f", change.previous)} -> {string.format("%.1f", change.value)} ({change.band})`
		end
		if action == "set" then
			local change = ThreatService:SetThreat(tonumber(argument) or 0, "debug")
			return `{string.format("%.1f", change.previous)} -> {string.format("%.1f", change.value)} ({change.band})`
		end
		if action == "source" then
			local change = ThreatService:AddSource(tostring(argument))
			return if change then `{string.format("%.1f", change.value)} ({change.band})` else "source inconnue"
		end
		return "actions : status | add <n> | set <n> | source <id>"
	end

	log:info("debug : ServerStorage.DebugThreat:Invoke(\"status\"|\"add\"|\"set\"|\"source\")")
end

-- ---------------------------------------------------------- Cycle de vie ---

function ThreatService.Init(context: ServiceContext)
	ctx = context
	meter = Threat.new(Config.Threat.min, os.clock())
end

function ThreatService.Start()
	installDebug()

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.Threat.tickRate then
			return
		end
		local step = accumulator
		accumulator = 0
		tick(step)
	end)

	local net = Config.Threat.passivePerSecond - Config.Threat.decayPerSecond
	log:info(
		`pret — passif +{Config.Threat.passivePerSecond}/s,`
			.. ` calme {string.format("%.2f", net)}/s apres {Config.Threat.quietDelay}s`
	)
end

function ThreatService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	Signal.clear(ThreatService.BandChanged)
	Signal.clear(ThreatService.HuntStarted)
	Signal.clear(ThreatService.HuntEnded)
end

return ThreatService
