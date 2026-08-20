--!strict
-- LE COMMANDITAIRE.
--
-- Le GDD est explicite : « des entreprises privees recrutent des
-- Scavengers ». Le joueur ne s'aventure pas dans la ville pour lui-meme, il
-- est envoye. Quelqu'un paie, quelqu'un regarde, quelqu'un comptabilise.
--
-- Ce fichier est la VOIX de ce quelqu'un. Tout ce que le joueur lit de la
-- part de l'entreprise est ici et nulle part ailleurs : aucun service
-- n'ecrit de texte en dur, ils declarent un evenement et le module Handler
-- choisit quoi transmettre.
--
-- LANGUE — ce fichier ne contient plus aucun texte affichable. La voix vit
-- dans Shared/Locale, traduite par langue ; ici ne restent que le ton, la
-- priorite et la cadence.
--
-- Regles d'ecriture de cette voix, a respecter si on l'etend :
--   1. Elle ne s'inquiete jamais pour le joueur, elle s'inquiete pour la
--      cargaison. « Actif perdu, cargaison non recouvree » — dans cet ordre.
--   2. Elle est breve. Deux lignes maximum, ~64 caracteres par ligne : le
--      HUD n'a pas la place, et la froideur tient dans la concision.
--   3. Elle ne donne jamais d'ordre, elle « recommande » et « rappelle ».
--      La menace est contractuelle, pas militaire.
--   4. Elle se tait pendant THE HUNT. C'est le retournement du jeu : la
--      surveillance qui pesait devient un abandon.

local HandlerConfig = {}

-- --------------------------------------------------------- Identite ------
--
-- Le GDD ne nomme pas l'entreprise (il dit « des entreprises privees »).
-- Ce nom est donc le seul element de lore ajoute ici : une ligne a changer
-- si tu en choisis un autre, il n'apparait nulle part ailleurs dans le code.
HandlerConfig.company = "MERIDIAN"

-- Le poste qui regarde le flux. C'est lui qui parle, pas l'entreprise
-- entiere : il faut sentir un bureau, un humain paye pour surveiller.
HandlerConfig.desk = "SUPERVISION"

-- Prefixe des matricules d'actif. Le joueur n'a pas de nom pour eux.
HandlerConfig.assetPrefix = "SCAV"

-- --------------------------------------------------------- Cadence -------

-- Duree d'affichage d'une transmission, en secondes.
HandlerConfig.holdTime = 7

-- Vitesse de frappe, en caracteres par seconde. Assez lent pour qu'on voie
-- le texte arriver : c'est ce qui donne l'impression d'une liaison, pas d'un
-- panneau qui s'allume.
HandlerConfig.typeRate = 42

-- Delai minimal entre deux transmissions, quelle que soit leur origine.
-- Sans lui, une entree en zone hostile pendant une extraction empilerait
-- trois messages en une seconde sans en rendre aucun lisible.
HandlerConfig.minGap = 2.5

-- Silence apres une transmission critique : on laisse la derniere phrase
-- peser avant d'enchainer sur du remplissage.
HandlerConfig.criticalGap = 6

-- ------------------------------------------------------- Priorites -------
--
-- Une transmission de priorite superieure interrompt celle en cours. En
-- dessous, elle est abandonnee : rien n'est mis en file, parce qu'un message
-- en retard sur l'evenement qui l'a declenche ment.
HandlerConfig.priority = {
	ambient = 1,
	routine = 2,
	warning = 3,
	critical = 4,
} :: { [string]: number }

-- ----------------------------------------------------- Vocabulaire -------
--
-- Chaque cle declare son TON et sa PRIORITE. Le texte, lui, vit dans
-- Shared/Locale : le serveur n'a pas de langue, il envoie une cle.
--
-- Le nombre de variantes se deduit du fichier de langue de reference —
-- ajouter « handler.idle.4 » dans en.luau suffit a enrichir la voix, sans
-- toucher a ce fichier.
--
--   tone      neutral | technical | warning | danger  (couleur cote HUD)
--   priority  ambient | routine | warning | critical  (interruption)
--   once      ne part qu'une fois par raid

export type Line = {
	tone: string,
	priority: string,
	once: boolean?,
}

HandlerConfig.lines = {
	deploy = { tone = "technical", priority = "routine", once = true },
	firstLoot = { tone = "neutral", priority = "routine", once = true },

	cargoLow = { tone = "warning", priority = "routine" },
	cargoMid = { tone = "warning", priority = "routine" },
	cargoHigh = { tone = "danger", priority = "warning" },

	bandALERT = { tone = "neutral", priority = "routine" },
	bandDANGER = { tone = "warning", priority = "warning" },
	bandSEVERE = { tone = "warning", priority = "warning" },
	bandCRITICAL = { tone = "danger", priority = "critical" },

	-- THE HUNT. Le retournement : la surveillance s'arrete.
	hunt = { tone = "danger", priority = "critical", once = true },
	huntEnd = { tone = "technical", priority = "warning" },

	teammateDown = { tone = "danger", priority = "warning" },
	teammateExtracted = { tone = "neutral", priority = "routine" },

	lowHealth = { tone = "danger", priority = "warning" },
	idle = { tone = "warning", priority = "routine" },

	windowWarning = { tone = "warning", priority = "warning" },
	windowFinal = { tone = "danger", priority = "critical" },
	windowClosed = { tone = "danger", priority = "critical" },

	extractionOpen = { tone = "technical", priority = "routine" },
	extractionDone = { tone = "neutral", priority = "routine" },
	extractionLost = { tone = "warning", priority = "warning" },

	contractAssigned = { tone = "technical", priority = "routine" },
	objectiveDone = { tone = "neutral", priority = "routine" },
	contractDone = { tone = "neutral", priority = "warning" },

	-- Releves de capteurs. Tous adosses a un fait mesure serveur.
	contact = { tone = "warning", priority = "routine" },
	contactClose = { tone = "danger", priority = "warning" },
	hunted = { tone = "danger", priority = "critical" },
	gunfire = { tone = "warning", priority = "routine" },
	heavySignature = { tone = "danger", priority = "critical", once = true },
	weather = { tone = "technical", priority = "ambient" },
	district = { tone = "technical", priority = "ambient" },
	batteryLow = { tone = "warning", priority = "routine", once = true },

	ambient = { tone = "technical", priority = "ambient" },
} :: { [string]: Line }

-- ------------------------------------------------------ Declencheurs -----

-- Duree sans aucun ramassage avant que le bureau s'en apercoive.
HandlerConfig.idleAfter = 100

-- Intervalle entre deux rappels d'inactivite, tant que rien n'est ramasse.
HandlerConfig.idleRepeat = 75

-- Intervalle des transmissions de remplissage.
--
-- CONSERVE MAIS PLUS EMIS : Handler.tick ne declenche plus d'ambiance. La
-- valeur reste pour ne pas casser les tests de reglage, et parce qu'un
-- retour en arriere ne doit pas demander de retrouver le nombre.
HandlerConfig.ambientEvery = 145

-- ------------------------------------------------------- Capteurs -------
--
-- Portee de detection des contacts, en studs.
--
-- DOIT DEPASSER la portee de detection des crawlers (60). J'avais d'abord
-- mis 45, en me disant que le commanditaire ne devait pas voir plus loin que
-- l'ennemi — et le releve n'est jamais parti une seule fois. La raison est
-- mecanique : tout ennemi assez proche pour entrer dans 45 studs avait deja
-- repere le joueur, donc il etait deja en poursuite, donc ecarte comme
-- doublon de l'alerte de verrouillage.
--
-- Il faut au contraire une BANDE ou le capteur voit avant la creature :
-- entre 60 et 78 studs, le joueur est prevenu qu'il y a quelque chose sans
-- avoir encore ete vu. C'est exactement ce que le commanditaire vend.
HandlerConfig.contactRadius = 78

-- En deca de cette distance, le contact devient une alerte : la creature est
-- entree dans sa propre portee de detection, le joueur n'a plus d'avance.
HandlerConfig.contactCloseRadius = 45

-- Delai minimal entre deux releves de contact, en secondes. Sans lui, une
-- meute de six crawlers produirait six lignes par seconde.
HandlerConfig.contactCooldown = 22

-- Cadence du balayage de proximite. Deux secondes suffisent : un crawler ne
-- traverse pas quarante-cinq studs entre deux passages.
HandlerConfig.contactRate = 2

-- Delai minimal entre deux releves de tir.
HandlerConfig.gunfireCooldown = 12

-- Portee au-dela de laquelle un tir n'est plus releve.
HandlerConfig.gunfireRadius = 220

-- Charge de batterie sous laquelle le bureau previent, une seule fois.
HandlerConfig.batteryWarnAt = 25

-- Fraction de vie sous laquelle la remarque biometrique part.
HandlerConfig.lowHealthAt = 0.3

-- Paliers de cargaison, en credits. Alignes sur Theme.cargo.tiers : le HUD
-- change de couleur au moment exact ou la voix commente, sinon les deux se
-- contredisent.
HandlerConfig.cargoTiers = {
	{ at = 1500, key = "cargoLow" },
	{ at = 6000, key = "cargoMid" },
	{ at = 15000, key = "cargoHigh" },
}

-- Seuils d'alerte sur la fenetre de contrat, en secondes restantes.
HandlerConfig.windowWarnAt = { 300, 120 }
HandlerConfig.windowFinalAt = 60

-- Les directives ont demenage dans ContractConfig : ce sont maintenant les
-- objectifs d'un contrat tenu par MissionService, pas une liste a part.

return HandlerConfig
