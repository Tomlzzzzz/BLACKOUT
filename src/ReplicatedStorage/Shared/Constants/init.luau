--!strict
-- Valeurs figees, partagees client/serveur. Rien de reglable a chaud ici :
-- ce qui doit se tuner en cours de dev va dans Shared/Config.

local Constants = {}

Constants.GAME_NAME = "BLACKOUT"
Constants.DATA_VERSION = 1

-- Raid
-- La duree de la fenetre de contrat a demenage dans Config.Match : elle
-- ferme maintenant reellement la partie, donc elle se tune.
Constants.MAX_PLAYERS_PER_RAID = 12
Constants.DEPLOY_COUNTDOWN = 10

-- Joueur
Constants.BASE_HEALTH = 100
-- Les deux contenants du joueur, tous deux exprimes en poids :
--   CARRY  = le sac emporte en raid, perdu a la mort
--   STASH  = le coffre, persiste entre les raids
Constants.BASE_CARRY_WEIGHT = 40
Constants.STASH_CAPACITY = 600

-- Donnees
Constants.DATASTORE_NAME = "BLACKOUT_PlayerData_v1"
Constants.AUTOSAVE_INTERVAL = 120
Constants.SAVE_RETRY_COUNT = 3

-- Remotes crees au boot par Bootstrap, sous ReplicatedStorage.Remotes.
-- Nom -> ClassName. Toute communication passe par cette liste : pas de
-- RemoteEvent cree a la volee ailleurs dans le code.
Constants.REMOTES = {
	-- Note : pas de RequestExtraction. L'extraction se declenche par la
	-- presence dans une zone, mesuree serveur — le client n'a rien a
	-- demander. Le RemoteFunction existait sans OnServerInvoke : un client
	-- qui l'aurait invoque serait reste bloque indefiniment.
	ExtractionProgress = "RemoteEvent",
	InventoryChanged = "RemoteEvent",
	RequestMoveItem = "RemoteFunction",
	CreditsChanged = "RemoteEvent",
	RaidStateChanged = "RemoteEvent",
	ThreatLevelChanged = "RemoteEvent",
	MissionUpdated = "RemoteEvent",
	LootGranted = "RemoteEvent",
	ExtractionStarted = "RemoteEvent",
	ExtractionCancelled = "RemoteEvent",
	ExtractionCompleted = "RemoteEvent",
	HuntStarted = "RemoteEvent",
	HuntEnded = "RemoteEvent",
	StaminaChanged = "RemoteEvent",
	EquippedChanged = "RemoteEvent",
	HudSnapshot = "RemoteEvent",

	-- Le commanditaire. Trois canaux purement descendants : le client ne
	-- repond jamais au bureau, il le subit.
	HandlerTransmission = "RemoteEvent",
	ContractWindow = "RemoteEvent",
	DirectiveChanged = "RemoteEvent",

	-- HUD v2. Etats supplementaires que la maquette affiche et qui n'avaient
	-- aucune source serveur : armure, batterie, contrat a objectifs, barre
	-- d'equipement, informations de zone.
	VitalsChanged = "RemoteEvent",
	ContractChanged = "RemoteEvent",
	LoadoutChanged = "RemoteEvent",
	WorldInfoChanged = "RemoteEvent",
	DamageTaken = "RemoteEvent",

	-- Seul canal montant du HUD : demander a equiper un emplacement. Le
	-- serveur valide et decide ; le client ne fait qu'appuyer sur une touche.
	RequestSlot = "RemoteEvent",

	-- Le client declare qu'il MAINTIENT la touche de course. Le serveur
	-- decide s'il accelere reellement : endurance, etat, vie.
	RequestSprint = "RemoteEvent",

	-- Meme principe pour l'accroupi : une INTENTION. C'est le serveur qui
	-- pose l'attribut lu par les creatures, sans quoi un client modifie
	-- se declarerait accroupi en courant.
	RequestCrouch = "RemoteEvent",

	-- Verdict d'une demande d'emplacement. Sans lui, une action refusee —
	-- vie deja pleine, case vide — ne produisait rien du tout a l'ecran et
	-- passait pour un bug.
	SlotResult = "RemoteEvent",

	-- Retour de combat : touche confirmee et cible abattue. Purement
	-- illustratif — le serveur a deja applique les degats, le client ne fait
	-- qu'afficher un marqueur.
	CombatFeedback = "RemoteEvent",

	-- Vue spectateur. Purement descendant : le serveur dit QUI peut etre
	-- regarde, le client choisit lequel. Le choix de camera n'a aucune
	-- consequence de jeu, il n'a donc rien a faire valider.
	SpectateChanged = "RemoteEvent",

	-- Rapport de fin de raid. Un seul message, envoye au seul joueur
	-- concerne, quelle que soit la maniere dont sa sortie s'est terminee.
	-- Le client n'a rien a recalculer : tout est deja chiffre serveur.
	RaidReport = "RemoteEvent",

	-- Le joueur acquitte son rapport. Purement declaratif : le serveur ne
	-- s'en sert que pour cesser de considerer le rapport comme en attente,
	-- jamais pour accorder quoi que ce soit.
	AcknowledgeReport = "RemoteEvent",

	-- Le client peut demander l'AFFICHAGE d'une invite d'achat, jamais un
	-- octroi. Ce remote ne fait qu'appeler PromptProductPurchase ; toute
	-- attribution passe exclusivement par ProcessReceipt.
	RequestPurchase = "RemoteEvent",
	PurchaseResult = "RemoteEvent",

	-- Tir : le client envoie une INTENTION (origine, direction). Le serveur
	-- fait son propre raycast et n'accepte aucune revendication de touche.
	RequestFire = "RemoteEvent",
	RequestReload = "RemoteEvent",
	WeaponStateChanged = "RemoteEvent",
	ShotFired = "RemoteEvent",
}

table.freeze(Constants)

return Constants
