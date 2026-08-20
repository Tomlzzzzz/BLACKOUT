--!strict
-- Types partages client/serveur.
-- Ce module ne require rien : il doit rester chargeable depuis n'importe ou,
-- a n'importe quel moment du boot, sans creer de cycle.

export type ServiceContext = {
	Get: (name: string) -> Service?,
	Remotes: Folder,
}

export type Service = {
	Name: string,
	Priority: number?,
	Init: ((ctx: ServiceContext) -> ())?,
	Start: (() -> ())?,
	Stop: (() -> ())?,
}

export type Rarity =
	"Common"
	| "Uncommon"
	| "Rare"
	| "Epic"
	| "Legendary"
	| "Mythic"

export type ItemId = string

-- Definition statique d'un item. Vit dans ItemDatabase et nulle part
-- ailleurs : rarete, valeur et poids ne sont jamais copies dans une pile,
-- sinon ils derivent et deviennent falsifiables par le client.
export type ItemDef = {
	id: ItemId,
	name: string,
	rarity: Rarity,
	value: number,
	weight: number,
	stackable: boolean,
	maxStack: number,
}

-- Ce qui est reellement stocke dans un inventaire : un id et une quantite.
-- Rien d'autre.
export type ItemStack = {
	id: ItemId,
	quantity: number,
}

export type Inventory = {
	slots: { ItemStack },
	capacity: number,
}

-- Vue resolue (definition + pile), pour l'UI et les retours d'API.
-- Construite a la demande, jamais persistee.
export type ResolvedItem = {
	id: ItemId,
	name: string,
	rarity: Rarity,
	quantity: number,
	weight: number,
	value: number,
}

-- Code stable, pas un message : le client et les tests branchent dessus.
export type InventoryError =
	"UNKNOWN_ITEM"
	| "INVALID_QUANTITY"
	| "OVER_CAPACITY"
	| "NOT_ENOUGH"
	| "NO_INVENTORY"
	| "DUPLICATE_REQUEST"
	| "BAD_REQUEST"

export type InventoryResult = {
	ok: boolean,
	error: InventoryError?,
}

-- `weight` est ici un poids de tirage, sans rapport avec le poids porte.
export type LootEntry = {
	id: ItemId,
	weight: number,
	min: number,
	max: number,
}

export type RaidState = "Lobby" | "Deploying" | "InRaid" | "Extracting" | "Ended"

-- Resultat d'un transfert entre deux contenants. `leftBehind` n'est pas une
-- erreur : c'est le cas normal d'un coffre plein, et l'appelant doit pouvoir
-- le dire au joueur.
export type TransferSummary = {
	moved: { ItemStack },
	leftBehind: { ItemStack },
}

export type PlayerStatistics = {
	Raids: number,
	Extractions: number,
	Deaths: number,
	Kills: number,
	CreditsEarned: number,
	ItemsLooted: number,
	Playtime: number,
}

-- Le profil ne contient que ce qui persiste, et ses champs portent les noms
-- du schema persiste — c'est ce qui part dans le DataStore.
--
-- Le sac de raid n'est deliberement pas ici : il est transitoire, vit dans
-- InventoryService le temps d'une partie, et disparait a la mort. Melanger
-- les deux, c'est sauvegarder du butin qui aurait du etre perdu.
--
-- Le coffre est stocke comme une simple liste de piles : la capacite vient
-- de la configuration au chargement, la persister figerait une valeur qu'on
-- veut pouvoir retoucher.
export type PlayerProfile = {
	Version: number,
	Credits: number,
	XP: number,
	Level: number,
	Reputation: { [string]: number },
	Inventory: {
		Stash: { ItemStack },
		Equipped: ItemId?,
	},
	UnlockedItems: { [string]: boolean },
	BaseUpgrades: { [string]: number },
	Cosmetics: {
		Owned: { [string]: boolean },
		Equipped: { [string]: string },
	},
	Statistics: PlayerStatistics,
}

-- Enveloppe reellement ecrite dans le DataStore : le profil, plus le verrou
-- de session qui ne fait pas partie du schema du joueur.
export type StoredEnvelope = {
	profile: PlayerProfile,
	session: {
		jobId: string,
		at: number,
	}?,
}

export type ExtractionZoneDef = {
	name: string,
	radius: number,
	holdTime: number,
	requiresItem: ItemId?,
}

-- Les quatre conditions evaluees a chaque pas d'extraction. Les separer
-- ainsi permet de tester chaque cause d'annulation isolement, sans monde.
export type ExtractionConditions = {
	inZone: boolean,
	alive: boolean,
	zoneActive: boolean,
	runValid: boolean,
}

export type ExtractionPhase = "Running" | "Cancelled" | "Completed"

export type ExtractionProgress = {
	zoneName: string,
	holdTime: number,
	elapsed: number,
	phase: ExtractionPhase,
	reason: string?,
}

-- "finished" signale un pas effectue sur une extraction deja terminee : ce
-- n'est ni un succes ni un echec, c'est un appel de trop. Le distinguer de
-- "completed" est ce qui empeche de recompenser deux fois.
export type ExtractionOutcome = "running" | "cancelled" | "completed" | "finished"

export type WeaponState = {
	itemId: ItemId,
	ammoInMagazine: number,
	lastFiredAt: number,
	reloadingUntil: number?,
	pendingReload: number?,
	shotsThisSecond: number,
	secondStartedAt: number,
}

export type FireDecision = {
	ok: boolean,
	error: string?,
	ammoInMagazine: number,
}

export type StaminaState = {
	value: number,
	lastEffortAt: number,
	exhausted: boolean,
}

-- Instantane envoye au client a l'apparition, pour que le HUD ne demarre
-- pas vide en attendant qu'un evenement veuille bien se produire.
export type HudSnapshot = {
	credits: number,
	threat: number,
	band: ThreatBand,
	stamina: number,
	maxStamina: number,
	equipped: string?,
}

-- ------------------------------------------------------- HUD v2 --------

-- Vitaux hors vie. La vie vient du Humanoid, deja repliquee par le moteur :
-- la dupliquer dans un remote serait du trafic pour une valeur que le client
-- possede deja.
export type Vitals = {
	armor: number,
	maxArmor: number,
	battery: number,
	maxBattery: number,
	lightOn: boolean,
}

export type ObjectiveKind = "collect" | "reach" | "extract"

export type ContractObjective = {
	kind: ObjectiveKind,
	-- Cle de localisation du libelle. Meme raison que pour Transmission.
	labelKey: string,
	item: ItemId?,
	quantity: number?,
	progress: number,
	done: boolean,
}

export type Contract = {
	id: string,
	titleKey: string,
	subtitleKey: string,
	objectives: { ContractObjective },
	reward: number,
	complete: boolean,
}

-- Une case de la barre d'equipement. `itemId` nil = case vide.
export type LoadoutSlot = {
	index: number,
	key: string,
	label: string,
	counter: string,
	itemId: ItemId?,
	name: string?,
	quantity: number,
	ammo: number?,
	magazine: number?,
	percent: number?,
	selected: boolean,
}

export type WorldInfo = {
	district: string,
	weather: string,
	clock: number,
}

-- Degats encaisses, envoyes au client pour le retour visuel. Le client ne
-- fait qu'illustrer : la vie a deja ete appliquee serveur.
export type DamageReport = {
	amount: number,
	toArmor: number,
	toHealth: number,
	remaining: number,
	severity: string,
	source: string?,
	-- Position de l'agresseur, pour l'indicateur directionnel. Le client
	-- calcule l'angle relatif a sa camera : savoir d'ou vient le coup est la
	-- moitie de l'information en premiere personne.
	origin: Vector3?,
}

-- ------------------------------------------------- Le commanditaire ----
--
-- Une transmission du bureau qui surveille le flux du joueur. Construite par
-- Shared/Handler, envoyee telle quelle au client : le HUD ne compose aucun
-- texte, il affiche ce qu'on lui donne.
--
-- `tone` vaut "neutral" | "technical" | "warning" | "danger". Volontairement
-- laisse en string plutot qu'en union : les tons sont declares dans
-- HandlerConfig, et coupler la config aux types pour gagner une union
-- obligerait chaque fichier de config a require Types. HandlerTests verifie
-- a la place qu'aucun ton inconnu ne trolle dans le vocabulaire.
export type Transmission = {
	key: string,
	sender: string,
	-- CLE de localisation, pas du texte. Six joueurs d'un meme raid peuvent
	-- lire six langues differentes : composer la phrase serveur reviendrait
	-- a en imposer une seule.
	textKey: string,
	fields: { [string]: any }?,
	tone: string,
	priority: number,
	holdTime: number,
}

-- Ce que l'entreprise reclame sur ce raid. `progress` est serveur : le client
-- ne fait que l'afficher.
export type Directive = {
	item: ItemId,
	label: string,
	quantity: number,
	reward: number,
	progress: number,
	done: boolean,
}

-- Fenetre de contrat. Le temps n'appartient pas au joueur : c'est le
-- commanditaire qui ouvre et referme.
export type ContractWindow = {
	state: RaidState,
	remaining: number,
	duration: number,
}

export type CrawlerState = "Idle" | "Patrol" | "Investigate" | "Chase" | "Attack"

-- Instantane de perception fourni au cerveau. Le cerveau ne regarde jamais
-- le monde lui-meme : c'est ce qui permet de le faire tourner sans partie.
export type CrawlerPerception = {
	now: number,
	selfPosition: Vector3,
	targetPosition: Vector3?,
	targetDistance: number?,
	targetVisible: boolean,
	targetAlive: boolean,
}

export type CrawlerBrainState = {
	state: CrawlerState,
	stateSince: number,
	lastSeenAt: number?,
	lastKnownPosition: Vector3?,
	destination: Vector3?,
	anchor: Vector3,
	lastAttackAt: number,
	idleUntil: number,
}

export type CrawlerDecision = {
	state: CrawlerState,
	previousState: CrawlerState,
	changed: boolean,
	moveTo: Vector3?,
	speed: number,
	attack: boolean,
	repath: boolean,
	reason: string,
}

-- Candidat a la selection de cible. Volontairement reduit a ce dont la
-- decision a besoin : pas de Player, donc testable avec six joueurs fictifs.
export type TargetCandidate = {
	id: string,
	position: Vector3,
	valid: boolean,
}

export type ThreatBand = "SAFE" | "ALERT" | "DANGER" | "SEVERE" | "CRITICAL" | "HUNT"

export type ThreatMeter = {
	value: number,
	lastEventAt: number,
	huntTriggeredAt: number?,
}

-- Toute mutation de la menace rend ce compte rendu. Porter l'ancien palier
-- a cote du nouveau evite que chaque appelant ait a le memoriser pour
-- savoir s'il doit prevenir quelqu'un.
export type ThreatChange = {
	value: number,
	previous: number,
	band: ThreatBand,
	previousBand: ThreatBand,
	reason: string,
}

export type ExtractionReward = {
	lootValue: number,
	bonus: number,
	credits: number,
	xpGained: number,
	level: number,
	leveledUp: boolean,
}

-- ------------------------------------------------ Rapport de fin de raid --
--
-- Les trois manieres de sortir d'un raid. Elles partagent une structure de
-- rapport unique : c'est ce qui garantit que l'echec est raconte avec le
-- meme soin que la reussite.
--
--   EXTRACTED  sorti par une zone, cargaison au coffre
--   KIA        mort sur place, sac perdu
--   EXPIRED    fenetre de contrat fermee, actif abandonne sur zone
export type RaidOutcome = "EXTRACTED" | "KIA" | "EXPIRED"

-- --------------------------------------------------------- Spectateur ----
--
-- Un actif sorti du raid — mort ou extrait — ne rejoue pas avant la fenetre
-- de contrat suivante. Il regarde les autres travailler, ce qui est aussi ce
-- que le commanditaire fait de lui depuis le debut.
export type SpectateTarget = {
	userId: number,
	name: string,
	-- Matricule affiche. Le nom Roblox dit qui est derriere l'ecran, le
	-- matricule dit ce que la compagnie voit.
	tag: string,
}

export type SpectateState = {
	active: boolean,
	-- Pourquoi on est sorti. Change le texte, pas la mecanique.
	reason: string,
	targets: { SpectateTarget },
}

-- Une ligne de manifeste. `unitValue` est conserve a cote du total : sans
-- lui, « 11 x Bandage — 550 » ne dit pas ce que vaut un bandage, et le
-- joueur ne peut pas apprendre les prix.
export type ReportLine = {
	id: ItemId,
	quantity: number,
	unitValue: number,
	value: number,
	rarity: string,
}

export type RaidReport = {
	outcome: RaidOutcome,
	reference: string,
	zone: string?,
	duration: number,
	rating: string,

	manifest: { ReportLine },
	overflowCount: number,
	overflowValue: number,
	manifestValue: number,
	leftBehind: number,

	bonus: number,
	credits: number,
	xpGained: number,
	level: number,
	leveledUp: boolean,
	balance: number,

	kills: number,
	damageTaken: number,
	peakThreat: number,

	objectivesDone: number,
	objectivesTotal: number,
	contractKey: string?,
	contractComplete: boolean,
}

return {}
