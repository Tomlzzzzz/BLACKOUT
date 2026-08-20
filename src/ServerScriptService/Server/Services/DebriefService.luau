--!strict
-- Rapport de fin de raid.
--
-- Le moment le plus important d'un jeu d'extraction ne produisait rien :
-- sortir par une zone affichait « EXTRACTED +250 » en bas d'ecran pendant
-- deux secondes, mourir n'affichait rien du tout, et la fermeture de la
-- fenetre de contrat non plus. Tout le raid — ce qu'on a ramene, ce qu'on a
-- perdu, ce qu'on a traverse — disparaissait sans etre raconte.
--
-- Ce service observe les trois sorties possibles, rassemble ce que les
-- autres services savent deja, et envoie UN rapport au seul joueur
-- concerne.
--
-- CE QU'IL N'EST PAS
--
-- Il ne calcule aucune recompense et n'accorde rien. Les credits sont deja
-- verses par EconomyService quand il recoit le signal, le sac est deja
-- perdu quand il apprend la mort. Il compile, il ne decide pas — et c'est
-- pour cela qu'il peut se brancher en dernier sans risquer de changer une
-- issue.
--
-- CE QU'IL MESURE LUI-MEME
--
-- Deux choses seulement, parce que personne d'autre ne les tenait :
--
--   les eliminations DE LA SORTIE  — la statistique du profil est
--                                    cumulative, on en prend la difference
--   le butin ramasse               — compte des piles entrees dans le sac
--
-- Tout le reste (duree, pic de menace, degats encaisses, contrat) est lu
-- chez son proprietaire au moment du rapport.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Debrief = require(Shared.Debrief)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type RaidOutcome = Types.RaidOutcome
type ItemStack = Types.ItemStack

local DebriefService = {}

DebriefService.Name = "DebriefService"

-- Demarre APRES tout le monde. Il s'abonne aux signaux des autres services :
-- ils doivent exister quand il les cherche.
DebriefService.Priority = 90

local log = Logger.new("Debrief")
local ctx: ServiceContext?
local connections: { RBXScriptConnection } = {}
local signalConnections: { any } = {}

-- Etat de la sortie en cours, par joueur.
type RunState = {
	killsAtStart: number,
	looted: number,
	reported: boolean,
}

local runs: { [Player]: RunState } = {}

local function service(name: string): any?
	local context = ctx
	return context and context.Get(name)
end

local function fire(player: Player, ...: any)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("RaidReport")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, ...)
	end
end

local function profileOf(player: Player): Types.PlayerProfile?
	local data = service("DataService")
	return if data then (data :: any).GetProfile(player) else nil
end

local function lifetimeKills(player: Player): number
	local profile = profileOf(player)
	return if profile then profile.Statistics.Kills else 0
end

-- ------------------------------------------------------------- Sessions --

-- Ouvre une sortie. Appele a l'entree du joueur et a chaque redeploiement :
-- un rapport ne doit jamais melanger deux fenetres de contrat.
local function beginRun(player: Player)
	local state: RunState = {
		killsAtStart = lifetimeKills(player),
		looted = 0,
		reported = false,
	}
	runs[player] = state

	-- Le profil n'est pas encore charge a l'instant ou un joueur entre. Lire
	-- ses eliminations maintenant rend 0, et le premier rapport lui
	-- crediterait alors TOUTES ses eliminations depuis son inscription. On
	-- recale la reference des que le profil arrive.
	local data = service("DataService")
	if data and not (data :: any).IsLoaded(player) then
		task.spawn(function()
			for _ = 1, 40 do
				task.wait(0.25)
				-- Une sortie plus recente a ete ouverte entre-temps : ce
				-- recalage ne la concerne plus.
				if runs[player] ~= state then
					return
				end
				if (data :: any).IsLoaded(player) then
					state.killsAtStart = lifetimeKills(player)
					return
				end
			end
		end)
	end

	local playerService = service("PlayerService")
	if playerService then
		pcall(function()
			(playerService :: any).ResetDamageTaken(player)
		end)
	end
end

-- ------------------------------------------------------------- Rapport ---

type Extra = {
	zone: string?,
	duration: number?,
	manifest: { ItemStack },
	leftBehind: { ItemStack }?,
	bonus: number?,
	credits: number?,
	xpGained: number?,
	level: number?,
	leveledUp: boolean?,
}

local function send(player: Player, outcome: RaidOutcome, extra: Extra)
	local run = runs[player]

	-- UN SEUL rapport par sortie.
	--
	-- Les chemins peuvent se croiser : un joueur tue a la seconde ou la
	-- fenetre se ferme declenche `Died` puis `Forfeited`. Sans ce verrou il
	-- recevrait deux ecrans, dont le second annoncerait une perte deja
	-- comptee — et le premier serait le bon.
	if run and run.reported then
		return
	end
	if run then
		run.reported = true
	end

	local profile = profileOf(player)
	local threat = service("ThreatService")
	local playerService = service("PlayerService")
	local mission = service("MissionService")

	local kills = 0
	if run then
		kills = math.max(0, lifetimeKills(player) - run.killsAtStart)
	end

	local report = Debrief.build({
		outcome = outcome,
		userId = player.UserId,
		raids = if profile then profile.Statistics.Raids else 0,
		duration = extra.duration or 0,

		manifest = extra.manifest,
		leftBehind = extra.leftBehind,

		bonus = extra.bonus,
		credits = extra.credits,
		xpGained = extra.xpGained,
		level = if extra.level then extra.level elseif profile then profile.Level else 1,
		leveledUp = extra.leveledUp,
		balance = if profile then profile.Credits else 0,

		zone = extra.zone,
		kills = kills,
		damageTaken = if playerService then (playerService :: any).GetDamageTaken(player) else 0,
		peakThreat = if threat then (threat :: any):GetPeak() else 0,
		contract = if mission then (mission :: any).GetContract(player) else nil,
	})

	fire(player, report)

	log:info(
		`{player.Name} : {outcome} — {report.manifestValue} cr au manifeste, `
			.. `note {report.rating}, {#report.manifest} ligne(s)`
	)
end

-- ---------------------------------------------------------- Abonnements --

local function bindSignals()
	local extraction = service("ExtractionService")
	local playerService = service("PlayerService")
	local match = service("MatchService")
	local inventory = service("InventoryService")

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

	subscribe(extraction, "Completed", function(player: Player, zone: string, reward: any, summary: any, duration: number?)
		send(player, "EXTRACTED", {
			zone = zone,
			duration = duration,
			manifest = if summary then summary.moved else {},
			leftBehind = if summary then summary.leftBehind else nil,
			bonus = reward and reward.bonus,
			credits = reward and reward.credits,
			xpGained = reward and reward.xpGained,
			level = reward and reward.level,
			leveledUp = reward and reward.leveledUp,
		})
	end)

	subscribe(playerService, "Died", function(player: Player, _lostValue: number, lostStacks: { ItemStack }, duration: number?)
		send(player, "KIA", {
			duration = duration,
			manifest = lostStacks or {},
		})
	end)

	subscribe(match, "Forfeited", function(player: Player, _lostValue: number, lostStacks: { ItemStack }, startedAt: number?)
		send(player, "EXPIRED", {
			duration = if startedAt then math.floor(os.clock() - startedAt) else 0,
			manifest = lostStacks or {},
		})
	end)

	-- Nouvelle fenetre : tout le monde repart d'un compteur neuf.
	subscribe(match, "Redeployed", function()
		for _, player in Players:GetPlayers() do
			beginRun(player)
		end
	end)

	subscribe(inventory, "ItemAdded", function(player: Player)
		local run = runs[player]
		if run then
			run.looted += 1
		end
	end)
end

-- --------------------------------------------------------------- Debug ---

local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local ServerStorage = game:GetService("ServerStorage")

	local existing = ServerStorage:FindFirstChild("DebugDebrief")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugDebrief"
	bindable.Parent = ServerStorage

	-- Sans cette affordance, voir l'ecran de mort demanderait de mourir, et
	-- l'ecran d'expiration d'attendre vingt-cinq minutes. Les trois issues
	-- doivent pouvoir etre regardees cote a cote.
	bindable.OnInvoke = function(outcome: string?, mode: string?): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "aucun joueur"
		end

		local wanted = string.upper(outcome or "EXTRACTED")
		if wanted ~= "EXTRACTED" and wanted ~= "KIA" and wanted ~= "EXPIRED" then
			return "usage : EXTRACTED | KIA | EXPIRED"
		end

		-- Par defaut on recopie le sac REEL : le rapport montre ce que le
		-- joueur porte vraiment.
		--
		-- Le mode « full » remplit un manifeste dense a la place. Il ne sert
		-- qu'a une chose, mais elle est necessaire : verifier la mise en page
		-- SATUREE — troncature, ligne d'agregation, alignement des montants a
		-- cinq chiffres. Un sac de depart contient une arme, et une arme ne
		-- prouve rien sur une colonne de huit lignes.
		local stacks: { ItemStack } = {}

		if string.lower(mode or "") == "full" then
			for _, sample in {
				{ id = "prototype_core", quantity = 1 },
				{ id = "black_box", quantity = 1 },
				{ id = "graphics_card", quantity = 3 },
				{ id = "gold_chain", quantity = 2 },
				{ id = "military_battery", quantity = 2 },
				{ id = "weapon_parts", quantity = 4 },
				{ id = "keycard_blue", quantity = 1 },
				{ id = "armor_plate", quantity = 2 },
				{ id = "ammo_762", quantity = 60 },
				{ id = "scrap_metal", quantity = 11 },
			} do
				table.insert(stacks, sample)
			end
		else
			local inventory = service("InventoryService")
			local contents = if inventory then (inventory :: any).GetContents(player) else {}
			for _, item in contents do
				table.insert(stacks, { id = item.id, quantity = item.quantity })
			end
		end

		-- Le verrou « un seul rapport par sortie » est leve avant, puis REPOSE
		-- apres. Sans la remise en place, un rapport de demonstration
		-- consommerait la sortie en cours : la vraie mort ou la vraie
		-- fermeture de fenetre qui suivraient n'afficheraient plus rien, et
		-- l'outil de debug ferait croire a une panne du chemin reel.
		local run = runs[player]
		local wasReported = run ~= nil and run.reported
		if run then
			run.reported = false
		end

		send(player, wanted :: RaidOutcome, {
			zone = "NORTH GATE",
			duration = 754,
			manifest = stacks,
			bonus = 250,
			credits = 1250,
			xpGained = 120,
			leveledUp = wanted == "EXTRACTED",
		})

		if run then
			run.reported = wasReported
		end

		return `rapport {wanted} envoye a {player.Name} ({#stacks} pile(s))`
	end

	log:info('debug : ServerStorage.DebugDebrief:Invoke("EXTRACTED"|"KIA"|"EXPIRED", "full"?)')
end

-- -------------------------------------------------------- Cycle de vie ---

function DebriefService.Init(context: ServiceContext)
	ctx = context
end

function DebriefService.Start()
	bindSignals()

	-- Une mort n'arrete pas la fenetre de contrat : le joueur reapparait et
	-- continue le meme raid. Sans cette reouverture, sa sortie resterait
	-- marquee « deja rapportee » et la fermeture de la fenetre, vingt
	-- minutes plus tard, ne produirait plus rien du tout.
	--
	-- On ne reouvre QUE si un rapport est deja parti : la reapparition
	-- ordinaire du debut de partie ne doit pas remettre les compteurs a
	-- zero.
	local respawnConnections: { [Player]: RBXScriptConnection } = {}

	local function watch(player: Player)
		beginRun(player)

		local existing = respawnConnections[player]
		if existing then
			existing:Disconnect()
		end
		respawnConnections[player] = player.CharacterAdded:Connect(function()
			local run = runs[player]
			if run and run.reported then
				beginRun(player)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(watch))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			runs[player] = nil
			local connection = respawnConnections[player]
			if connection then
				connection:Disconnect()
				respawnConnections[player] = nil
			end
		end)
	)

	-- Acquittement du rapport. Purement declaratif : on ne fait qu'en
	-- prendre note. Le client peut mentir tant qu'il veut, il ne gagne
	-- rien — aucune recompense ne depend de ce message.
	local remote = ctx and ctx.Remotes:FindFirstChild("AcknowledgeReport")
	if remote and remote:IsA("RemoteEvent") then
		table.insert(
			connections,
			remote.OnServerEvent:Connect(function(player: Player)
				log:info(`{player.Name} a acquitte son rapport`)
			end)
		)
	end

	installDebug()
	log:info("pret — extraction, mort et fenetre fermee produisent un rapport")
end

function DebriefService.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	for _, connection in signalConnections do
		Signal.disconnect(connection)
	end
	table.clear(signalConnections)
	table.clear(runs)
end

return DebriefService
