--!strict
-- Machine a etats du raid, et horloge du contrat.
--
-- La fenetre de contrat n'appartient pas au joueur : c'est le commanditaire
-- qui l'ouvre et la referme. Ce service est donc le seul a decider quand une
-- partie se termine, et le seul a pouvoir declarer une perte seche.
--
-- Cycle :
--
--   InRaid ---- la fenetre s'ecoule ----> Ended ---- debrief ----> InRaid
--                                          |
--                            tout actif non extrait perd son sac
--
-- Historique : la minuterie existait deja mais ne produisait aucun effet.
-- Un compte a rebours qui atteint zero sans rien fermer est pire que pas de
-- compte a rebours du tout — il apprend au joueur que l'affichage ment.
-- Depuis, l'expiration ferme reellement le contrat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type RaidState = Types.RaidState

local MatchService = {}

MatchService.Name = "MatchService"
MatchService.Priority = 25

-- Signaux serveur.
--
--   WindowClosing  emis AVANT la depossession, pour laisser le
--                  commanditaire prononcer sa derniere phrase pendant que
--                  le joueur a encore sa cargaison sous les yeux.
--   Redeployed     nouvelle fenetre : tout ce qui est par-raid se reamorce.
--   Forfeited      un actif precis n'a pas extrait a temps. Emis PAR
--                  JOUEUR, avec ce qu'il perd, pour que le rapport de fin
--                  puisse chiffrer la sortie plutot que d'annoncer un echec
--                  sans montant.
MatchService.WindowClosing = Signal.new()
MatchService.Redeployed = Signal.new()
MatchService.Forfeited = Signal.new()

local log = Logger.new("MatchService")
local ctx: ServiceContext?

local state: RaidState = "Lobby"
local startedAt = 0
local endedAt = 0
local heartbeat: RBXScriptConnection?
local sinceSync = 0

-- Verrou de transition.
--
-- Les deux transitions appellent du code qui REND LA MAIN — LoadCharacter en
-- premier lieu. Pendant ce rendu, Heartbeat continue de tourner, `tick` relit
-- un etat qui n'a pas encore change, et relance la meme transition. Mesure
-- avant correction : onze redeploiements pour une seule fermeture, onze
-- rotations de zones et autant d'evenements RunStarted.
--
-- Deux protections, parce qu'aucune ne suffit seule : ce drapeau ferme la
-- porte, et chaque transition pose son etat AVANT de travailler pour que
-- `tick` cesse de la reconnaitre des la premiere image.
local transitioning = false

local function service(name: string): any?
	local context = ctx
	return context and context.Get(name)
end

-- ------------------------------------------------------------ Horloge ----

function MatchService.GetState(): RaidState
	return state
end

-- Un raid « valide » est un raid en cours. C'est cette condition que
-- ExtractionService interroge : on n'extrait pas d'un lobby, ni d'une partie
-- deja terminee.
function MatchService.IsRunning(): boolean
	return state == "InRaid"
end

function MatchService.TimeRemaining(): number
	if state ~= "InRaid" then
		return 0
	end
	return math.max(0, Config.Match.windowDuration - (os.clock() - startedAt))
end

local function broadcast()
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("ContractWindow")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(state, MatchService.TimeRemaining(), Config.Match.windowDuration)
	end

	-- Conserve pour les abonnes existants de l'ancien canal.
	local legacy = context and context.Remotes:FindFirstChild("RaidStateChanged")
	if legacy and legacy:IsA("RemoteEvent") then
		legacy:FireAllClients(state, MatchService.TimeRemaining())
	end
end

function MatchService.SetState(next: RaidState)
	if next == state then
		return
	end

	state = next
	if next == "InRaid" then
		startedAt = os.clock()
	elseif next == "Ended" then
		endedAt = os.clock()
	end

	sinceSync = 0
	log:info(`etat -> {next}`)
	broadcast()
end

-- ------------------------------------------------- Fermeture du contrat --

-- L'actif n'a pas extrait a temps. Le sac part, la course est comptee en
-- echec, mais le joueur n'est pas tue : c'est le contrat qui se ferme, pas
-- la ville qui gagne. La nuance compte pour le ton — le commanditaire ne
-- punit pas, il arrete de payer.
local function forfeit(player: Player)
	local inventory = service("InventoryService")
	local analytics = service("AnalyticsService")
	local threat = service("ThreatService")
	local extraction = service("ExtractionService")

	if player:GetAttribute("Extracted") == true then
		return
	end

	local lostValue = 0
	local lostStacks: { any } = {}
	if inventory then
		-- Le second retour porte le detail des piles. Il etait ignore ici
		-- depuis le debut, et c'est lui qui permet au rapport de nommer ce
		-- qui est perdu au lieu d'en donner seulement le prix.
		local value, stacks = inventory.LoseRaidBag(player)
		lostValue = value or 0
		lostStacks = stacks or {}
	end

	local startedFor = extraction and extraction.GetRunStart(player)
	Signal.fire(MatchService.Forfeited, player, lostValue, lostStacks, startedFor)

	if analytics then
		analytics.Track("RunFailed", player, {
			cause = "fenetre_fermee",
			lostValue = math.floor(lostValue),
			duration = if startedFor then math.floor(os.clock() - startedFor) else 0,
			threat = if threat then math.floor(threat:GetThreat()) else 0,
		})
	end

	log:info(`{player.Name} : contrat clos, {math.floor(lostValue)} credits perdus`)
end

local function closeWindow()
	if transitioning then
		return
	end
	transitioning = true

	-- L'etat en premier : des cette ligne, `tick` ne voit plus « InRaid » et
	-- ne peut plus redemander une fermeture pendant qu'on travaille.
	MatchService.SetState("Ended")

	-- L'annonce ensuite, la depossession en dernier : les abonnes parlent
	-- pendant que la cargaison est encore la. Deposseder puis annoncer
	-- donnerait un message qui commente une valeur deja remise a zero.
	Signal.fire(MatchService.WindowClosing)

	for _, player in Players:GetPlayers() do
		local ok, err = pcall(forfeit, player)
		if not ok then
			log:error(`forfeit {player.Name} a leve -> {err}`)
		end
	end

	transitioning = false
end

-- ---------------------------------------------------- Redeploiement ------

local function redeploy()
	if transitioning then
		return
	end
	transitioning = true

	-- Meme regle : la nouvelle fenetre s'ouvre avant le travail. C'est aussi
	-- la bonne semantique — elle commence quand le redeploiement commence,
	-- pas quand le dernier personnage a fini de charger.
	MatchService.SetState("InRaid")

	local threat = service("ThreatService")
	local extraction = service("ExtractionService")

	if threat then
		threat:SetThreat(0, "redeploiement")
		-- Le pic se remet a zero APRES la menace, sinon il retiendrait la
		-- valeur d'avant la remise a zero et le rapport du raid suivant
		-- afficherait le pic du precedent.
		threat:ResetPeak()
	end

	if extraction then
		-- Nouvelle fenetre : les sorties se REVERROUILLENT. Elles se
		-- rouvriront d'elles-memes au bout du delai, comme au premier raid.
		pcall(extraction.LockZones)
	end

	for _, player in Players:GetPlayers() do
		if extraction then
			pcall(extraction.ResetPlayer, player)
		end
		-- LoadCharacter remet aussi la vie, la position et le sac via les
		-- gestionnaires CharacterAdded existants : on ne duplique pas ici ce
		-- que PlayerService fait deja a chaque apparition.
		pcall(function()
			player:LoadCharacter()
		end)
	end

	Signal.fire(MatchService.Redeployed)
	transitioning = false
	log:info(`nouvelle fenetre de contrat — {Config.Match.windowDuration}s`)
end

-- ------------------------------------------------------------- Boucle ----

local function tick(dt: number)
	sinceSync += dt

	if state == "InRaid" then
		if Config.Match.autoCycle and MatchService.TimeRemaining() <= 0 then
			closeWindow()
			return
		end
	elseif state == "Ended" then
		if Config.Match.autoCycle and os.clock() - endedAt >= Config.Match.debriefTime then
			redeploy()
			return
		end
	end

	if sinceSync >= Config.Match.syncInterval then
		sinceSync = 0
		broadcast()
	end
end

-- --------------------------------------------------------------- Debug ---

-- Sans cette affordance, verifier la fermeture du contrat demanderait
-- d'attendre vingt-cinq minutes. C'est exactement le genre de chemin qu'on
-- ne teste jamais, et donc exactement celui qui casse en production.
local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local ServerStorage = game:GetService("ServerStorage")

	local existing = ServerStorage:FindFirstChild("DebugMatch")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugMatch"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: string?, argument: string?): string
		if action == "close" then
			if state ~= "InRaid" then
				return `rien a fermer, etat {state}`
			end
			closeWindow()
			return "fenetre fermee"
		end

		if action == "redeploy" then
			redeploy()
			return "redeploye"
		end

		if action == "window" then
			local seconds = tonumber(argument or "")
			if not seconds then
				return "usage : window <secondes restantes>"
			end
			-- On recule la date de debut : la fenetre expirera d'elle-meme
			-- par le chemin normal, ce qui est le seul interessant a tester.
			startedAt = os.clock() - (Config.Match.windowDuration - seconds)
			broadcast()
			return `il reste {math.floor(MatchService.TimeRemaining())}s`
		end

		return table.concat({
			`etat : {state}`,
			`restant : {math.floor(MatchService.TimeRemaining())}s / {Config.Match.windowDuration}s`,
			`cycle automatique : {tostring(Config.Match.autoCycle)}`,
			`joueurs extraits : {(function()
				local count = 0
				for _, player in Players:GetPlayers() do
					if player:GetAttribute("Extracted") == true then
						count += 1
					end
				end
				return count
			end)()}/{#Players:GetPlayers()}`,
			"actions : status | close | redeploy | window <secondes>",
		}, "\n")
	end

	log:info('debug : ServerStorage.DebugMatch:Invoke("status"|"close"|"redeploy"|"window <s>")')
end

-- -------------------------------------------------------- Cycle de vie ---

function MatchService.Init(context: ServiceContext)
	ctx = context
end

function MatchService.Start()
	-- Pas de lobby pour l'instant : on entre directement en raid, sinon rien
	-- n'est jouable et l'extraction serait refusee d'office.
	MatchService.SetState("InRaid")

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(tick, dt)
		if not ok then
			log:error(`tick a leve -> {err}`)
		end
	end)

	-- Un client qui arrive en cours de partie doit connaitre l'horloge : le
	-- HUD affiche la fenetre des la premiere image, sinon il montre un
	-- compteur vide pendant quinze secondes.
	Players.PlayerAdded:Connect(function()
		broadcast()
	end)

	installDebug()
	log:info(`pret — fenetre de contrat de {Config.Match.windowDuration}s`)
end

function MatchService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	state = "Ended"
	Signal.clear(MatchService.WindowClosing)
	Signal.clear(MatchService.Redeployed)
	Signal.clear(MatchService.Forfeited)
end

return MatchService
