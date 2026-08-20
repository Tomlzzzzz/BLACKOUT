--!strict
-- Le commanditaire, cote serveur.
--
-- Ce service n'invente aucun evenement. Il s'abonne a ce qui se passe
-- reellement — un objet entre dans le sac, la menace monte d'un palier, un
-- equipier tombe, la fenetre se referme — et laisse Shared.Handler decider
-- s'il y a lieu de parler.
--
-- La separation compte : toute la logique de cadence, de priorite et de
-- silence est pure et testee sans partie ; ici il ne reste que du cablage.
--
-- POURQUOI CE SERVICE EXISTE
--
-- Le GDD dit que des entreprises privees envoient les Scavengers en zone.
-- Sans ce service, cette phrase n'existe nulle part dans le jeu : le joueur
-- ramasse des objets pour lui-meme, personne ne le regarde, personne ne
-- compte. La surveillance est ce qui transforme du pillage en travail.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Handler = require(Shared.Handler)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type Transmission = Types.Transmission

local HandlerService = {}

HandlerService.Name = "HandlerService"
-- Apres les systemes qu'il ecoute (Threat 65, Extraction 70), avant
-- l'analytique. Il ne fournit rien a personne : il n'a besoin d'etre tot
-- pour aucun autre service.
HandlerService.Priority = 90

local log = Logger.new("Handler")
local ctx: ServiceContext?

local states: { [Player]: Handler.State } = {}

-- Anti-rafale par joueur. Une meute de six crawlers ou une rafale
-- automatique produiraient sinon une ligne par entite et par tir.
local lastContactAt: { [Player]: number } = {}
local lastGunfireAt: { [Player]: number } = {}
local lastDistrict: { [Player]: string } = {}
local contactAccumulator = 0

-- Compteurs de diagnostic. Un releve qui ne part pas peut avoir trois causes
-- indiscernables de l'exterieur : la boucle ne tourne pas, elle tourne mais ne
-- voit rien, ou elle voit et le message est abandonne. Ces trois compteurs
-- les separent.
local diagTicks = 0
local diagScans = 0
local diagSent = 0
local connections: { RBXScriptConnection } = {}
local subscriptions: { any } = {}
local heartbeat: RBXScriptConnection?
local accumulator = 0

-- Cadence de la boucle lente. Rien ici n'a besoin d'une image : les rappels
-- de rendement se comptent en dizaines de secondes.
local TICK_INTERVAL = 1

-- Secteur cardinal a partir d'un cap absolu.
--
-- On envoie une CLE (« sector.2 »), pas « E » : le secteur se traduit comme
-- le reste, et « O » en francais n'est pas « W » en anglais. Le repere est
-- celui de la boussole du HUD — le joueur lit « secteur NE » et tourne la
-- tete au bon endroit.
local function sectorKey(bearing: number): string
	local index = math.floor(((bearing % 360) + 22.5) / 45) % 8
	return `sector.{index}`
end

local function service(name: string): any?
	local context = ctx
	return context and context.Get(name)
end

-- ------------------------------------------------------------ Emission ---

local function send(player: Player, transmission: Transmission?)
	if not transmission then
		return
	end

	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("HandlerTransmission")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, transmission)
	end
end

-- Applique la meme decision a tout le monde. Les paliers de menace sont
-- globaux au serveur : six Scavengers partagent la meme ville, ils doivent
-- recevoir la meme annonce.
local function forEachState(apply: (Player, Handler.State) -> Transmission?)
	for player, state in states do
		local ok, result = pcall(apply, player, state)
		if ok then
			send(player, result)
		else
			log:error(`transmission vers {player.Name} a leve -> {result}`)
		end
	end
end

-- --------------------------------------------------------- Matricules ----

-- Meme calcul que cote client (Hud.tagFor) : le bureau et le HUD doivent
-- nommer un actif de la meme facon, sinon le joueur lit deux identites pour
-- une seule personne.
local function tagFor(userId: number): string
	return string.format("%s-%04d", Config.Handler.assetPrefix, userId % 10000)
end

-- ------------------------------------------------------- Par joueur ------

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	table.insert(
		connections,
		humanoid.HealthChanged:Connect(function(health)
			local state = states[player]
			if not state or humanoid.MaxHealth <= 0 then
				return
			end
			send(player, Handler.healthChanged(state, health / humanoid.MaxHealth, os.clock()))
		end)
	)

	table.insert(
		connections,
		humanoid.Died:Connect(function()
			-- La perte est annoncee aux AUTRES. Celui qui meurt a deja son
			-- ecran de mort ; lui envoyer un constat comptable sur sa propre
			-- disparition serait du bruit.
			local tag = tagFor(player.UserId)
			for other, state in states do
				if other ~= player then
					send(other, Handler.submit(state, "teammateDown", os.clock(), { tag = tag }))
				end
			end
		end)
	)
end

local function onPlayerAdded(player: Player)
	local now = os.clock()
	local state = Handler.new(now)
	states[player] = state

	send(player, Handler.submit(state, "deploy", now))

	if player.Character then
		watchCharacter(player, player.Character)
	end
	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
	)
end

local function onPlayerRemoving(player: Player)
	states[player] = nil
end

-- --------------------------------------------------------- Abonnements ---

local function subscribe()
	local inventory = service("InventoryService")
	local threat = service("ThreatService")
	local extraction = service("ExtractionService")
	local match = service("MatchService")
	local missions = service("MissionService")
	local enemies = service("EnemyService")
	local combat = service("CombatService")
	local world = service("WorldService")

	-- Production. Le seul evenement qui prouve que l'actif travaille.
	if inventory then
		table.insert(
			subscriptions,
			Signal.connect(inventory.ItemAdded, function(player: Player, _itemId: string, _quantity: number, value: number)
				local state = states[player]
				if not state then
					return
				end

				local now = os.clock()

				-- La progression d'objectif appartient a MissionService. Ici
				-- on ne fait que constater que l'actif produit.
				send(player, Handler.recordLoot(state, now))

				-- Le palier de cargaison se commente apres le ramassage :
				-- l'ordre donne « article inventorie » puis « cargaison non
				-- assuree », qui est la lecture naturelle.
				send(player, Handler.cargoChanged(state, value, now))
			end)
		)
	end

	-- Menace. Globale au serveur.
	if threat then
		table.insert(
			subscriptions,
			Signal.connect(threat.BandChanged, function(change: Types.ThreatChange)
				forEachState(function(_, state)
					return Handler.bandChanged(state, change.band, os.clock())
				end)
			end)
		)

		table.insert(
			subscriptions,
			Signal.connect(threat.HuntEnded, function()
				forEachState(function(_, state)
					return Handler.submit(state, "huntEnd", os.clock())
				end)
			end)
		)
	end

	-- Extraction.
	if extraction then
		table.insert(
			subscriptions,
			Signal.connect(extraction.Completed, function(player: Player, _zone: string, reward: any)
				local state = states[player]
				if state then
					send(player, Handler.submit(state, "extractionDone", os.clock(), {
						credits = math.floor(reward.credits or 0),
					}))
				end

				local tag = tagFor(player.UserId)
				for other, otherState in states do
					if other ~= player then
						send(other, Handler.submit(otherState, "teammateExtracted", os.clock(), { tag = tag }))
					end
				end
			end)
		)

		table.insert(
			subscriptions,
			Signal.connect(extraction.Cancelled, function(player: Player)
				local state = states[player]
				if state then
					send(player, Handler.submit(state, "extractionLost", os.clock()))
				end
			end)
		)

		table.insert(
			subscriptions,
			Signal.connect(extraction.ZonesRotated, function(open: { string })
				if #open == 0 then
					return
				end
				forEachState(function(_, state)
					return Handler.submit(state, "extractionOpen", os.clock(), { zone = open[1] })
				end)
			end)
		)
	end

	-- Fenetre de contrat.
	-- ------------------------------------------------------ Capteurs ----
	--
	-- Tout ce qui suit repond a un FAIT mesure serveur. C'est ce qui remplace
	-- les anciennes transmissions d'ambiance : le joueur doit pouvoir se fier
	-- a chaque ligne, sinon il cesse de toutes les lire.

	-- Un ennemi vient de verrouiller CE joueur. Le plus urgent des releves :
	-- il ne dit pas « il y a du danger », il dit « il vient pour toi ».
	if enemies then
		table.insert(
			subscriptions,
			Signal.connect(enemies.TargetAcquired, function(player: Player, position: Vector3, isBoss: boolean)
				local state = states[player]
				if not state then
					return
				end

				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local fields: { [string]: any } = {}

				if root and root:IsA("BasePart") then
					local offset = position - root.Position
					fields.bearing = sectorKey(math.deg(math.atan2(offset.X, -offset.Z)))
				end

				send(player, Handler.submit(state, if isBoss then "heavySignature" else "hunted", os.clock(), fields))
			end)
		)
	end

	-- Coups de feu qui ne sont pas les votres.
	if combat then
		table.insert(
			subscriptions,
			Signal.connect(combat.ShotFired, function(shooter: Player, origin: Vector3)
				local now = os.clock()

				for player, state in states do
					if player == shooter then
						continue
					end

					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					if not root or not root:IsA("BasePart") then
						continue
					end

					local offset = origin - root.Position
					local distance = offset.Magnitude
					if distance > Config.Handler.gunfireRadius then
						continue
					end

					local last = lastGunfireAt[player]
					if last and now - last < Config.Handler.gunfireCooldown then
						continue
					end

					-- Meme regle que pour les contacts : on n'arme le delai
					-- qu'une fois le message reellement produit.
					local transmission = Handler.submit(state, "gunfire", now, {
						bearing = sectorKey(math.deg(math.atan2(offset.X, -offset.Z))),
						distance = math.floor(distance),
					})
					if transmission then
						lastGunfireAt[player] = now
						send(player, transmission)
					end
				end
			end)
		)
	end

	-- Front meteo. Information d'environnement reelle : WorldService pilote
	-- vraiment Lighting derriere.
	if world then
		table.insert(
			subscriptions,
			Signal.connect(world.WeatherChanged, function(weather: string)
				forEachState(function(_, state)
					return Handler.submit(state, "weather", os.clock(), { weather = `world.weather.{weather}` })
				end)
			end)
		)
	end

	-- Contrats. Le bureau commente ce que MissionService decide.
	if missions then
		table.insert(
			subscriptions,
			Signal.connect(missions.ContractAssigned, function(player: Player, contract: any)
				local state = states[player]
				if state then
					send(player, Handler.submit(state, "contractAssigned", os.clock(), {
						title = contract.titleKey,
						reward = contract.reward,
					}))
				end
			end)
		)

		table.insert(
			subscriptions,
			Signal.connect(missions.ObjectiveCompleted, function(player: Player, _contract: any, objective: any)
				local state = states[player]
				if state then
					send(player, Handler.submit(state, "objectiveDone", os.clock(), { objective = objective.labelKey }))
				end
			end)
		)

		table.insert(
			subscriptions,
			Signal.connect(missions.ContractCompleted, function(player: Player, contract: any)
				local state = states[player]
				if state then
					send(player, Handler.submit(state, "contractDone", os.clock(), { reward = contract.reward }))
				end
			end)
		)
	end

	if match then
		table.insert(
			subscriptions,
			Signal.connect(match.WindowClosing, function()
				forEachState(function(_, state)
					return Handler.submit(state, "windowClosed", os.clock())
				end)
			end)
		)

		table.insert(
			subscriptions,
			Signal.connect(match.Redeployed, function()
				-- Nouvelle fenetre, etat neuf : sans cela le second raid
				-- serait muet, tous les `once` ayant deja ete consommes.
				local now = os.clock()
				for player in states do
					states[player] = Handler.new(now)
				end
			end)
		)
	end
end

-- -------------------------------------------------------------- Boucle ---

-- Balayage de proximite. Le serveur est le seul a connaitre la position des
-- ennemis ; c'est lui qui decide ce que le joueur apprend, et a quel rythme.
local function scanContacts(now: number)
	diagScans += 1
	local enemies = service("EnemyService")
	local world = service("WorldService")
	local playerService = service("PlayerService")
	if not enemies then
		return
	end

	for player, state in states do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		-- Changement de district : une information de carte, emise une seule
		-- fois par entree.
		if world then
			local info = world.GetInfo(player)
			if info and lastDistrict[player] and lastDistrict[player] ~= info.district then
				send(player, Handler.submit(state, "district", now, {
					district = `world.district.{info.district}`,
				}))
			end
			lastDistrict[player] = info and info.district
		end

		-- Batterie : une alerte unique, tant qu'il reste le temps d'agir.
		if playerService then
			local vitals = playerService.GetVitals(player)
			if vitals and vitals.maxBattery > 0 then
				local percent = vitals.battery / vitals.maxBattery * 100
				if percent <= Config.Handler.batteryWarnAt then
					send(player, Handler.submit(state, "batteryLow", now, { percent = math.floor(percent) }))
				end
			end
		end

		local last = lastContactAt[player]
		if last and now - last < Config.Handler.contactCooldown then
			continue
		end

		local contacts = enemies.QueryNear(root.Position, Config.Handler.contactRadius)
		local nearest = contacts[1]
		if not nearest then
			continue
		end

		-- Un contact deja en poursuite est annonce par TargetAcquired : le
		-- relayer ici ferait doublon sur le meme evenement.
		if nearest.chasing then
			continue
		end

		local key = if nearest.distance <= Config.Handler.contactCloseRadius then "contactClose" else "contact"
		local transmission = Handler.submit(state, key, now, {
			bearing = sectorKey(nearest.bearing),
			distance = math.floor(nearest.distance),
		})

		-- LE DELAI NE S'ARME QUE SI LE MESSAGE EST REELLEMENT PARTI.
		--
		-- Il etait arme avant l'appel : un releve abandonne par la regle de
		-- cadence — typiquement le tout premier, tombant dans les 2.5 s qui
		-- suivent le message de deploiement — consommait quand meme les
		-- vingt-deux secondes de silence. Le capteur paraissait mort alors
		-- qu'il voyait tout : douze balayages, zero envoi.
		if not transmission then
			continue
		end

		lastContactAt[player] = now
		diagSent += 1
		send(player, transmission)
	end
end

local function tick()
	diagTicks += 1
	local match = service("MatchService")
	local now = os.clock()

	contactAccumulator += TICK_INTERVAL
	if contactAccumulator >= Config.Handler.contactRate then
		contactAccumulator = 0
		local ok, err = pcall(scanContacts, now)
		if not ok then
			log:error(`balayage de proximite a leve -> {err}`)
		end
	end

	local remaining = if match then match.TimeRemaining() else 0
	local running = if match then match.IsRunning() else false

	for player, state in states do
		local ok, err = pcall(function()
			if running then
				send(player, Handler.windowTick(state, remaining, now))
			end
			send(player, Handler.tick(state, now))
		end)
		if not ok then
			log:error(`tick {player.Name} a leve -> {err}`)
		end
	end
end

-- --------------------------------------------------------------- Debug ---

-- Affordance de playtest. Les transmissions se declenchent sur des
-- evenements espaces de plusieurs minutes ; sans ce point d'entree, verifier
-- une seule phrase demanderait de jouer jusqu'a ce qu'elle tombe.
--
-- Studio uniquement, et cote serveur : rien de tout ceci n'est joignable
-- depuis un client.
local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local ServerStorage = game:GetService("ServerStorage")

	local existing = ServerStorage:FindFirstChild("DebugHandler")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugHandler"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: string?, argument: string?): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "aucun joueur"
		end
		local state = states[player]
		if not state then
			return "aucun etat pour ce joueur"
		end

		if action == "say" and argument then
			-- On force la transmission en effacant la fenetre de silence :
			-- sinon une phrase demandee a la main serait abandonnee par la
			-- regle de cadence et on croirait a un bug.
			state.lastAt = -math.huge
			state.lastPriority = 0
			state.seen[argument] = nil
			local transmission = Handler.submit(state, argument, os.clock(), {
				tag = tagFor(player.UserId),
				cargo = 12345,
				credits = 4200,
				zone = "NORD",
				seconds = 60,
				minutes = 5,
				quantity = 2,
				item = "Batterie militaire",
				reward = 1200,
			})
			send(player, transmission)
			-- `text` n'existe plus depuis le passage aux cles de localisation :
			-- la sonde affichait « envoye : nil » alors que l'envoi marchait.
			return if transmission
				then `envoye : {transmission.textKey}`
				else `cle inconnue ou muette : {argument}`
		end

		-- Etat du balayage de proximite. Sans cette sonde, un releve qui ne
		-- part pas est indiscernable d'un releve qui part et se perd.
		if action == "scan" then
			local enemies = service("EnemyService")
			if not enemies then
				return "EnemyService introuvable"
			end

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root then
				return "pas de personnage"
			end

			local contacts = enemies.QueryNear(root.Position, Config.Handler.contactRadius)

			-- Calcule AVANT la chaine. Une expression `if` avec des guillemets
			-- imbriquee dans une interpolation Luau ne compile pas, et l'erreur
			-- ne pointe pas la bonne ligne : le service entier avait cesse de
			-- se charger sans que rien ne le dise a part un « 15/15 services »
			-- au lieu de 16.
			local since = "jamais"
			local last = lastContactAt[player]
			if last then
				since = string.format("%.1fs", os.clock() - last)
			end

			local lines = {
				`ticks : {diagTicks}   balayages : {diagScans}   releves emis : {diagSent}`,
				`rayon : {Config.Handler.contactRadius}   contacts : {#contacts}`,
				`dernier releve : {since}`,
			}
			for index, contact in contacts do
				if index <= 4 then
					table.insert(
						lines,
						string.format(
							"  %5.1f studs  secteur %s  poursuite=%s  boss=%s",
							contact.distance,
							sectorKey(contact.bearing),
							tostring(contact.chasing),
							tostring(contact.isBoss)
						)
					)
				end
			end
			return table.concat(lines, "\n")
		end

		if action == "silence" then
			state.silenced = not state.silenced
			return `silence = {tostring(state.silenced)}`
		end

		return table.concat({
			`bureau : {Config.Handler.desk} / {Config.Handler.company}`,
			`actif : {tagFor(player.UserId)}`,
			`silencieux : {tostring(state.silenced)}`,
			`palier cargaison : {state.cargoTier}  palier menace : {state.bandIndex}`,
			`inactif depuis : {math.floor(os.clock() - state.lastLootAt)}s`,
		}, "\n")
	end

	log:info('debug : ServerStorage.DebugHandler:Invoke("status"|"say <cle>"|"scan"|"silence")')
end

-- -------------------------------------------------------- Cycle de vie ---

function HandlerService.Init(context: ServiceContext)
	ctx = context
end

function HandlerService.Start()
	subscribe()

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		accumulator = 0
		tick()
	end)

	installDebug()
	log:info(`pret — {Config.Handler.desk} / {Config.Handler.company}`)
end

function HandlerService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, subscription in subscriptions do
		Signal.disconnect(subscription)
	end
	table.clear(subscriptions)
	table.clear(states)
	table.clear(lastContactAt)
	table.clear(lastGunfireAt)
	table.clear(lastDistrict)
end

return HandlerService
