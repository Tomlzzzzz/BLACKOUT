--!strict
-- Configuration des ennemis. Aucune de ces valeurs ne doit apparaitre dans
-- EnemyService ni dans CrawlerBrain.

local EnemyConfig = {}

-- Journalisation detaillee de l'IA. A laisser a false : chaque crawler
-- produirait sinon plusieurs lignes par seconde, et six crawlers noieraient
-- la console en quelques instants.
EnemyConfig.debugLogging = false

EnemyConfig.maxAlive = 24

-- ------------------------------------------------------- Repeuplement ----
--
-- LA CARTE NE DOIT JAMAIS SE VIDER.
--
-- Les crawlers etaient poses une seule fois au demarrage, sur des marqueurs
-- fixes. Six ennemis tues, et la zone devenait un terrain de promenade pour
-- le reste de la fenetre de contrat : plus aucune raison de se cacher, plus
-- aucune raison d'extraire. `spawnBatchSize` et `spawnInterval` existaient
-- deja dans ce fichier — ils n'etaient lus nulle part.
--
-- Le repeuplement vise un EFFECTIF, il ne compte pas les morts : c'est ce
-- qui garantit qu'une zone nettoyee se remplit, et qu'une zone deja pleine
-- ne se surcharge pas.
EnemyConfig.population = {
	-- Effectif vise en permanence.
	targetAlive = 8,
	-- Secondes entre deux verifications d'effectif.
	interval = 15,
	-- Apparitions maximales par verification. Volontairement faible : la
	-- pression doit remonter progressivement, pas ressusciter une vague
	-- entiere d'un coup.
	batch = 2,

	-- Anneau d'apparition autour d'un joueur choisi au hasard.
	--
	-- On apparait AUTOUR DES JOUEURS et non a des points fixes : sur une
	-- grande carte, des positions fixes laissent le joueur seul des qu'il
	-- s'en eloigne. Le minimum garantit qu'aucune creature ne se
	-- materialise dans le champ de vision.
	minDistance = 130,
	maxDistance = 280,

	-- Tirages avant d'abandonner pour ce tour. Un echec n'est pas une
	-- erreur : la verification suivante reessaiera dans quinze secondes.
	attempts = 14,

	-- Hauteur depuis laquelle on sonde le sol, et repli si la sonde ne
	-- touche rien (trou dans la carte, joueur au-dessus du vide).
	probeHeight = 240,
	probeDepth = 600,
	fallbackY = 4,
}

-- Distance en studs sous laquelle un spawn est annule si un joueur est a
-- portee : evite les apparitions dans le champ de vision.
EnemyConfig.minSpawnDistance = 120

-- Sanctuaire d'apparition des joueurs.
--
-- Sans lui, un ennemi poste pres du point de reapparition tue le joueur
-- avant qu'il ait repris le controle, puis recommence a chaque respawn : la
-- partie devient injouable sans qu'aucun systeme ne soit en faute.
--
-- Deux protections complementaires, parce qu'aucune ne suffit seule :
--   `radius`    empeche la situation de se produire (aucun ennemi ne vit
--               ni ne poursuit dans cette bulle)
--   `graceTime` couvre le cas ou elle se produit quand meme — ennemi place
--               a la main, sanctuaire mal dimensionne, joueur telporte
EnemyConfig.spawnGuard = {
	radius = 70,
	graceTime = 5,
}

EnemyConfig.crawler = {
	-- Les six valeurs demandees par la specification.
	DetectionRange = 60,
	AttackRange = 6,
	Damage = 18,
	AttackCooldown = 1.4,
	WalkSpeed = 9,
	ChaseSpeed = 19,

	Health = 90,

	-- Hysteresis de poursuite : on detecte a 60 mais on ne lache qu'au-dela
	-- de 85. Sans cet ecart, une cible qui oscille autour de la limite de
	-- detection ferait clignoter l'etat plusieurs fois par seconde.
	LoseTargetRange = 85,

	-- Duree sans voir la cible avant d'abandonner la poursuite. C'est ce
	-- delai qui rend la fuite possible : se cacher doit payer.
	LoseTargetTime = 4,

	-- Duree passee a fouiller la derniere position connue.
	InvestigateTime = 6,

	-- Repos entre deux patrouilles.
	IdleTime = { min = 2, max = 5 },

	-- Rayon autour du point d'ancrage dans lequel les points de patrouille
	-- sont tires.
	PatrolRadius = 45,

	-- Distance en deca de laquelle un point de destination est considere
	-- atteint.
	ArriveRadius = 4,

	-- Delai maximal accorde a un trajet de patrouille avant de renoncer,
	-- au cas ou le chemin serait devenu impraticable.
	PatrolTimeout = 20,

	-- Trois cadences distinctes, volontairement decouplees. Rien de tout
	-- ceci ne tourne par image : la perception est le poste le plus cher,
	-- la decision est bon marche, et le calcul de chemin est le plus lourd
	-- des trois.
	SenseRate = 0.3,
	ThinkRate = 0.2,
	RepathRate = 0.7,

	-- Distance dont la cible doit s'etre deplacee pour justifier un nouveau
	-- calcul de chemin. Recalculer pour vingt centimetres coute cher et ne
	-- change rien au trajet.
	RepathThreshold = 6,
}

-- Variante boss : meme cerveau, statistiques amplifiees. Un archetype a
-- part entiere viendra plus tard ; pour l'instant c'est un Crawler plus
-- dangereux, ce qui suffit a rendre BossSpawned et BossKilled reels.
-- Le Warden. C'est LUI que The Hunt lache sur la ville — le document de
-- design le nomme, le jeu doit le nommer aussi.
EnemyConfig.boss = {
	name = "Warden",
	healthMultiplier = 6,
	damageMultiplier = 1.8,
	detectionMultiplier = 1.5,
	scale = 2,
	color = Color3.fromRGB(120, 25, 30),
}

-- Positions de secours, utilisees quand Workspace.EnemySpawns est vide.
-- Volontairement au-dela du sanctuaire : un point de secours qui tomberait
-- dedans serait rejete au demarrage et le raid n'aurait aucun ennemi.
EnemyConfig.fallbackSpawns = {
	Vector3.new(110, 5, 110),
	Vector3.new(-110, 5, 110),
	Vector3.new(110, 5, -110),
	Vector3.new(-110, 5, -110),
	Vector3.new(0, 5, 140),
	Vector3.new(0, 5, -140),
}

-- Attribut lu sur les marqueurs de Workspace.EnemySpawns.
EnemyConfig.kindAttribute = "EnemyKind"
EnemyConfig.defaultKind = "crawler"

return EnemyConfig
