--!strict
-- Configuration de la menace. Aucune de ces valeurs ne doit apparaitre dans
-- ThreatService : le service applique des regles, il n'en fixe aucune.

local ThreatConfig = {}

ThreatConfig.min = 0
ThreatConfig.max = 100

-- Paliers, definis par leur borne BASSE, evalues du plus haut au plus bas.
-- Une borne basse plutot qu'un intervalle ferme evite le trou classique :
-- avec des bandes 0-20 puis 21-40, une menace a 20.5 n'appartient a rien.
-- Ici elle est SAFE, et 21.0 exactement bascule en ALERT.
-- Bornes alignees sur la specification du HUD v2 : SEVERE couvre 61-85 et
-- CRITICAL 86-99, au lieu de 61-80 / 81-99. Un decalage de cinq points, mais
-- l'affichage et le systeme doivent changer de palier au meme instant, sinon
-- la barre de menace ment sur l'etat reel.
ThreatConfig.bands = {
	{ name = "HUNT", from = 100 },
	{ name = "CRITICAL", from = 86 },
	{ name = "SEVERE", from = 61 },
	{ name = "DANGER", from = 41 },
	{ name = "ALERT", from = 21 },
	{ name = "SAFE", from = 0 },
}

-- Gain passif du seul ecoulement du temps, par seconde.
--
-- 0.06/s = 3.6 points par minute, soit environ 90 points sur une fenetre de
-- vingt-cinq minutes. La menace atteint donc son sommet AU MOMENT ou les
-- sorties s'ouvrent, et pas avant : le temps seul chasse les joueurs, mais
-- il leur laisse la partie.
--
-- Valait 0.15/s, soit 225 points sur la meme fenetre — la jauge saturait
-- bien avant la fin et les actions du joueur ne pesaient plus rien a cote.
ThreatConfig.passivePerSecond = 0.06

-- Decroissance pendant les periodes calmes, par seconde.
--
-- Elle s'ajoute au gain passif, elle ne le remplace pas : le bilan net au
-- calme vaut 0.06 - 0.25 = -0.19/s, soit environ 11 points regagnes par
-- minute de silence. Se planquer paie, mais il faut y passer du temps.
--
-- Valait 0.60/s : trente secondes de calme effacaient un palier entier, et
-- tout ce que le joueur venait de declencher — tirs, pillage, course —
-- disparaissait avant qu'il en subisse la moindre consequence. Une action
-- sans repercussion n'est pas une decision.
ThreatConfig.decayPerSecond = 0.25

-- Duree sans le moindre evenement avant que la decroissance s'enclenche.
ThreatConfig.quietDelay = 20

-- Montants standards par source. Les services appellent AddSource avec un
-- identifiant, jamais avec un nombre : ajouter une source de menace ne doit
-- pas demander de toucher au code du service qui la declenche.
ThreatConfig.sources = {
	-- Un conteneur rend trois a cinq piles : a 0.8 il valait quatre points a
	-- lui seul, et piller normalement suffisait a faire monter la jauge.
	LOOT_PICKUP = 0.35,
	GENERATOR = 14,
	DOOR_BREACH = 6,
	-- PAR BALLE. Une arme automatique tire huit fois par seconde : a 2.5 une
	-- seule rafale valait vingt points. Tirer doit rester bruyant, pas
	-- suicidaire.
	GUNSHOT = 0.9,
	ENEMY_KILLED = 1.5,
	PLAYER_DOWNED = 5,
	EXTRACTION_STARTED = 10,
}

-- Bonus de butin majeur, par rarete. Les rarete absentes ne comptent pas
-- comme majeures : ramasser de la ferraille n'alerte personne.
ThreatConfig.majorLoot = {
	Rare = 4,
	Epic = 10,
	Legendary = 22,
	Mythic = 45,
}

-- The Hunt, declenche au moment precis ou la menace atteint 100.
ThreatConfig.hunt = {
	-- Duree de la traque avant retombee.
	duration = 90,

	-- Ou retombe la menace quand la traque s'acheve. Pas a zero : une
	-- carte qui vient de subir une traque n'est pas redevenue sure.
	postValue = 55,

	-- Delai minimal avant qu'une seconde traque puisse se declencher, meme
	-- si la menace remonte a 100 entre-temps.
	cooldown = 120,
}

-- Cadence d'evaluation du service.
ThreatConfig.tickRate = 1

-- Cadence de diffusion aux clients.
--
-- Un changement de palier part toujours immediatement : c'est l'information
-- qui compte. La valeur numerique, elle, derive de 0.15/s — la diffuser a
-- chaque tick faisait un FireAllClients par seconde, indefiniment, pour un
-- chiffre qui bouge d'un point toutes les sept secondes. Mesure : 1,1
-- message/s par client, soit 6,6/s a six joueurs, pour rien.
ThreatConfig.broadcastInterval = 5

return ThreatConfig
