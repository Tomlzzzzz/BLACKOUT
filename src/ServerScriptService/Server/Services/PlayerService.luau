--!strict
-- Cycle de vie joueur et endurance.
--
-- L'endurance est calculee a partir de la VELOCITE REELLE du personnage,
-- mesuree serveur. Aucune entree client n'entre dans le calcul : un client
-- modifie pourrait annoncer qu'il marche en sprintant, il ne peut pas
-- mentir sur le deplacement que le serveur observe.
--
-- Ce service est aussi celui qui envoie l'instantane initial au HUD, pour
-- qu'il ne demarre pas vide en attendant qu'un evenement se produise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Stamina = require(Shared.Stamina)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

type ServiceContext = Types.ServiceContext
type StaminaState = Types.StaminaState

local PlayerService = {}

PlayerService.Name = "PlayerService"
PlayerService.Priority = 20

-- Signal serveur.
--
--   Died  emis APRES la perte du sac, avec ce qui vient d'etre perdu. Le
--         rapport de fin en a besoin pour nommer la cargaison : la lire
--         apres coup donnerait un sac deja vide.
PlayerService.Died = Signal.new()

local log = Logger.new("PlayerService")
local ctx: ServiceContext?

-- Degats encaisses depuis le debut de la fenetre de contrat, par joueur.
--
-- Compte les degats BRUTS, armure comprise : c'est ce que le joueur a pris,
-- pas ce qui a franchi sa protection. Un rapport qui n'en compterait que la
-- part passee a la vie recompenserait l'armure deux fois.
local damageTaken: { [Player]: number } = {}

local staminas: { [Player]: StaminaState } = {}

-- Armure et batterie. Memes proprietaires que l'endurance : ce sont les
-- vitaux du joueur, ils ne quittent jamais le serveur autrement que par une
-- diffusion en lecture seule.
local vitals: { [Player]: Types.Vitals } = {}
local vitalsPushAccumulator = 0
local vitalsDirty: { [Player]: boolean } = {}

-- Le joueur MAINTIENT-il la touche de course ? Une intention, pas un droit :
-- le serveur decide ensuite s'il accelere reellement.
local sprintIntent: { [Player]: boolean } = {}

-- Meme chose pour l'accroupi. L'attribut `Crouched` qui en decoule est pose
-- par le SERVEUR : les creatures le lisent pour reduire leur portee de
-- detection, et un client qui pourrait le poser lui-meme se declarerait
-- accroupi en pleine course.
local crouchIntent: { [Player]: boolean } = {}

-- VERROU D'EPUISEMENT : il faut RELACHER la touche pour repartir.
--
-- Sans lui, garder Maj enfonce produisait une scie. La course s'arrete a
-- bout de souffle, la jauge remonte, l'hysteresis la rend a un quart — et la
-- touche etant toujours tenue, la course repartait aussitot pour retomber
-- deux secondes plus tard. Le joueur restait coince entre 5 et 25 sur une
-- barre de 100 : a l'ecran, une jauge collee en bas qui ne bouge plus.
-- « Quand une touche est enfoncee ca la fige. »
--
-- Le verrou se pose a l'epuisement et ne se leve qu'au relachement de la
-- touche. C'est aussi la bonne regle de jeu : une fois hors d'haleine, on
-- reprend son souffle, on ne repart pas par a-coups.
local sprintLocked: { [Player]: boolean } = {}
local connections: { RBXScriptConnection } = {}

-- Une connexion Died par joueur, remplacee a chaque reapparition.
--
-- La version precedente empilait chaque nouvelle connexion dans
-- `connections`, jamais purgee avant Stop() : sur un serveur qui tourne des
-- heures, la table grossissait d'une entree morte a chaque mort de chaque
-- joueur.
local deathConnections: { [Player]: RBXScriptConnection } = {}

-- Meme regle que ci-dessus : une connexion par joueur, remplacee a chaque
-- apparition. L'empiler dans `connections` ferait grossir la table d'une
-- entree morte a chaque reapparition.
local regenConnections: { [Player]: RBXScriptConnection } = {}

-- Temps de jeu non encore verse au profil.
--
-- Verse des qu'une seconde entiere est accumulee. Un palier plus large
-- serait tentant, mais DataService se connecte a PlayerRemoving avant ce
-- service (Priority 10 contre 20) et sauvegarde donc en premier : tout ce
-- qui reste en attente au depart du joueur est perdu. A une seconde, la
-- perte maximale est d'une seconde ; a quinze, elle etait de quinze.
local PLAYTIME_FLUSH = 1
local pendingPlaytime: { [Player]: number } = {}
local heartbeat: RBXScriptConnection?
local accumulator = 0

local function fire(remoteName: string, player: Player, ...: any)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, ...)
	end
end

-- ------------------------------------------------------------- Snapshot ---

local function sendSnapshot(player: Player)
	local context = ctx
	if not context then
		return
	end

	local economy = context.Get("EconomyService")
	local threat = context.Get("ThreatService")
	local inventory = context.Get("InventoryService")
	local state = staminas[player]

	local vital = vitals[player]

	local snapshot: Types.HudSnapshot = {
		credits = if economy then (economy :: any).GetCredits(player) else 0,
		threat = if threat then (threat :: any):GetThreat() else 0,
		band = if threat then (threat :: any):GetState() else "SAFE",
		stamina = if state then state.value else Config.Player.stamina.max,
		maxStamina = Config.Player.stamina.max,
		equipped = if inventory then (inventory :: any).GetEquipped(player) else nil,
	}

	fire("HudSnapshot", player, snapshot)

	-- Les vitaux partent dans leur propre canal : ils changent bien plus
	-- souvent que l'instantane et n'ont pas a le faire grossir.
	if vital then
		fire("VitalsChanged", player, vital)
	end
end

-- ------------------------------------------------- Armure et batterie ----

local function pushVitals(player: Player)
	local vital = vitals[player]
	if vital then
		fire("VitalsChanged", player, vital)
		vitalsDirty[player] = nil
	end
end

function PlayerService.GetVitals(player: Player): Types.Vitals?
	return vitals[player]
end

-- Recharge d'armure ou de batterie. Renvoie ce qui a REELLEMENT ete
-- consomme : un ramassage sur une jauge pleine ne doit pas detruire l'item.
function PlayerService.AddArmor(player: Player, amount: number): number
	local vital = vitals[player]
	if not vital or amount <= 0 then
		return 0
	end
	local before = vital.armor
	vital.armor = math.clamp(vital.armor + amount, 0, vital.maxArmor)
	vitalsDirty[player] = true
	return vital.armor - before
end

function PlayerService.AddBattery(player: Player, amount: number): number
	local vital = vitals[player]
	if not vital or amount <= 0 then
		return 0
	end
	local before = vital.battery
	vital.battery = math.clamp(vital.battery + amount, 0, vital.maxBattery)
	vitalsDirty[player] = true
	return vital.battery - before
end

function PlayerService.SetLight(player: Player, on: boolean)
	local vital = vitals[player]
	if not vital then
		return
	end
	-- Batterie vide : la lampe refuse de s'allumer. C'est la seule regle qui
	-- donne du poids a la jauge.
	if on and vital.battery <= 0 then
		return
	end
	if vital.lightOn ~= on then
		vital.lightOn = on
		pushVitals(player)
	end
end

-- POINT D'ENTREE UNIQUE DES DEGATS JOUEUR.
--
-- Existe pour que l'armure ait un seul endroit ou s'interposer. Avant, chaque
-- source appelait humanoid:TakeDamage directement ; ajouter l'armure aurait
-- voulu dire la reimplementer dans chaque appelant, et en oublier un.
--
-- Renvoie le rapport envoye au client pour le retour visuel. Le client ne
-- fait qu'illustrer : la vie est deja appliquee ici.
function PlayerService.ApplyDamage(
	player: Player,
	amount: number,
	source: string?,
	origin: Vector3?
): Types.DamageReport?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid.Health <= 0 or amount <= 0 then
		return nil
	end
	if player:GetAttribute("Extracted") == true then
		return nil
	end

	local settings = Config.Vitals.armor
	local vital = vitals[player]

	local toArmor = 0
	local toHealth = amount

	if vital and vital.armor > 0 then
		-- L'armure absorbe une fraction du coup, dans la limite de ce qui
		-- lui reste. Le reliquat passe toujours a la vie : encaisser doit
		-- se voir meme protege.
		local wanted = amount * settings.absorption
		toArmor = math.min(vital.armor, wanted)
		vital.armor -= toArmor
		toHealth = amount - toArmor
		vitalsDirty[player] = true
	end

	humanoid:TakeDamage(toHealth)
	damageTaken[player] = (damageTaken[player] or 0) + amount

	local maxHealth = if humanoid.MaxHealth > 0 then humanoid.MaxHealth else 100
	local lostFraction = toHealth / maxHealth
	local remainingFraction = humanoid.Health / maxHealth

	local severity = "light"
	if lostFraction >= Config.Hud.damage.criticalAbove or remainingFraction <= Config.Hud.damage.criticalBelowHealth then
		severity = "critical"
	elseif lostFraction >= Config.Hud.damage.heavyAbove then
		severity = "heavy"
	end

	local report: Types.DamageReport = {
		amount = amount,
		toArmor = toArmor,
		toHealth = toHealth,
		remaining = humanoid.Health,
		severity = severity,
		source = source,
		origin = origin,
	}

	fire("DamageTaken", player, report)
	if vitalsDirty[player] then
		pushVitals(player)
	end

	return report
end

-- Consommation de la lampe. Appelee par la boucle lente, jamais par image.
local function updateBattery(player: Player, dt: number)
	local vital = vitals[player]
	if not vital then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if player:GetAttribute("Extracted") == true then
		return
	end

	local settings = Config.Vitals.battery
	local drain = if vital.lightOn then settings.drainPerSecond else settings.idleDrainPerSecond
	local before = vital.battery
	vital.battery = math.max(0, vital.battery - drain * dt)

	if vital.battery <= 0 and vital.lightOn then
		vital.lightOn = false
		log:info(`{player.Name} : batterie epuisee, lampe coupee`)
		pushVitals(player)
		return
	end

	-- Un dixieme de point suffit a marquer la jauge sale : on evite de
	-- diffuser a chaque tick pour une variation invisible.
	if math.floor(before * 10) ~= math.floor(vital.battery * 10) then
		vitalsDirty[player] = true
	end
end

-- -------------------------------------------------------------- Endurance ---

local function updateStamina(player: Player, dt: number, now: number)
	local state = staminas[player]
	if not state then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Vitesse horizontale : une chute ne doit pas passer pour un effort.
	local velocity = root.AssemblyLinearVelocity
	local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)

	local wasExhausted = state.exhausted

	-- ORDRE : ON DECIDE D'ABORD, ON CONSOMME ENSUITE.
	--
	-- L'arbitrage se faisait APRES le calcul d'endurance, qui deduisait
	-- l'effort de la vitesse mesuree. Les deux pouvaient diverger, et la
	-- jauge ne bougeait pas pendant la course.
	local sprint = Config.Player.sprint
	local crouch = Config.Player.crouch

	-- L'ACCROUPI PRIME SUR LA COURSE. On ne sprinte pas accroupi : laisser
	-- les deux se cumuler donnerait le meilleur des deux mondes — la
	-- discretion et la vitesse — et viderait la decision de son sens.
	local crouching = crouchIntent[player] == true
	local wantsSprint = not crouching
		and sprintIntent[player] == true
		and not sprintLocked[player]
		and not state.exhausted
		and state.value > 0

	-- La course accordee est ce qui coute. La vitesse ne sert plus qu'a
	-- verifier que le joueur avance vraiment : tenir la touche a l'arret ne
	-- vide pas la jauge.
	local changed = Stamina.step(state, dt, speed, now, wantsSprint)

	-- Un joueur qui tombe a bout de souffle PENDANT ce pas perd sa course
	-- immediatement, sans attendre le pas suivant.
	if state.exhausted then
		wantsSprint = false
		-- Et il devra relacher la touche avant de repartir.
		sprintLocked[player] = true
	end

	local target = if crouching
		then crouch.speed
		elseif state.exhausted then Config.Player.stamina.exhaustedSpeed
		elseif wantsSprint then sprint.sprintSpeed
		else sprint.walkSpeed

	-- Attribut replique : c'est la SEULE facon dont EnemyService et le HUD
	-- apprennent qu'un joueur est accroupi.
	if player:GetAttribute("Crouched") ~= crouching then
		player:SetAttribute("Crouched", crouching)
	end

	-- La course ACCORDEE, pas la touche enfoncee. Le rythme cardiaque du
	-- HUD la lit : on ne s'essouffle pas a demander une course refusee.
	if player:GetAttribute("Sprinting") ~= wantsSprint then
		player:SetAttribute("Sprinting", wantsSprint)
	end

	if humanoid.WalkSpeed ~= target then
		humanoid.WalkSpeed = target
	end

	-- Courir s'entend. C'est la contrepartie du sprint, et elle passe par la
	-- menace comme n'importe quelle autre source.
	if wantsSprint and speed > Config.Player.stamina.moveThreshold then
		local context = ctx
		local threat = context and context.Get("ThreatService")
		if threat then
			(threat :: any):AddThreat(sprint.threatPerSecond * dt, "SPRINT")
		end
	end

	if state.exhausted ~= wasExhausted then
		log:info(`{player.Name} {if state.exhausted then "a bout de souffle" else "a repris son souffle"}`)
	end

	if changed then
		fire("StaminaChanged", player, state.value, Config.Player.stamina.max, state.exhausted)
	end
end

-- ------------------------------------------------------------------ API ---

-- Verse le temps accumule dans le profil. Appelee par paliers, et une
-- derniere fois au depart du joueur pour ne pas perdre le reliquat.
local function flushPlaytime(player: Player, force: boolean?)
	local pending = pendingPlaytime[player]
	if not pending or pending <= 0 then
		return
	end
	if not force and pending < PLAYTIME_FLUSH then
		return
	end

	local context = ctx
	local dataService = context and context.Get("DataService")
	local profile = dataService and (dataService :: any).GetProfile(player)
	if not profile then
		-- Profil pas encore charge : on garde le temps de cote plutot que
		-- de le jeter, il sera verse au prochain palier.
		return
	end

	profile.Statistics.Playtime += math.floor(pending)
	pendingPlaytime[player] = pending - math.floor(pending)
end

-- Degats encaisses depuis la derniere remise a zero. Lu par le rapport de
-- fin de raid ; remis a zero au redeploiement, pas a la reapparition — une
-- mort fait partie du raid et doit rester dans le releve.
function PlayerService.GetDamageTaken(player: Player): number
	return damageTaken[player] or 0
end

function PlayerService.ResetDamageTaken(player: Player)
	damageTaken[player] = 0
end

function PlayerService.GetStamina(player: Player): number
	local state = staminas[player]
	return if state then state.value else 0
end

function PlayerService.IsExhausted(player: Player): boolean
	local state = staminas[player]
	return state ~= nil and state.exhausted
end

-- ------------------------------------------------------- Cycle de vie ----

-- Attend que DataService ait charge le profil, puis emet les evenements
-- d'entree. Sans profil, TrackOnce ne saurait pas persister les jalons et
-- les rejouerait a chaque reconnexion.
local function announceJoin(player: Player)
	local context = ctx
	if not context then
		return
	end

	for _ = 1, 40 do
		local dataService = context.Get("DataService")
		local profile = dataService and (dataService :: any).GetProfile(player)

		if profile then
			local analytics = context.Get("AnalyticsService")
			if not analytics then
				return
			end

			local isNew = profile.Statistics.Raids == 0 and profile.Statistics.Extractions == 0

			;(analytics :: any).Track("PlayerJoined", player, {
				level = profile.Level,
				credits = profile.Credits,
				isNewPlayer = isNew,
				raids = profile.Statistics.Raids,
				extractions = profile.Statistics.Extractions,
			})

			-- Debut de l'entonnoir d'accueil. DEFINITION PROVISOIRE : la
			-- premiere connexion tient lieu de tutoriel entame tant qu'il
			-- n'y a pas de vrai tutoriel.
			;(analytics :: any).TrackOnce("TutorialStarted", player, {
				trigger = "premiere_connexion",
			})
			return
		end

		task.wait(0.25)
	end

	log:warn(`profil de {player.Name} jamais charge, evenement d'entree non emis`)
end

local function onDeath(player: Player)
	local context = ctx
	if not context then
		return
	end

	local analytics = context.Get("AnalyticsService")
	local inventoryService = context.Get("InventoryService")
	local threatService = context.Get("ThreatService")
	local extractionService = context.Get("ExtractionService")

	-- Le sac de raid est perdu : on chiffre la perte avant de le vider.
	local lostValue = 0
	local lostStacks: { any } = {}
	if inventoryService then
		local value, stacks = (inventoryService :: any).LoseRaidBag(player)
		lostValue = value
		lostStacks = stacks or {}
	end

	local startedAt = extractionService and (extractionService :: any).GetRunStart(player)
	local duration = if startedAt then math.floor(os.clock() - startedAt) else 0
	local threat = if threatService then math.floor((threatService :: any):GetThreat()) else 0

	local dataService = context.Get("DataService")
	local profile = dataService and (dataService :: any).GetProfile(player)
	if profile then
		profile.Statistics.Deaths += 1
	end

	if analytics then
		(analytics :: any).Track("RunFailed", player, {
			cause = "mort",
			lostValue = lostValue,
			duration = duration,
			threat = threat,
		})

		;(analytics :: any).TrackOnce("FirstDeath", player, {
			cause = "mort",
			lostValue = lostValue,
			survivedFor = duration,
		})
	end

	-- Un mort ne court plus et n'est plus accroupi. Sans ca les intentions
	-- traversent la mort et reprennent au redeploiement.
	sprintIntent[player] = nil
	crouchIntent[player] = nil
	sprintLocked[player] = nil

	-- Emis EN DERNIER : les abonnes lisent des chiffres definitifs.
	-- Notamment le rapport de fin, qui a besoin du detail des piles perdues
	-- et de la duree deja calculee plus haut.
	Signal.fire(PlayerService.Died, player, lostValue, lostStacks, duration)

	log:info(`{player.Name} est mort — {lostValue} cr de butin perdus apres {duration}s`)
end

local function onPlayerAdded(player: Player)
	staminas[player] = Stamina.new(os.clock())
	vitals[player] = {
		armor = Config.Vitals.armor.startingValue,
		maxArmor = Config.Vitals.armor.max,
		battery = Config.Vitals.battery.startingValue,
		maxBattery = Config.Vitals.battery.max,
		lightOn = true,
	}
	task.spawn(announceJoin, player)

	local function onCharacter(character: Model)
		-- REGENERATION AUTOMATIQUE : COUPEE.
		--
		-- Roblox glisse dans chaque personnage un Script nomme « Health » qui
		-- rend 1 % de la vie maximale par seconde. Dans un jeu d'extraction
		-- c'est une erreur de conception a lui seul : encaisser un coup ne
		-- coute plus rien, les consommables de soin ne servent a rien, et le
		-- joueur n'a aucune raison de rentrer.
		--
		-- Effet visible qui l'a trahi : le journal d'evenements annoncait
		-- « SOIN APPLIQUE » en boucle apres chaque egratignure, puisqu'il
		-- deduit le soin d'une remontee de vie.
		--
		-- On l'ecoute en plus de le retirer : le moteur peut le reinserer
		-- apres la premiere replication du personnage.
		local function stripRegen(child: Instance)
			if child.Name == "Health" and child:IsA("BaseScript") then
				child:Destroy()
			end
		end

		for _, child in character:GetChildren() do
			stripRegen(child)
		end
		local previousRegen = regenConnections[player]
		if previousRegen then
			previousRegen:Disconnect()
		end
		regenConnections[player] = character.ChildAdded:Connect(stripRegen)

		-- POSTURE NEUTRE A CHAQUE CORPS.
	--
	-- LE bug d'endurance. Les intentions de course et d'accroupi n'etaient
	-- effacees qu'au DEPART du joueur : elles survivaient donc a la mort et au
	-- redeploiement. Un joueur mort en tenant Maj revenait en sprintant sans
	-- avoir rien touche, vidait sa jauge dans la seconde, tombait a bout de
	-- souffle, se remettait a courir des qu'il repassait le quart — la jauge
	-- oscillait sans jamais repondre a la touche. « Il reste actionne », et
	-- c'etait litteralement le cas.
	--
	-- Le client renvoie la meme remise a zero de son cote : les deux
	-- pourraient sinon rester en desaccord jusqu'a ce que le joueur pense a
	-- appuyer puis relacher.
	sprintIntent[player] = nil
	crouchIntent[player] = nil
	sprintLocked[player] = nil
	player:SetAttribute("Sprinting", false)
	player:SetAttribute("Crouched", false)

	-- Nouvelle apparition, vitaux neufs. L'armure repart a zero — elle se
		-- trouve, elle ne se conserve pas a travers la mort — et la lampe est
		-- rechargee : entrer en zone sans lumiere serait injouable.
		local vital = vitals[player]
		if vital then
			vital.armor = Config.Vitals.armor.startingValue
			vital.battery = Config.Vitals.battery.startingValue
			vital.lightOn = true
		end

		-- L'instantane part a chaque apparition : le HUD est recree avec le
		-- personnage, il doit etre repeuple a chaque fois.
		task.defer(function()
			sendSnapshot(player)
		end)

		local startedAt = os.clock()

		local context = ctx
		local extractionService = context and context.Get("ExtractionService")
		if extractionService then
			(extractionService :: any).MarkRunStart(player, startedAt)
		end

		-- Une course ne demarre que si un raid est en cours : reapparaitre
		-- dans un lobby n'est pas une course.
		--
		-- L'emission attend le profil. CharacterAdded se declenche avant la
		-- fin du chargement asynchrone : sans cette attente, RunStarted
		-- annoncait niveau 1 et coffre vide pour un joueur niveau 2 charge
		-- une seconde plus tard, et l'increment de Raids tombait dans le
		-- vide faute de profil.
		task.spawn(function()
			local matchService = context and context.Get("MatchService")
			local analytics = context and context.Get("AnalyticsService")
			local dataService = context and context.Get("DataService")
			if not analytics or not matchService or not dataService then
				return
			end

			local profile
			for _ = 1, 40 do
				profile = (dataService :: any).GetProfile(player)
				if profile then
					break
				end
				task.wait(0.25)
			end

			if not profile or not player.Parent then
				return
			end
			if not (matchService :: any).IsRunning() then
				return
			end

			-- Statistics.Raids n'etait incremente nulle part : il restait a
			-- zero a vie, et `isNewPlayer` s'en servait pour decider si un
			-- joueur etait nouveau.
			profile.Statistics.Raids += 1

			local inventoryService = context.Get("InventoryService")
			;(analytics :: any).Track("RunStarted", player, {
				raidState = (matchService :: any).GetState(),
				level = profile.Level,
				stashValue = if inventoryService then math.floor((inventoryService :: any).GetStashValue(player)) else 0,
			})
		end)

		local previous = deathConnections[player]
		if previous then
			previous:Disconnect()
			deathConnections[player] = nil
		end

		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			deathConnections[player] = humanoid.Died:Connect(function()
				onDeath(player)
			end)
		end
	end

	if player.Character then
		onCharacter(player.Character)
	end
	table.insert(connections, player.CharacterAdded:Connect(onCharacter))

	-- Apparition EXPLICITE. `CharacterAutoLoads` est coupe : sans cet appel,
	-- un joueur qui rejoint reste sans corps jusqu'au redeploiement suivant,
	-- soit jusqu'a vingt-cinq minutes d'attente devant un ecran vide.
	--
	-- On n'agit que s'il n'a pas deja un corps : le premier joueur d'une
	-- session Studio peut etre apparu avant que ce service ne demarre.
	if not player.Character then
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			log:error(`apparition de {player.Name} impossible -> {err}`)
		end
	end
end

local function onPlayerRemoving(player: Player)
	-- Tentative de dernier versement. Elle echoue si DataService a deja
	-- libere le profil — d'ou le palier a une seconde plus haut, qui borne
	-- la perte plutot que de compter sur un ordre non garanti.
	flushPlaytime(player, true)
	pendingPlaytime[player] = nil

	staminas[player] = nil
	sprintIntent[player] = nil
	crouchIntent[player] = nil
	sprintLocked[player] = nil
	vitals[player] = nil
	damageTaken[player] = nil

	local regen = regenConnections[player]
	if regen then
		regen:Disconnect()
		regenConnections[player] = nil
	end
	vitalsDirty[player] = nil

	local connection = deathConnections[player]
	if connection then
		connection:Disconnect()
		deathConnections[player] = nil
	end
end

function PlayerService.Init(context: ServiceContext)
	ctx = context
end

-- Affordance de playtest pour les vitaux.
--
-- La batterie tient une heure : impossible de verifier a la main ce qui se
-- passe a plat, ni le flou de la camera embarquee qu'elle declenche. Sans ce
-- point d'entree, ce chemin ne serait jamais teste avant la production.
local function installDebug()
	if not RunService:IsStudio() then
		return
	end

	local ServerStorage = game:GetService("ServerStorage")
	local existing = ServerStorage:FindFirstChild("DebugVitals")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DebugVitals"
	bindable.Parent = ServerStorage

	bindable.OnInvoke = function(action: string?, argument: string?): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "aucun joueur"
		end
		local vital = vitals[player]
		if not vital then
			return "aucun vital pour ce joueur"
		end

		local value = tonumber(argument or "")

		-- Filet de secours si une intention reste bloquee : on relache tout
		-- sans avoir a mourir ni a se reconnecter.
		-- RELEVE CONTINU, cinq secondes.
		--
		-- Le seul moyen de voir ce que fait l'endurance PENDANT qu'une touche
		-- est tenue : impossible d'invoquer une commande et de maintenir Maj en
		-- meme temps. On lance le releve, on va tenir la touche, on lit ensuite.
		--
		-- Il imprime la vitesse mesuree, l'intention, la course accordee, la
		-- jauge et l'epuisement. Si la jauge ne bouge pas alors que la course
		-- est accordee, le defaut est serveur ; si elle bouge ici mais pas a
		-- l'ecran, il est dans l'affichage.
		if action == "watch" then
			task.spawn(function()
				log:info("releve d'endurance : 5 s, tiens la touche maintenant")
				for index = 1, 25 do
					task.wait(0.2)
					local state = staminas[player]
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local velocity = if root and root:IsA("BasePart")
						then root.AssemblyLinearVelocity
						else Vector3.zero
					local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)

					log:info(string.format(
						"%2d  jauge %5.1f  vitesse %4.1f  demande %s  accordee %s  epuise %s  verrou %s",
						index,
						if state then state.value else -1,
						speed,
						tostring(sprintIntent[player] == true),
						tostring(player:GetAttribute("Sprinting") == true),
						tostring(state and state.exhausted),
						tostring(sprintLocked[player] == true)
					))
				end
				log:info("releve termine")
			end)
			return "releve lance : tiens Maj pendant cinq secondes, puis lis la console"
		end

		if action == "release" then
			sprintIntent[player] = nil
			crouchIntent[player] = nil
			sprintLocked[player] = nil
			player:SetAttribute("Sprinting", false)
			player:SetAttribute("Crouched", false)
			return "course et accroupi relaches"
		end

		if action == "battery" and value then
			vital.battery = math.clamp(value, 0, vital.maxBattery)
			if vital.battery <= 0 then
				vital.lightOn = false
			end
			pushVitals(player)
			return `batterie = {math.floor(vital.battery)}`
		end

		if action == "armor" and value then
			vital.armor = math.clamp(value, 0, vital.maxArmor)
			pushVitals(player)
			return `armure = {math.floor(vital.armor)}`
		end

		if action == "light" then
			PlayerService.SetLight(player, not vital.lightOn)
			return `lampe = {tostring(vital.lightOn)}`
		end

		return table.concat({
			`armure : {math.floor(vital.armor)}/{vital.maxArmor}`,
			`batterie : {math.floor(vital.battery)}/{vital.maxBattery}`,
			`lampe : {tostring(vital.lightOn)}`,
			"",
			"-- endurance --",
			`jauge : {if staminas[player] then string.format("%.1f/%d", staminas[player].value, Config.Player.stamina.max) else "?"}`,
			`a bout de souffle : {tostring(staminas[player] and staminas[player].exhausted)}`,
			`intention de course : {tostring(sprintIntent[player] == true)}`,
			`verrou d'epuisement : {tostring(sprintLocked[player] == true)}`,
			`course accordee : {tostring(player:GetAttribute("Sprinting") == true)}`,
			`intention d'accroupi : {tostring(crouchIntent[player] == true)}`,
			`vitesse appliquee : {(function()
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				return if humanoid then humanoid.WalkSpeed else -1
			end)()}`,
			"",
			"actions : status | watch | battery <n> | armor <n> | light | release",
		}, "\n")
	end

	log:info('debug : ServerStorage.DebugVitals:Invoke("status"|"watch"|"battery <n>"|"armor <n>"|"light"|"release")')
end

function PlayerService.Start()
	-- ON NE REVIENT PAS.
	--
	-- Roblox fait reapparaitre le personnage tout seul. Dans un jeu
	-- d'extraction, ca vide la mort de son sens : le sac est perdu mais on
	-- repart aussitot, et la menace ne coute plus rien.
	--
	-- Couper CharacterAutoLoads rend le premier spawn EXPLICITE : c'est
	-- desormais ce service qui fait apparaitre un joueur qui arrive, et
	-- MatchService qui fait reapparaitre tout le monde au redeploiement.
	-- Personne d'autre n'appelle LoadCharacter.
	Players.CharacterAutoLoads = false

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.Player.stamina.tickRate then
			return
		end
		local step = accumulator
		accumulator = 0

		local now = os.clock()
		vitalsPushAccumulator += step

		local shouldPush = vitalsPushAccumulator >= Config.Vitals.pushRate
		if shouldPush then
			vitalsPushAccumulator = 0
		end

		for _, player in Players:GetPlayers() do
			updateStamina(player, step, now)
			updateBattery(player, step)

			-- Diffusion groupee : la batterie change en continu, mais une
			-- jauge n'a pas besoin de quatre decimales par seconde.
			if shouldPush and vitalsDirty[player] then
				pushVitals(player)
			end

			pendingPlaytime[player] = (pendingPlaytime[player] or 0) + step
			flushPlaytime(player)
		end
	end)

	-- Intention de course. Validation stricte : on n'accepte qu'un booleen,
	-- et on ne le croit que comme une INTENTION.
	local context = ctx
	local sprintRemote = context and context.Remotes:FindFirstChild("RequestSprint")
	if sprintRemote and sprintRemote:IsA("RemoteEvent") then
		table.insert(
			connections,
			sprintRemote.OnServerEvent:Connect(function(player, wants)
				local before = sprintIntent[player] == true
				sprintIntent[player] = wants == true

				-- Le relachement leve le verrou d'epuisement : c'est le SEUL
				-- moyen de repartir en course apres etre tombe hors d'haleine.
				if wants ~= true then
					sprintLocked[player] = nil
				end

				-- REACTION IMMEDIATE. Attendre le tick suivant laissait la jauge
				-- immobile jusqu'a un dixieme de seconde apres l'appui, en plus du
				-- trajet reseau. Le joueur appuyait, il ne se passait rien, et il
				-- concluait que la touche ne marchait pas.
				--
				-- On ne passe ici que sur un VRAI changement : un client qui
				-- reenverrait la meme valeur en boucle ne peut pas forcer le
				-- serveur a recalculer a volonte.
				if before ~= (wants == true) then
					local now = os.clock()
					updateStamina(player, Config.Player.stamina.tickRate, now)
				end
			end)
		)
	else
		log:warn("remote RequestSprint absent : le sprint sera indisponible")
	end

	-- Intention d'accroupi, meme contrat que la course.
	local crouchRemote = context and context.Remotes:FindFirstChild("RequestCrouch")
	if crouchRemote and crouchRemote:IsA("RemoteEvent") then
		table.insert(
			connections,
			crouchRemote.OnServerEvent:Connect(function(player, wants)
				crouchIntent[player] = wants == true
			end)
		)
	else
		log:warn("remote RequestCrouch absent : l'accroupi sera indisponible")
	end

	installDebug()
	log:info(`pret — endurance {Config.Player.stamina.max}, effort au-dela de {Config.Player.stamina.moveThreshold}`)
end

function PlayerService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(staminas)
	Signal.clear(PlayerService.Died)
end

return PlayerService
