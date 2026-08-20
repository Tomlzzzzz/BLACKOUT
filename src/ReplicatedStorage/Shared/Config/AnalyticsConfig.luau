--!strict
-- Catalogue des evenements analytiques.
--
-- Declaratif : ce fichier dit QUELS evenements existent et QUELS champs ils
-- portent. Comment ils partent appartient a AnalyticsService, et lui seul
-- parle aux API Roblox.
--
-- Un evenement absent de ce catalogue est refuse a l'emission. C'est ce qui
-- empeche les fautes de frappe de creer des evenements fantomes qu'on ne
-- decouvrirait que trois mois plus tard, en cherchant pourquoi un entonnoir
-- ne se remplit pas.

local AnalyticsConfig = {}

-- ------------------------------------------------------------------ PII ---
--
-- Cles interdites dans une charge utile. Le filtre est applique a
-- l'execution : une cle interdite fait echouer l'emission, elle n'est pas
-- silencieusement retiree — un champ qui disparait sans bruit finit par
-- etre reintroduit.
--
-- L'identifiant Roblox (UserId) n'est pas ici : c'est l'identifiant
-- technique attendu par les API Roblox, et il ne revele rien par lui-meme.
-- Le NOM d'utilisateur, lui, est choisi par la personne et l'identifie.
AnalyticsConfig.forbiddenKeys = {
	"name", "username", "displayname", "playername",
	"email", "mail", "phone", "address", "ip", "ipaddress",
	"password", "token", "birthday", "birthdate", "age",
	"realname", "firstname", "lastname",
}

-- Longueur maximale d'une valeur texte. Une chaine libre trop longue finit
-- toujours par contenir quelque chose qu'on n'aurait pas du transmettre.
AnalyticsConfig.maxStringLength = 64

-- Nombre maximal de champs par evenement.
AnalyticsConfig.maxFields = 12

-- ------------------------------------------------------------ Evenements ---
--
-- `fields` documente ce qu'on attend ; ce n'est pas une contrainte stricte
-- (un champ manquant n'invalide pas l'evenement), mais un contrat lisible.
-- `once` marque les jalons : emis une seule fois par joueur, jamais rejoues,
-- l'etat etant persiste dans le profil.
AnalyticsConfig.events = {
	PlayerJoined = {
		fields = { "level", "credits", "isNewPlayer", "raids", "extractions" },
		once = false,
	},

	-- Entonnoir d'accueil. DEFINITION PROVISOIRE : il n'existe pas encore de
	-- tutoriel. On considere qu'il demarre a la premiere connexion et
	-- s'acheve a la premiere extraction reussie. Quand un vrai tutoriel
	-- existera, seuls les points d'appel changeront.
	TutorialStarted = { fields = { "trigger" }, once = true },
	TutorialCompleted = { fields = { "trigger", "raids" }, once = true },

	RunStarted = { fields = { "raidState", "level", "stashValue" }, once = false },

	FirstLoot = { fields = { "itemId", "rarity", "quantity" }, once = true },
	FirstEnemyEncounter = { fields = { "enemy", "distance" }, once = true },
	FirstDeath = { fields = { "cause", "lostValue", "survivedFor" }, once = true },
	FirstExtraction = { fields = { "zone", "lootValue", "credits" }, once = true },

	RunExtracted = {
		fields = { "zone", "lootValue", "credits", "stacks", "duration", "threat" },
		once = false,
	},
	RunFailed = {
		fields = { "cause", "lostValue", "duration", "threat" },
		once = false,
	},

	MissionCompleted = { fields = { "missionId", "reward", "duration" }, once = false },

	BossSpawned = { fields = { "boss", "threat", "players" }, once = false },
	BossKilled = { fields = { "boss", "duration", "players" }, once = false },

	PurchaseStarted = { fields = { "product", "kind" }, once = false },
	PurchaseCompleted = { fields = { "product", "summary" }, once = false },
}

-- ------------------------------------------------------------- Entonnoirs ---
--
-- Les etapes servent a LogFunnelStepEvent : l'ordre compte, il donne le
-- numero d'etape.
AnalyticsConfig.funnels = {
	Onboarding = {
		name = "onboarding",
		steps = { "TutorialStarted", "FirstLoot", "FirstExtraction", "TutorialCompleted" },
	},
	Run = {
		name = "run",
		steps = { "RunStarted", "FirstEnemyEncounter", "RunExtracted" },
	},
}

-- Envoi vers les API Roblox. A laisser a true en production ; en Studio les
-- appels echouent sans consequence, ils sont enveloppes.
AnalyticsConfig.forwardToRoblox = true

-- Taille du tampon memoire conserve pour l'inspection en jeu.
AnalyticsConfig.bufferSize = 500

return AnalyticsConfig
