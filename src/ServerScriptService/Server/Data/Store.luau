--!strict
-- Magasin de profils : reprise sur erreur, verrou de session, migration.
--
-- Le backend est INJECTE. En production c'est un DataStore Roblox ; dans
-- les tests c'est une fausse implementation programmable qui echoue a la
-- demande. Sans cette inversion, ni la reprise sur erreur ni le verrou ne
-- seraient testables autrement qu'en priant.
--
-- Le backend doit exposer :
--   UpdateAsync(key, transform) -> value
-- ou `transform(old)` rend la nouvelle valeur, ou nil pour annuler l'ecriture.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Schema = require(script.Parent.Schema)
local Migrations = require(script.Parent.Migrations)

local Store = {}

export type Backend = {
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
}

export type Store = {
	backend: Backend,
	jobId: string,
	sleep: (seconds: number) -> (),
	clock: () -> number,
	locked: { [string]: boolean },
	stats: {
		loads: number,
		saves: number,
		retries: number,
		migrations: number,
		conflicts: number,
	},
}

export type LoadResult = {
	ok: boolean,
	profile: any?,
	error: string?,
	migrated: number,
	attempts: number,
}

-- `sleep` et `clock` sont injectables pour que les tests ne passent pas
-- trente secondes a attendre des delais de reprise.
function Store.new(backend: Backend, jobId: string?, sleep: ((number) -> ())?, clock: (() -> number)?): Store
	return {
		backend = backend,
		jobId = jobId or "job-inconnu",
		sleep = sleep or task.wait,
		clock = clock or os.time,
		locked = {},
		stats = { loads = 0, saves = 0, retries = 0, migrations = 0, conflicts = 0 },
	}
end

local function delayFor(attempt: number): number
	local retry = Config.Data.retry
	return math.min(retry.baseDelay * (retry.factor ^ (attempt - 1)), retry.maxDelay)
end

-- Enveloppe toute operation DataStore : pcall, reprise avec attente
-- croissante, et abandon propre apres N tentatives.
local function withRetry<T>(store: Store, label: string, operation: () -> T): (boolean, T | string, number)
	local retry = Config.Data.retry
	local lastError: string = "inconnu"

	for attempt = 1, retry.attempts do
		local ok, result = pcall(operation)
		if ok then
			return true, result, attempt
		end

		lastError = tostring(result)
		store.stats.retries += 1

		if attempt < retry.attempts then
			store.sleep(delayFor(attempt))
		end
	end

	return false, `{label} a echoue apres {retry.attempts} tentatives : {lastError}`, retry.attempts
end

local function isLockHeldByOther(store: Store, session: any): boolean
	if type(session) ~= "table" or type(session.jobId) ~= "string" then
		return false
	end
	if session.jobId == store.jobId then
		return false
	end
	-- Un verrou plus vieux que sa duree de vie appartient a un serveur
	-- disparu sans relacher : on le reprend, sinon le joueur resterait
	-- enferme dehors jusqu'a expiration manuelle.
	return (store.clock() - (tonumber(session.at) or 0)) < Config.Data.session.ttl
end

-- Charge un profil et prend le verrou de session dans la meme operation
-- atomique. Un UpdateAsync qui rend nil annule l'ecriture : c'est ainsi
-- qu'on refuse de voler un verrou vivant.
function Store.load(store: Store, key: string): LoadResult
	local session = Config.Data.session
    local totalAttempts = 0

	for acquire = 1, session.acquireAttempts do
		local conflicted = false

		local ok, result, attempts = withRetry(store, "chargement", function()
			return store.backend:UpdateAsync(key, function(old)
				local envelope = if type(old) == "table" then old else {}

				if isLockHeldByOther(store, envelope.session) then
					conflicted = true
					return nil
				end

				envelope.profile = if type(envelope.profile) == "table" then envelope.profile else Schema.defaults()
				envelope.session = { jobId = store.jobId, at = store.clock() }
				return envelope
			end)
		end)

		totalAttempts += attempts

		if not ok then
			return { ok = false, profile = nil, error = result :: string, migrated = 0, attempts = totalAttempts }
		end

		if conflicted then
			store.stats.conflicts += 1
			if acquire < session.acquireAttempts then
				store.sleep(session.acquireDelay)
			end
			continue
		end

		local envelope = result :: any
		local raw = envelope.profile

		local migrated, applied, migrationError = Migrations.migrate(raw, Schema.CURRENT_VERSION)
		if migrationError then
			-- On journalise mais on continue : la reconciliation qui suit
			-- comblera ce que la migration n'a pas su faire.
			warn(`[Store] migration partielle pour {key} : {migrationError}`)
		end
		store.stats.migrations += applied

		local profile = Schema.reconcile(migrated)

		store.locked[key] = true
		store.stats.loads += 1

		return { ok = true, profile = profile, error = migrationError, migrated = applied, attempts = totalAttempts }
	end

	return {
		ok = false,
		profile = nil,
		error = "profil verrouille par une autre session",
		migrated = 0,
		attempts = totalAttempts,
	}
end

-- Ecrit le profil. `release` relache le verrou dans la meme operation, pour
-- que la sortie du joueur soit atomique : sauvegarde et deverrouillage ne
-- peuvent pas diverger.
function Store.save(store: Store, key: string, profile: any, release: boolean?): (boolean, string?)
	local writable, reason = Schema.isWritable(profile)
	if not writable then
		return false, `ecriture refusee : {reason}`
	end

	local stolen = false

	local ok, result = withRetry(store, "sauvegarde", function()
		return store.backend:UpdateAsync(key, function(old)
			local envelope = if type(old) == "table" then old else {}

			-- Le verrou a change de main pendant la session : un autre
			-- serveur a repris le joueur. Ecrire maintenant ecraserait sa
			-- progression avec notre etat perime.
			if isLockHeldByOther(store, envelope.session) then
				stolen = true
				return nil
			end

			envelope.profile = profile
			envelope.session = if release then nil else { jobId = store.jobId, at = store.clock() }
			return envelope
		end)
	end)

	if stolen then
		return false, "verrou repris par une autre session, ecriture abandonnee"
	end
	if not ok then
		return false, result :: string
	end

	if release then
		store.locked[key] = nil
	end
	store.stats.saves += 1
	return true, nil
end

-- Rafraichit l'horodatage du verrou sans toucher au profil, pour qu'une
-- session longue ne se fasse pas voler sa place.
function Store.refreshLock(store: Store, key: string): boolean
	local ok = withRetry(store, "rafraichissement", function()
		return store.backend:UpdateAsync(key, function(old)
			local envelope = if type(old) == "table" then old else {}
			if isLockHeldByOther(store, envelope.session) then
				return nil
			end
			envelope.session = { jobId = store.jobId, at = store.clock() }
			return envelope
		end)
	end)
	return ok
end

function Store.keyFor(userId: number): string
	return `{Config.Data.keyPrefix}{userId}`
end

return Store
