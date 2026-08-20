--!strict
-- Anti-rejeu : memorise les identifiants de requete deja traites, pour
-- qu'une meme demande envoyee deux fois ne s'applique qu'une seule fois.
--
-- Necessaire parce qu'un RemoteFunction peut etre invoque en boucle par un
-- client modifie, ou simplement deux fois par un double-clic. Sans ca, un
-- "jeter 1 batterie" rejoue dix fois en jette dix.

local RequestGuard = {}

export type Guard = {
	seen: { [number]: boolean },
	order: { number },
	limit: number,
}

function RequestGuard.new(limit: number?): Guard
	return {
		seen = {},
		order = {},
		limit = limit or 64,
	}
end

-- Retourne true si la requete est nouvelle (et la memorise), false si elle
-- a deja ete vue ou si l'identifiant est inexploitable.
function RequestGuard.accept(guard: Guard, requestId: number): boolean
	if type(requestId) ~= "number" or requestId ~= requestId then
		return false
	end
	if guard.seen[requestId] then
		return false
	end

	guard.seen[requestId] = true
	table.insert(guard.order, requestId)

	-- Fenetre glissante. Sans purge, un client envoyant des identifiants
	-- toujours croissants ferait grossir la table sans fin — une fuite
	-- memoire declenchable a distance.
	if #guard.order > guard.limit then
		local oldest = table.remove(guard.order, 1)
		if oldest then
			guard.seen[oldest] = nil
		end
	end

	return true
end

return RequestGuard
