--!strict
local EconomyConfig = {
	startingCredits = 2500,

	-- Le vendeur rachete sous le prix de base : c'est le puits qui absorbe
	-- l'inflation du loot. A surveiller en premier si l'economie derive.
	vendorBuybackRate = 0.45,
	vendorSellMarkup = 1.25,

	insuranceRate = 0.15,
	insuranceReturnChance = 0.60,

	extractionBonus = 250,
	deathPenalty = 0,

	xpPerExtraction = 400,
	xpPerKill = 75,
	xpCurve = function(level: number): number
		return math.floor(500 * (level ^ 1.45))
	end,
}

return EconomyConfig
