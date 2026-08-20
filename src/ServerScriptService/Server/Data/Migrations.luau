--!strict
-- Migrations de schema.
--
-- Une etape par saut de version : `steps[n]` transforme un profil en
-- version n vers la version n+1. Elles sont appliquees en chaine, dans
-- l'ordre, jusqu'a la version courante.
--
-- REGLES POUR TOUTE NOUVELLE ETAPE
--   1. Ne jamais supprimer une cle. Renommer = copier puis laisser
--      l'ancienne en place ; une etape ulterieure la retirera, quand plus
--      aucun serveur ancien ne tournera.
--   2. Toujours poser Version a la valeur d'arrivee.
--   3. Etre idempotente autant que possible : une migration rejouee sur un
--      profil deja migre ne doit rien casser.
--   4. Ne jamais lever. Une migration qui echoue bloque le joueur hors de
--      son compte ; mieux vaut un champ par defaut qu'une session refusee.

local Migrations = {}

export type Step = (data: { [any]: any }) -> { [any]: any }

Migrations.steps = {} :: { [number]: Step }

-- ---------------------------------------------------------------- 1 -> 2 --
--
-- La version 1 etait le profil en memoire du prototype :
--   { userId, credits, xp, level, stash = {slots, capacity}, stats = {...} }
--
-- La version 2 introduit Reputation, UnlockedItems, BaseUpgrades et
-- Cosmetics, passe les champs en PascalCase, sort le coffre sous Inventory
-- et enrichit les statistiques.
--
-- Les anciennes cles sont recopiees, pas deplacees : si ce serveur retombe
-- en panne au milieu et qu'un serveur v1 reprend la main, il retrouve les
-- siennes.
Migrations.steps[1] = function(data)
	data.Credits = data.Credits or data.credits or 2500
	data.XP = data.XP or data.xp or 0
	data.Level = data.Level or data.level or 1

	data.Reputation = data.Reputation or {}
	data.UnlockedItems = data.UnlockedItems or {}
	data.BaseUpgrades = data.BaseUpgrades or {}
	data.Cosmetics = data.Cosmetics or { Owned = {}, Equipped = {} }

	-- Le coffre v1 etait un objet Inventory complet ({slots, capacity}).
	-- Seule la liste de piles se persiste : la capacite vient desormais de
	-- la configuration, pour pouvoir la retoucher sans migration.
	local inventory = data.Inventory or {}
	if inventory.Stash == nil then
		local legacy = data.stash
		if type(legacy) == "table" and type(legacy.slots) == "table" then
			inventory.Stash = legacy.slots
		elseif type(legacy) == "table" then
			inventory.Stash = legacy
		else
			inventory.Stash = {}
		end
	end
	data.Inventory = inventory

	local legacyStats = data.stats or {}
	local stats = data.Statistics or {}
	stats.Raids = stats.Raids or legacyStats.raids or 0
	stats.Extractions = stats.Extractions or legacyStats.extractions or 0
	stats.Deaths = stats.Deaths or legacyStats.deaths or 0
	stats.Kills = stats.Kills or 0
	stats.CreditsEarned = stats.CreditsEarned or 0
	stats.ItemsLooted = stats.ItemsLooted or 0
	stats.Playtime = stats.Playtime or 0
	data.Statistics = stats

	data.Version = 2
	return data
end

-- ---------------------------------------------------------------- 2 -> 3 --
--
-- Introduit la monetisation : monnaie cosmetique, bonus temporaires, cache
-- des gamepasses, et surtout l'historique des achats honores dont depend
-- l'idempotence de ProcessReceipt.
--
-- Purement additive : aucun champ existant n'est touche.
Migrations.steps[2] = function(data)
	data.BlackTokens = data.BlackTokens or 0
	data.Boosts = data.Boosts or {}
	data.Gamepasses = data.Gamepasses or {}

	local purchases = data.Purchases or {}
	purchases.seen = purchases.seen or {}
	purchases.order = purchases.order or {}
	data.Purchases = purchases

	data.Version = 3
	return data
end

-- ---------------------------------------------------------------- 3 -> 4 --
--
-- Jalons analytiques. Purement additive.
--
-- Les joueurs existants demarrent avec des jalons vides : ils reverront donc
-- passer leurs evenements "First*" une fois. C'est assume et prefere a
-- l'inverse — deviner qu'un joueur a deja loote a partir de ses statistiques
-- produirait des jalons faux, et un entonnoir faux vaut moins que rien.
Migrations.steps[3] = function(data)
	data.Milestones = data.Milestones or {}
	data.Version = 4
	return data
end

-- Applique toutes les etapes necessaires pour amener `data` a
-- `targetVersion`. Retourne le profil, le nombre d'etapes appliquees, et
-- une erreur eventuelle.
--
-- Une etape qui leve est capturee : on rend ce qu'on a pu migrer plutot que
-- de refuser la session. Un joueur avec un champ par defaut est un incident
-- mineur ; un joueur qui ne peut plus se connecter est un incident majeur.
function Migrations.migrate(data: { [any]: any }, targetVersion: number): ({ [any]: any }, number, string?)
	if type(data) ~= "table" then
		return data, 0, "profil absent"
	end

	local version = if type(data.Version) == "number" then data.Version else 1
	local applied = 0

	while version < targetVersion do
		local step = Migrations.steps[version]
		if not step then
			return data, applied, `aucune migration depuis la version {version}`
		end

		local ok, result = pcall(step, data)
		if not ok then
			return data, applied, `migration {version} -> {version + 1} a leve : {result}`
		end

		data = result
		applied += 1

		local nextVersion = if type(data.Version) == "number" then data.Version else version + 1
		if nextVersion <= version then
			-- Une etape qui n'avance pas la version bouclerait sans fin.
			return data, applied, `la migration depuis {version} n'a pas incremente Version`
		end
		version = nextVersion
	end

	return data, applied, nil
end

return Migrations
