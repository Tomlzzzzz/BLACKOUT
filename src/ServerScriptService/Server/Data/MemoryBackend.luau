--!strict
-- Backend en memoire, compatible avec l'interface attendue par Store.
--
-- Deux usages :
--   - les tests, qui ont besoin de provoquer des pannes a volonte
--   - le repli quand les DataStore sont indisponibles (Studio sans acces
--     aux services API), pour que le jeu reste jouable sans persister
--
-- Les valeurs sont copiees en profondeur a l'entree comme a la sortie. Un
-- vrai DataStore serialise : rendre la meme table qu'on a stockee ferait
-- passer des bugs d'aliasing inapercus en test, pour les decouvrir en
-- production.

local MemoryBackend = {}

export type Backend = {
	data: { [string]: any },
	calls: number,
	failNext: number,
	failAlways: boolean,
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

function MemoryBackend.new(): Backend
	local backend = {
		data = {},
		calls = 0,
		failNext = 0,
		failAlways = false,
	}

	function backend:UpdateAsync(key: string, transform: (any) -> any): any
		self.calls += 1

		if self.failAlways or self.failNext > 0 then
			if self.failNext > 0 then
				self.failNext -= 1
			end
			error(`panne simulee du DataStore (appel {self.calls})`, 0)
		end

		local current = deepCopy(self.data[key])
		local updated = transform(current)

		-- nil annule l'ecriture, comme un vrai UpdateAsync.
		if updated == nil then
			return current
		end

		self.data[key] = deepCopy(updated)
		return deepCopy(updated)
	end

	return backend :: any
end

return MemoryBackend
