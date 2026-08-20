--!strict
-- Tirage pondere. Utilise par LootService pour les tables de butin.

local WeightedRandom = {}

-- entries : liste d'objets portant un champ `weight` > 0.
-- Retourne nil si la liste est vide ou si tous les poids sont nuls.
function WeightedRandom.pick<T>(entries: { T & { weight: number } }, rng: Random?): (T & { weight: number })?
	local total = 0
	for _, entry in entries do
		if entry.weight > 0 then
			total += entry.weight
		end
	end

	if total <= 0 then
		return nil
	end

	local roll = if rng then rng:NextNumber(0, total) else math.random() * total
	local cursor = 0

	for _, entry in entries do
		if entry.weight <= 0 then
			continue
		end
		cursor += entry.weight
		if roll <= cursor then
			return entry
		end
	end

	-- Atteignable seulement par erreur d'arrondi flottant sur le dernier
	-- element : on rend le dernier candidat valide.
	for index = #entries, 1, -1 do
		if entries[index].weight > 0 then
			return entries[index]
		end
	end

	return nil
end

return WeightedRandom
