--!strict
-- Configuration de la persistance.
--
-- Rien de sensible ici : le nom d'un DataStore n'est pas un secret, un
-- client ne peut de toute facon pas y acceder. Le schema et les migrations,
-- eux, restent cote serveur.

local DataConfig = {}

DataConfig.storeName = "BLACKOUT_PlayerData"

-- Suffixe de cle. A changer pour repartir de zero en test sans toucher aux
-- donnees de production.
DataConfig.keyPrefix = "player_"

-- Reprise sur erreur. Les DataStore echouent regulierement pour des raisons
-- transitoires (limitation de debit, incident cote Roblox) : abandonner au
-- premier echec ferait perdre une session entiere.
DataConfig.retry = {
	attempts = 5,
	baseDelay = 0.5,
	-- Delai = baseDelay * (factor ^ (tentative - 1)), plafonne.
	factor = 2,
	maxDelay = 8,
}

-- Verrou de session. Empeche deux serveurs d'ecrire le meme profil, ce qui
-- ferait perdre le butin du joueur au profit de la session la plus lente.
DataConfig.session = {
	-- Duree au-dela de laquelle un verrou est considere abandonne. Doit
	-- depasser largement l'intervalle de rafraichissement, sinon un serveur
	-- vivant se ferait voler son propre verrou.
	ttl = 90,

	-- Rafraichissement du verrou pendant la session.
	refreshInterval = 30,

	-- Tentatives d'acquisition avant d'abandonner le chargement.
	acquireAttempts = 4,
	acquireDelay = 3,
}

-- Sauvegarde periodique.
DataConfig.autosaveInterval = 120

return DataConfig
