--!strict
-- Assemblage du HUD v2.
--
-- Ce module monte les widgets, les cable sur les remotes et fait tourner la
-- boucle d'animation. Il ne DECIDE rien : chaque valeur affichee vient du
-- serveur ou d'un etat deja replique par le moteur.
--
-- Repartition, conforme a la maquette :
--
--   haut gauche    identite du jeu
--   haut centre    boussole, puis menace
--   haut droite    zone, heure, meteo
--   gauche         contrat
--   droite         extraction (contextuel)
--   bas gauche     vitaux, transmission au-dessus
--   bas centre     barre d'equipement
--   bas droite     arme
--   centre         invites uniquement
--
-- SEUL CANAL MONTANT : RequestSlot, quand le joueur presse 1-5. Le serveur
-- decide de ce que ca veut dire. Aucune autre communication ne part d'ici.

local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local ItemDatabase = require(Shared.ItemDatabase)
local Locale = require(Shared.Locale)
local Spectate = require(Shared.Spectate)
local Logger = require(Shared.Utils.Logger)

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local IdentityWidget = require(script.Parent.IdentityWidget)
local CompassWidget = require(script.Parent.CompassWidget)
local ThreatWidget = require(script.Parent.ThreatWidget)
local WorldInfoWidget = require(script.Parent.WorldInfoWidget)
local ObjectiveWidget = require(script.Parent.ObjectiveWidget)
local ExtractionWidget = require(script.Parent.ExtractionWidget)
local PlayerStatusWidget = require(script.Parent.PlayerStatusWidget)
local WeaponWidget = require(script.Parent.WeaponWidget)
local InteractionWidget = require(script.Parent.InteractionWidget)
local DamageFeedback = require(script.Parent.DamageFeedback)
local TransmissionWidget = require(script.Parent.TransmissionWidget)
local BootSequence = require(script.Parent.BootSequence)
local DamageIndicator = require(script.Parent.DamageIndicator)
local HitMarker = require(script.Parent.HitMarker)
local EventFeed = require(script.Parent.EventFeed)
local BandBanner = require(script.Parent.BandBanner)
local DebriefWidget = require(script.Parent.DebriefWidget)
local Panic = require(script.Parent.Panic)

local HUDController = {}

local log = Logger.new("Hud")

-- Abonnements poses par bindInput. `connections` appartient a bind() et n'est
-- pas visible ici : garder la molette dans une variable de module est le seul
-- moyen que unbindInput puisse la couper.
local inputConnections: { RBXScriptConnection } = {}

-- Le HUD de jeu est-il masque par un autre ecran ?
--
-- Un SEUL endroit decide de sa visibilite. La vue spectateur coupait le
-- ScreenGui elle-meme et la boucle d'animation le rallumait a l'image
-- suivante : le HUD clignotait a 60 Hz par-dessus le flux de surveillance.
local suppressed = false

-- Nom affichable d'un objet, dans la langue du joueur.
--
-- ItemDatabase garde ses noms pour les journaux serveur ; l'affichage passe
-- par « item.<id> » quand la cle existe, et retombe sur le nom brut sinon.
-- Un objet ajoute au catalogue sans traduction reste donc lisible.
local function itemName(itemId: string?): string
	if not itemId then
		return ""
	end
	local translated = Locale.maybe(`item.{itemId}`)
	if translated then
		return translated
	end
	local definition = ItemDatabase.get(itemId)
	return if definition then definition.name else itemId
end
local player = Players.LocalPlayer

export type Hud = {
	gui: ScreenGui,
	scale: UIScale,

	identity: IdentityWidget.Widget,
	compass: CompassWidget.Widget,
	threat: ThreatWidget.Widget,
	world: WorldInfoWidget.Widget,
	objectives: ObjectiveWidget.Widget,
	extraction: ExtractionWidget.Widget,
	status: PlayerStatusWidget.Widget,
	weapon: WeaponWidget.Widget,
	interaction: InteractionWidget.Widget,
	feedback: DamageFeedback.Widget,
	transmission: TransmissionWidget.Widget,
	exitMarkers: { { bearing: number, distance: number } },
	boot: BootSequence.Widget,
	damageDirection: DamageIndicator.Widget,
	hitMarker: HitMarker.Widget,
	events: EventFeed.Widget,
	bandBanner: BandBanner.Widget,
	debrief: DebriefWidget.Widget,
	panic: Panic.Widget,
	lastBand: string,

	profile: string,
	compassAccumulator: number,
	derivedAccumulator: number,

	-- Munitions en reserve, derivees de l'inventaire deja replique.
	reserve: { [string]: number },
	-- Dernier etat de barre recu, pour pouvoir le rejouer avec un chargeur
	-- rafraichi sans redemander quoi que ce soit au serveur.
	slots: { Types.LoadoutSlot },
	equipped: string?,
	ammo: number,
	reloading: boolean,
}

-- ------------------------------------------------------------- Montage ---

-- Coupe les elements d'interface natifs que le HUD remplace.
--
-- La barre de vie Roblox s'affichait en haut a gauche des la premiere
-- egratignure, en doublon de la ligne VIE du bloc de vitaux — deux lectures
-- de la meme valeur a deux endroits, dont une qu'on ne controle pas et qui
-- ne suit aucune direction artistique.
--
-- SetCoreGuiEnabled echoue tant que le CoreGui n'est pas pret : on reessaie
-- brievement plutot que d'abandonner au premier refus.
local function disableCoreGui()
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			end)
			if ok then
				return
			end
			task.wait(0.25)
		end
		log:warn("barre de vie native non desactivee")
	end)
end

function HUDController.mount(playerGui: PlayerGui): Hud
	disableCoreGui()

	for _, name in { "BlackoutHud", "BlackoutFeedback" } do
		local existing = playerGui:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	-- La langue se determine UNE FOIS, avant de construire quoi que ce soit :
	-- les libelles fixes sont poses a la creation des widgets.
	local language = Locale.detect()
	log:info(`langue : {language}`)

	local feedback = DamageFeedback.create(playerGui)

	local gui = Components.new("ScreenGui", {
		Name = "BlackoutHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	}, playerGui) :: ScreenGui

	-- UIScale unique a la racine : l'echelle corrige la densite selon la
	-- resolution, elle ne remplace pas le retrait d'information.
	local scale = Components.new("UIScale", { Scale = 1 }, gui) :: UIScale

	local hud: Hud = {
		gui = gui,
		scale = scale,
		identity = IdentityWidget.create(gui),
		compass = CompassWidget.create(gui),
		threat = ThreatWidget.create(gui),
		world = WorldInfoWidget.create(gui),
		objectives = ObjectiveWidget.create(gui),
		extraction = ExtractionWidget.create(gui),
		status = PlayerStatusWidget.create(gui),
		weapon = WeaponWidget.create(gui),
		interaction = InteractionWidget.create(gui),
		feedback = feedback,
		transmission = TransmissionWidget.create(gui),
		exitMarkers = {},
		boot = BootSequence.create(gui),
		damageDirection = DamageIndicator.create(gui),
		hitMarker = HitMarker.create(gui),
		events = EventFeed.create(gui),
		bandBanner = BandBanner.create(gui),
		-- Sa propre couche : le rapport doit passer PAR-DESSUS le HUD, pas
		-- se glisser entre deux widgets.
		debrief = DebriefWidget.create(playerGui),
		panic = Panic.create(),
		lastBand = "SAFE",
		profile = "full",
		compassAccumulator = 0,
		derivedAccumulator = 0,
		reserve = {},
		slots = {},
		equipped = nil,
		ammo = 0,
		reloading = false,
	}

	-- Le moniteur porte le matricule de son porteur : c'est l'annotation qui
	-- le fait lire comme un equipement sangle sur quelqu'un.
	PlayerStatusWidget.setTag(hud.status, Spectate.tag(player.UserId))

	-- PANIQUE GENERALE.
	--
	-- Le bloc de vitaux tremblait seul quand le rythme montait, et tout le
	-- reste de l'equipement restait parfaitement stable a cote. On
	-- enregistre donc les autres panneaux pour qu'ils encaissent la meme
	-- chose, sur le meme pouls.
	--
	-- PlayerStatus est volontairement ABSENT de la liste : il a deja son
	-- propre tremblement, l'ajouter ici le ferait vibrer deux fois.
	for _, name in
		{ "Objectives", "Threat", "Weapon", "WorldInfo", "Extraction", "Identity", "Transmission", "EventFeed" }
	do
		Panic.watchFrame(hud.panic, hud.gui:FindFirstChild(name) :: GuiObject?)
	end

	-- Libelles FIXES uniquement, et le mot compte deux fois.
	--
	-- Pas de valeur chiffree : brouiller un chiffre ferait douter le
	-- joueur du chiffre lui-meme, ce qui est une tout autre promesse que
	-- « l'appareil fatigue ».
	--
	-- Et pas de libelle que son widget REECRIT en cours de partie — le
	-- palier de menace, le mode de tir, l'en-tete de contrat. La panique
	-- retient le texte au moment ou elle l'enregistre : si le widget le
	-- change ensuite, la restauration reposerait l'ANCIEN texte, et le HUD
	-- afficherait « SAFE » en pleine traque.
	Panic.watchLabel(hud.panic, hud.threat.caption)
	Panic.watchLabel(hud.panic, hud.threat.minLabel)
	Panic.watchLabel(hud.panic, hud.threat.maxLabel)
	Panic.watchLabel(hud.panic, hud.objectives.footer)
	Panic.watchLabel(hud.panic, hud.objectives.footerSuffix)

	-- LE POP-UP D'INFORMATION. C'est une liaison radio : c'est
	-- precisement le texte ou un decrochage se lit le mieux, et c'etait
	-- le seul que la panique ne touchait pas.
	--
	-- Il passe par `watchLive` parce que son widget le REECRIT en
	-- permanence : la transmission s'ecrit lettre par lettre. Une
	-- reference figee y remettrait un message deja perime.
	Panic.watchLive(hud.panic, hud.transmission.body)
	Panic.watchLive(hud.panic, hud.transmission.sender)

	return hud
end

-- ---------------------------------------------------------- Responsive ---

-- On ne reduit pas le HUD entier : on retire du secondaire. La consigne est
-- explicite, et c'est aussi la seule facon de rester lisible sur telephone —
-- un HUD complet mis a 60 % est un HUD illisible, pas un HUD mobile.
local function applyProfile(hud: Hud, viewport: Vector2)
	local profile = "full"
	if viewport.X < Config.Hud.breakpoints.minimalBelow then
		profile = "minimal"
	elseif viewport.X < Config.Hud.breakpoints.compactBelow then
		profile = "compact"
	end

	-- Echelle relative a la hauteur de reference, bornee pour qu'un ecran
	-- 4K n'affiche pas un HUD minuscule ni un telephone un HUD geant.
	local density = math.clamp(
		viewport.Y / Config.Hud.referenceHeight,
		Config.Hud.densityRange.min,
		Config.Hud.densityRange.max
	)
	hud.scale.Scale = density * (Config.Hud.scale[profile] or 1) * Config.Hud.globalScale

	if hud.profile == profile then
		return
	end
	hud.profile = profile

	local full = profile == "full"
	local minimal = profile == "minimal"

	-- Boussole, identite et bandeau de zone sont du confort : ils partent
	-- les premiers.
	CompassWidget.setVisible(hud.compass, full)
	IdentityWidget.setVisible(hud.identity, full)
	WorldInfoWidget.setVisible(hud.world, full)

	-- Restent toujours : contrat, menace, vitaux, arme, interaction.
	PlayerStatusWidget.setCompact(hud.status, minimal)

	log:info(`profil d'affichage : {profile} ({math.floor(viewport.X)}x{math.floor(viewport.Y)})`)
end

-- ------------------------------------------------------------- Derives ---

-- Cap de la camera, en degres, 0 = nord. La boussole est le seul widget qui
-- suit la camera : il ne peut pas etre evenementiel.
local function updateCompass(hud: Hud)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	-- Cap de la camera : 0 = nord. Roblox regarde vers -Z au repos, d'ou
	-- l'atan2 sur (X, -Z) plutot que l'inverse.
	local look = camera.CFrame.LookVector
	local yaw = math.deg(math.atan2(look.X, -look.Z))

	CompassWidget.setHeading(hud.compass, yaw)
	CompassWidget.setMarkers(hud.compass, hud.exitMarkers, yaw)
end

local function updateExit(hud: Hud)
	if hud.extraction.extracting then
		return
	end

	local folder = Workspace:FindFirstChild("ExtractionZones")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not folder or not root or not root:IsA("BasePart") then
		ExtractionWidget.setExit(hud.extraction, nil, nil)
		return
	end

	local bestName, bestDistance = nil, math.huge
	local markers: { { bearing: number, distance: number } } = {}

	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Active") == true then
			local offset = part.Position - root.Position
			local distance = offset.Magnitude

			if distance < bestDistance then
				bestDistance = distance
				bestName = part:GetAttribute("ZoneName") :: string? or part.Name
			end

			-- Cap absolu de la sortie, 0 = nord (-Z dans Roblox), sens
			-- horaire. C'est ce que la boussole attend pour poser son
			-- marqueur au bon endroit.
			local bearing = math.deg(math.atan2(offset.X, -offset.Z))
			table.insert(markers, { bearing = (bearing % 360 + 360) % 360, distance = distance })
		end
	end

	-- La plus proche d'abord : la boussole n'a que quatre marqueurs, autant
	-- qu'ils servent a quelque chose.
	table.sort(markers, function(a, b)
		return a.distance < b.distance
	end)

	hud.exitMarkers = markers
	ExtractionWidget.setExit(hud.extraction, bestName, if bestName then bestDistance else nil)
end

-- Recompose l'affichage de l'arme a partir des trois sources : etat d'arme
-- (serveur), reserve (inventaire replique) et config (calibre, mode).
local function refreshWeapon(hud: Hud)
	local itemId = hud.equipped
	if not itemId then
		WeaponWidget.setWeapon(hud.weapon, nil, 0, 0, 0, nil, nil, false)
		return
	end

	local weapon = Config.Weapons.weapons[itemId]
	if not weapon then
		WeaponWidget.setWeapon(hud.weapon, nil, 0, 0, 0, nil, nil, false)
		return
	end

	WeaponWidget.setWeapon(
		hud.weapon,
		itemName(itemId),
		hud.ammo,
		weapon.magazine,
		hud.reserve[weapon.ammoId] or 0,
		weapon.caliber,
		weapon.fireMode,
		hud.reloading
	)
end

-- --------------------------------------------------------------- Boucle --

function HUDController.step(hud: Hud, dt: number)
	ThreatWidget.step(hud.threat, dt)
	ObjectiveWidget.step(hud.objectives, dt)
	ExtractionWidget.step(hud.extraction, dt)
	PlayerStatusWidget.step(hud.status, dt)
	WeaponWidget.step(hud.weapon, dt)
	InteractionWidget.step(hud.interaction, dt)
	TransmissionWidget.step(hud.transmission, dt)
	DamageFeedback.step(hud.feedback, dt)
	DamageIndicator.step(hud.damageDirection, dt)
	HitMarker.step(hud.hitMarker, dt)
	EventFeed.step(hud.events, dt)
	BandBanner.step(hud.bandBanner, dt)
	BootSequence.step(hud.boot, dt)
	DebriefWidget.step(hud.debrief, dt)

	-- La panique lit la DEGRADATION du bloc de vitaux : source unique.
	-- Recalculer ici donnerait deux horloges qui derivent, et un HUD dont
	-- les panneaux tremblent a contretemps de leur propre cardiogramme.
	Panic.step(hud.panic, dt, PlayerStatusWidget.getDecay(hud.status))

	-- Le rapport REMPLACE le HUD, il ne se pose pas dessus.
	--
	-- Les deux parlent de la meme partie : laisser la boussole, le contrat
	-- et le moniteur vital derriere le document donne deux lectures
	-- concurrentes du meme raid, et le voile ne suffit pas a les separer.
	-- Le retour du HUD pendant la disparition du rapport est voulu : c'est
	-- la reprise en main.
	local hidden = DebriefWidget.isOpen(hud.debrief) or suppressed
	if hud.gui.Enabled == hidden then
		hud.gui.Enabled = not hidden
		hud.feedback.gui.Enabled = not hidden
	end

	hud.compassAccumulator += dt
	if hud.compassAccumulator >= Config.Hud.sampleRate.compass then
		hud.compassAccumulator = 0
		updateCompass(hud)
	end

	hud.derivedAccumulator += dt
	if hud.derivedAccumulator >= Config.Hud.sampleRate.derived then
		hud.derivedAccumulator = 0
		updateExit(hud)
	end
end

-- Masque le HUD de jeu au profit d'un autre ecran plein cadre.
function HUDController.setSuppressed(value: boolean)
	suppressed = value
end

function HUDController.destroy(hud: Hud)
	hud.gui:Destroy()
	DebriefWidget.destroy(hud.debrief)
	DamageFeedback.destroy(hud.feedback)
end

-- -------------------------------------------------------------- Cablage --

-- Retourne la liste des connexions a liberer a l'arret.
function HUDController.bind(hud: Hud): { RBXScriptConnection }
	local connections: { RBXScriptConnection } = {}
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	-- Abonnement defensif : on ATTEND le remote et on signale son absence.
	-- Un FindFirstChild sans attente repart en silence quand l'enfant n'a pas
	-- fini de se repliquer, et le HUD reste muet sans lever d'erreur.
	local function bind(name: string, handler: (...any) -> ())
		local remote = remotes:WaitForChild(name, 10)
		if not remote or not remote:IsA("RemoteEvent") then
			log:warn(`remote absent : {name}`)
			return
		end
		table.insert(connections, remote.OnClientEvent:Connect(handler))
	end

	-- --- etat initial ---------------------------------------------------
	bind("HudSnapshot", function(snapshot: Types.HudSnapshot)
		ThreatWidget.setThreat(hud.threat, snapshot.threat, snapshot.band)
		DamageFeedback.setBand(hud.feedback, snapshot.band)
		PlayerStatusWidget.setStamina(hud.status, snapshot.stamina, snapshot.maxStamina)
		PlayerStatusWidget.setStress(hud.status, snapshot.band)
		if snapshot.equipped then
			hud.equipped = snapshot.equipped
			refreshWeapon(hud)
		end
	end)

	-- --- vitaux ----------------------------------------------------------
	-- Retour de consommable.
	--
	-- La barre d'equipement ayant ete retiree, presser 3 ou 5 ne montrait plus
	-- RIEN : le joueur ne pouvait pas savoir si son soin avait ete pris ou
	-- refuse. On le derive d'une valeur deja repliquee — une jauge qui MONTE
	-- ne peut venir que d'une consommation — plutot que d'ouvrir un remote
	-- pour une ligne de texte.
	local previousArmor, previousBattery, previousHealth = -1, -1, -1

	bind("VitalsChanged", function(vitals: Types.Vitals)
		PlayerStatusWidget.setVitals(hud.status, vitals)

		if previousArmor >= 0 and vitals.armor > previousArmor + 0.5 then
			EventFeed.push(hud.events, Locale.t("hud.feed.armor"), Theme.color.armor)
		end
		if previousBattery >= 0 and vitals.battery > previousBattery + 0.5 then
			EventFeed.push(hud.events, Locale.t("hud.feed.battery"), Theme.color.battery)
		end
		previousArmor = vitals.armor
		previousBattery = vitals.battery
	end)

	bind("StaminaChanged", function(value: number, max: number)
		PlayerStatusWidget.setStamina(hud.status, value, max)
	end)

	-- --- menace ----------------------------------------------------------
	-- Ordre des paliers, pour n'annoncer que les montees. Redescendre est une
	-- bonne nouvelle : elle n'a pas besoin d'interrompre le joueur.
	local BAND_RANK: { [string]: number } =
		{ SAFE = 1, ALERT = 2, DANGER = 3, SEVERE = 4, CRITICAL = 5, HUNT = 6 }

	bind("ThreatLevelChanged", function(value: number, band: string)
		ThreatWidget.setThreat(hud.threat, value, band)
		DamageFeedback.setBand(hud.feedback, band)
		-- Le coeur s'emballe avant que quoi que ce soit ne touche le joueur.
		PlayerStatusWidget.setStress(hud.status, band)

		local was = BAND_RANK[hud.lastBand] or 1
		local now = BAND_RANK[band] or 1
		if now > was then
			BandBanner.announce(
				hud.bandBanner,
				Locale.t("hud.band.announce", { band = Locale.t(`hud.band.{band}`) }),
				Theme.threat.color[band] or Theme.color.danger
			)
		end
		hud.lastBand = band
	end)

	bind("HuntStarted", function()
		DamageFeedback.setHunt(hud.feedback, true)
	end)

	bind("HuntEnded", function()
		DamageFeedback.setHunt(hud.feedback, false)
	end)

	-- --- contrat ---------------------------------------------------------
	-- Etat precedent des objectifs, pour reperer CE QUI VIENT de changer.
	-- Le serveur envoie le contrat entier ; sans cette comparaison, on ne
	-- saurait pas quelle ligne vient d'etre validee.
	local objectiveDone: { [string]: boolean } = {}

	bind("ContractChanged", function(contract: Types.Contract?)
		ObjectiveWidget.setContract(hud.objectives, contract)

		if not contract then
			table.clear(objectiveDone)
			return
		end

		for _, objective in contract.objectives do
			local key = `{contract.id}:{objective.labelKey}`
			if objective.done and not objectiveDone[key] then
				objectiveDone[key] = true
				EventFeed.push(hud.events, Locale.t("hud.feed.objective"), Theme.color.extraction)
				ObjectiveWidget.flash(hud.objectives, objective.labelKey)
			end
		end

		if contract.complete then
			local key = `{contract.id}:complete`
			if not objectiveDone[key] then
				objectiveDone[key] = true
				EventFeed.push(
					hud.events,
					Locale.t("hud.feed.contract", { reward = contract.reward }),
					Theme.color.amber
				)
			end
		end
	end)

	-- --- barre d'equipement ----------------------------------------------
	-- La barre d'equipement a ete RETIREE de l'ecran : elle prenait le bas du
	-- champ de vision pour une information que l'arme et les vitaux donnent
	-- deja. On garde l'abonnement — c'est lui qui alimente la bascule d'arme
	-- et le compteur de munitions.
	-- Verdict d'une demande d'emplacement. TOUT refus s'affiche : une touche
	-- qui ne produit rien se lit comme cassee, meme quand le refus est
	-- legitime.
	bind("SlotResult", function(reason: string)
		InteractionWidget.alert(hud.interaction, Locale.t(`slot.{reason}`), Theme.color.amber)
	end)

	bind("LoadoutChanged", function(slots: { Types.LoadoutSlot })
		hud.slots = slots

		-- La barre porte deja le chargeur de l'arme active. On s'en sert pour
		-- amorcer le module d'arme : au deploiement, WeaponStateChanged n'a
		-- pas encore ete emis et le compteur affichait 0 alors que le joueur
		-- avait un pistolet charge en main.
		for _, slot in slots do
			if slot.selected and slot.ammo then
				hud.equipped = slot.itemId
				hud.ammo = slot.ammo
				refreshWeapon(hud)
				break
			end
		end
	end)

	-- --- zone / heure / meteo --------------------------------------------
	bind("WorldInfoChanged", function(info: Types.WorldInfo)
		WorldInfoWidget.setInfo(hud.world, info.district, info.weather, info.clock)
	end)

	-- --- arme -------------------------------------------------------------
	bind("WeaponStateChanged", function(itemId: string?, ammo: number, _magazine: number, reloading: boolean)
		hud.equipped = itemId
		hud.ammo = ammo
		hud.reloading = reloading
		refreshWeapon(hud)

		-- La case de l'arme active porte le meme chargeur que le module
		-- d'arme. Sans ce rappel, la barre restait sur la valeur d'avant le
		-- tir et affichait 12/12 pendant que le compteur indiquait 7.
		local touched = false
		for _, slot in hud.slots do
			if slot.itemId == itemId and slot.counter == "ammo" then
				slot.ammo = ammo
				touched = true
			end
		end
		if touched then
		end
	end)

	bind("EquippedChanged", function(itemId: string?)
		hud.equipped = itemId
		refreshWeapon(hud)
	end)

	-- --- inventaire : reserve de munitions --------------------------------
	--
	-- Derivee localement plutot que diffusee : `contents` porte deja les
	-- quantites, un remote de plus ne dirait rien de neuf.
	bind("InventoryChanged", function(contents: { Types.ResolvedItem })
		table.clear(hud.reserve)
		for _, item in contents do
			hud.reserve[item.id] = item.quantity
		end
		refreshWeapon(hud)
	end)

	-- --- degats -----------------------------------------------------------
	bind("DamageTaken", function(report: Types.DamageReport)
		DamageFeedback.onDamage(hud.feedback, report.severity)
		DamageIndicator.hit(hud.damageDirection, report.origin, report.severity)
		PlayerStatusWidget.onDamage(hud.status, report.severity)
	end)

	-- Retour de combat. Purement illustratif : le serveur a deja tranche.
	bind("CombatFeedback", function(kind: string)
		HitMarker.hit(hud.hitMarker, kind)
		if kind == "kill" then
			EventFeed.push(hud.events, Locale.t("hud.feed.kill"), Theme.color.danger)
		end
	end)

	-- Butin ramasse. Une ligne par pile : un conteneur qui donne cinq objets
	-- produit cinq lignes, empilees et toutes lisibles.
	bind("LootGranted", function(granted: { { id: string, quantity: number } })
		for _, stack in granted do
			EventFeed.push(hud.events, itemName(stack.id), Theme.color.amber, `x{stack.quantity}`)
		end
	end)

	-- --- extraction -------------------------------------------------------
	bind("ExtractionStarted", function(zone: string, holdTime: number)
		ExtractionWidget.setProgress(hud.extraction, zone, 0, holdTime)
	end)

	bind("ExtractionProgress", function(zone: string, fraction: number, remaining: number)
		ExtractionWidget.setProgress(hud.extraction, zone, fraction, remaining)
	end)

	bind("ExtractionCancelled", function(reason: string)
		ExtractionWidget.setProgress(hud.extraction, nil, nil, nil)
		local keys: { [string]: string } = {
			LEFT_ZONE = "hud.extraction.brokenZone",
			DEAD = "hud.extraction.brokenDead",
			ZONE_INACTIVE = "hud.extraction.brokenClosed",
			RUN_INVALID = "hud.extraction.brokenRun",
		}
		local key = keys[reason]
		ExtractionWidget.flash(hud.extraction, if key then Locale.t(key) else reason, true)
	end)

	bind("ExtractionCompleted", function(payload: { [string]: any })
		ExtractionWidget.setProgress(hud.extraction, nil, nil, nil)
		ExtractionWidget.flash(hud.extraction, `EXTRACTED  +{math.floor(payload.credits or 0)}`)
	end)

	-- --- rapport de sortie ------------------------------------------------
	--
	-- Le serveur envoie un rapport DEJA chiffre. Le client ne recalcule rien
	-- et ne decide de rien : il met en page.
	bind("RaidReport", function(report: Types.RaidReport)
		if type(report) ~= "table" or type(report.outcome) ~= "string" then
			log:warn("rapport de sortie malforme, ignore")
			return
		end
		DebriefWidget.show(hud.debrief, report)
	end)

	-- --- commanditaire ----------------------------------------------------
	bind("HandlerTransmission", function(transmission: Types.Transmission)
		-- Le serveur envoie une cle ; c'est ICI qu'elle devient du texte, dans
		-- la langue de CE client.
		TransmissionWidget.transmit(
			hud.transmission,
			transmission.sender,
			Locale.t(transmission.textKey, transmission.fields),
			transmission.tone,
			transmission.holdTime
		)
	end)

	-- --- invites ----------------------------------------------------------
	table.insert(
		connections,
		ProximityPromptService.PromptShown:Connect(function(prompt)
			InteractionWidget.setPrompt(
				hud.interaction,
				Locale.maybe(prompt.ActionText) or prompt.ActionText,
				Locale.maybe(prompt.ObjectText) or prompt.ObjectText,
				prompt.KeyboardKeyCode.Name,
				prompt.HoldDuration > 0
			)
		end)
	)

	table.insert(
		connections,
		ProximityPromptService.PromptHidden:Connect(function()
			InteractionWidget.cancelHold(hud.interaction)
			InteractionWidget.setPrompt(hud.interaction, nil)
		end)
	)

	-- MAINTIEN DE LA TOUCHE.
	--
	-- L'invite disait « [MAINTENIR] FOUILLER » et il ne se passait
	-- strictement rien pendant qu'on maintenait : impossible de savoir si
	-- la touche etait prise en compte ni combien de temps il restait. On
	-- relachait au bout d'une demi-seconde en croyant a une panne.
	--
	-- La duree vient du prompt lui-meme : la barre se remplit donc
	-- exactement au rythme ou l'action aboutit, jamais plus vite.
	table.insert(
		connections,
		ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
			InteractionWidget.beginHold(hud.interaction, prompt.HoldDuration)
		end)
	)

	table.insert(
		connections,
		ProximityPromptService.PromptButtonHoldEnded:Connect(function()
			InteractionWidget.cancelHold(hud.interaction)
		end)
	)

	-- Declenchement REEL. C'est le seul retour qui distingue « j'ai tenu
	-- assez longtemps » de « j'ai relache trop tot » — les deux se
	-- ressemblaient exactement.
	table.insert(
		connections,
		ProximityPromptService.PromptTriggered:Connect(function(prompt)
			if prompt.HoldDuration <= 0 then
				InteractionWidget.beginHold(hud.interaction, 0)
			end
			InteractionWidget.completeHold(hud.interaction)
		end)
	)

	-- --- vie ---------------------------------------------------------------
	local healthConnection: RBXScriptConnection?

	local function watchCharacter(character: Model)
		if healthConnection then
			healthConnection:Disconnect()
		end

		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end

		-- Nouveau corps, aucune reference : sans cette remise a zero, la
		-- premiere lecture compare la vie pleine du personnage frais aux zero
		-- point de vie du precedent, et le journal annonce « SOIN APPLIQUE »
		-- a chaque reapparition.
		previousHealth = -1

		local function push()
			-- Deduire le soin d'une remontee de vie n'est legitime que parce
			-- que PLUS RIEN d'autre ne fait remonter la vie : la regeneration
			-- automatique de Roblox est retiree cote serveur. Si une autre
			-- source de soin apparait un jour, c'est elle qui devra annoncer.
			if previousHealth >= 0 and humanoid.Health > previousHealth + 0.5 then
				EventFeed.push(hud.events, Locale.t("hud.feed.medical"), Theme.color.health)
			end
			previousHealth = humanoid.Health

			PlayerStatusWidget.setHealth(hud.status, humanoid.Health, humanoid.MaxHealth)
		end

		push()
		healthConnection = humanoid.HealthChanged:Connect(push)
		table.insert(connections, healthConnection :: RBXScriptConnection)
	end

	if player.Character then
		watchCharacter(player.Character)
	end
	table.insert(connections, player.CharacterAdded:Connect(watchCharacter))

	-- --- responsive --------------------------------------------------------
	local camera = Workspace.CurrentCamera
	if camera then
		applyProfile(hud, camera.ViewportSize)
		table.insert(
			connections,
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				applyProfile(hud, camera.ViewportSize)
			end)
		)
	end

	return connections
end

-- ---------------------------------------------------------------- Entree --

-- Les touches 1-5 selectionnent un emplacement. Le client n'envoie QUE
-- l'index : c'est le serveur qui sait si cela veut dire equiper, soigner ou
-- recharger, et s'il l'autorise.
-- Joue la sequence d'allumage. Appelee au montage et a chaque reapparition :
-- reprendre le controle d'un nouveau corps, c'est rallumer l'equipement.
function HUDController.boot(hud: Hud)
	BootSequence.play(hud.boot, Spectate.tag(player.UserId))
	EventFeed.clear(hud.events)
	DamageIndicator.clear(hud.damageDirection)
end

function HUDController.bindInput(hud: Hud)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local request = remotes:WaitForChild("RequestSlot", 10)

	if not request or not request:IsA("RemoteEvent") then
		log:warn("remote RequestSlot absent : la barre d'equipement sera inerte")
		return
	end

	-- Touches 1 a 5.
	--
	-- Enum.KeyCode.One designe la TOUCHE PHYSIQUE, pas le caractere : sur un
	-- clavier AZERTY c'est bien « & », puis « e » « " » « ' » « ( ». Aucune
	-- correspondance a ecrire, le meme binding sert les deux dispositions.
	local keys = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
	}

	for index, key in keys do
		ContextActionService:BindAction(`BlackoutSlot{index}`, function(_, state)
			if state == Enum.UserInputState.Begin then
				(request :: RemoteEvent):FireServer(index)
			end
			return Enum.ContextActionResult.Pass
		end, false, key)
	end

	-- Molette : parcourt les armes REELLEMENT DISPONIBLES.
	--
	-- L'ancienne version basculait en dur entre les emplacements 1 et 2, sans
	-- regarder ce qu'ils contenaient. Comme le joueur demarre avec le seul
	-- pistolet en emplacement 2, la molette demandait sans cesse un
	-- emplacement 1 vide — le serveur refusait, et la bascule paraissait
	-- cassee alors qu'elle n'avait simplement rien vers quoi aller.
	local function cycleWeapon(direction: number)
		local candidates = {}
		for _, slot in hud.slots do
			if Config.Loadout.equippable[slot.key] and slot.itemId then
				table.insert(candidates, slot)
			end
		end

		-- Une seule arme : il n'y a rien a faire, et surtout rien a demander
		-- au serveur.
		if #candidates < 2 then
			return
		end

		local current = 1
		for index, slot in candidates do
			if slot.selected then
				current = index
			end
		end

		local target = ((current - 1 + direction) % #candidates) + 1
		;(request :: RemoteEvent):FireServer(candidates[target].index)
	end

	table.insert(
		inputConnections,
		UserInputService.InputChanged:Connect(function(input, processed)
			if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end
			cycleWeapon(if input.Position.Z > 0 then -1 else 1)
		end)
	)

	-- Course. On envoie l'INTENTION au serveur, qui decide s'il accelere :
	-- endurance, epuisement, vie. Le client ne touche jamais a WalkSpeed.
	local sprintRemote = remotes:WaitForChild("RequestSprint", 10)
	if sprintRemote and sprintRemote:IsA("RemoteEvent") then
		ContextActionService:BindAction("BlackoutSprint", function(_, state)
			if state == Enum.UserInputState.Begin then
				(sprintRemote :: RemoteEvent):FireServer(true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				(sprintRemote :: RemoteEvent):FireServer(false)
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
	else
		log:warn("remote RequestSprint absent : le sprint sera indisponible")
	end

	-- ACCROUPI : une BASCULE, pas un maintien.
	--
	-- Une partie de furtivite se joue accroupi pendant des minutes.
	-- Demander de garder le doigt sur la touche tout ce temps est une
	-- punition ergonomique, pas une decision de jeu.
	--
	-- L'etat vit ICI parce que c'est une preference d'entree ; ce que le
	-- serveur recoit reste une intention qu'il arbitre.
	local crouchRemote = remotes:WaitForChild("RequestCrouch", 10)
	if crouchRemote and crouchRemote:IsA("RemoteEvent") then
		local crouched = false

		local function setCrouch(value: boolean)
			if crouched == value then
				return
			end
			crouched = value
			;(crouchRemote :: RemoteEvent):FireServer(value)
		end

		ContextActionService:BindAction("BlackoutCrouch", function(_, state)
			if state == Enum.UserInputState.Begin then
				setCrouch(not crouched)
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.C, Enum.KeyCode.LeftControl)

		-- Nouveau corps, position debout. Sans ca le client se croit
		-- accroupi apres un redeploiement et la touche parait morte au
		-- premier appui.
		table.insert(
			inputConnections,
			player.CharacterAdded:Connect(function()
				crouched = false
				;(crouchRemote :: RemoteEvent):FireServer(false)
			end)
		)
	else
		log:warn("remote RequestCrouch absent : l'accroupi sera indisponible")
	end

	-- E : acquitter le rapport de sortie.
	--
	-- La meme touche que les invites d'interaction, a dessein : c'est la
	-- touche « valider » du jeu. Elle ne fait rien quand aucun rapport n'est
	-- affiche, et le rapport se ferme de lui-meme au bout de son delai —
	-- personne ne reste bloque devant un ecran faute d'avoir trouve la
	-- touche.
	local acknowledge = remotes:WaitForChild("AcknowledgeReport", 10)
	ContextActionService:BindAction("BlackoutAcknowledge", function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if not DebriefWidget.isOpen(hud.debrief) then
			return Enum.ContextActionResult.Pass
		end
		DebriefWidget.hide(hud.debrief)
		if acknowledge and acknowledge:IsA("RemoteEvent") then
			(acknowledge :: RemoteEvent):FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter)

	-- M : la carte n'existe pas encore. On le DIT plutot que de laisser la
	-- touche ne rien faire — un rappel de touche inerte est un mensonge.
	ContextActionService:BindAction("BlackoutMap", function(_, state)
		if state == Enum.UserInputState.Begin then
			InteractionWidget.alert(hud.interaction, Locale.t("hud.interaction.mapUnavailable"), Theme.color.amber)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.M)

	-- Tactile : la barre ayant ete retiree, il n'y a plus de case a toucher.
	-- Deux zones invisibles en bas d'ecran font office de molette.
	if UserInputService.TouchEnabled then
		for index, direction in { -1, 1 } do
			local button = Components.new("TextButton", {
				BackgroundTransparency = 1,
				Text = "",
				AnchorPoint = Vector2.new(0.5, 1),
				Size = UDim2.fromOffset(80, 60),
				Position = UDim2.new(0.5, if index == 1 then -60 else 60, 1, -20),
				ZIndex = 6,
			}, hud.gui) :: TextButton

			button.Activated:Connect(function()
				cycleWeapon(direction)
			end)
		end
	end
end

function HUDController.unbindInput()
	for index = 1, 5 do
		ContextActionService:UnbindAction(`BlackoutSlot{index}`)
	end
	ContextActionService:UnbindAction("BlackoutMap")
	ContextActionService:UnbindAction("BlackoutAcknowledge")
	ContextActionService:UnbindAction("BlackoutSprint")
	ContextActionService:UnbindAction("BlackoutCrouch")

	for _, connection in inputConnections do
		connection:Disconnect()
	end
	table.clear(inputConnections)
end

return HUDController
