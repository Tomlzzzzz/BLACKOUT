--!strict
-- Application des effets d'achat.
--
-- Le catalogue (Shared/Config/MonetizationConfig) dit CE QUI est vendu.
-- Ce module dit COMMENT l'accorder. Ajouter un produit ne demande de
-- toucher a ce fichier que s'il introduit un `type` d'effet inedit.
--
-- GARDE-FOUS ANTI PAY-TO-WIN
-- Ils sont appliques ici, a l'execution, pas seulement ecrits dans un
-- commentaire. Un produit qui tenterait de deposer un objet ou de modifier
-- une statistique de combat est refuse au moment de l'octroi, et l'echec
-- remonte. C'est deliberé : une regle qu'on ne peut pas enfreindre par
-- distraction vaut mieux qu'une regle qu'on se rappelle d'appliquer.
--
-- Toutes les fonctions operent sur un profil brut, sans Player ni Instance,
-- pour rester testables.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)

type PlayerProfile = Types.PlayerProfile

local Grants = {}

export type GrantResult = {
	ok: boolean,
	error: string?,
	summary: string?,
}

local function fail(reason: string): GrantResult
	return { ok = false, error = reason }
end

local function succeed(summary: string): GrantResult
	return { ok = true, summary = summary }
end

-- Types d'effets interdits par les regles. Refuses avant toute execution :
-- on ne veut pas d'un octroi partiel qu'il faudrait ensuite defaire.
local function checkRules(grant: any): (boolean, string?)
	local rules = Config.Monetization.rules

	if grant.type == "items" and not rules.allowItemGrants then
		return false, "octroi d'objets interdit par les regles (pay-to-win)"
	end
	if grant.type == "stat" and not rules.allowStatBoosts then
		return false, "modification de statistique interdite par les regles (pay-to-win)"
	end
	if grant.inRaid == true and not rules.allowInRaidEffects then
		return false, "effet en raid interdit par les regles (pay-to-win)"
	end

	if grant.type == "boost" then
		if grant.boostId == "credits" and (grant.multiplier or 1) > rules.maxCreditMultiplier then
			return false, `multiplicateur {grant.multiplier} au-dela du plafond {rules.maxCreditMultiplier}`
		end
		if (grant.duration or 0) > rules.maxBoostDuration then
			return false, `duree {grant.duration}s au-dela du plafond {rules.maxBoostDuration}s`
		end
	end

	return true, nil
end

-- --------------------------------------------------------- Applicateurs ---

local handlers: { [string]: (PlayerProfile, any, number) -> GrantResult } = {}

handlers.currency = function(profile, grant, now)
	if grant.currency ~= "BlackTokens" then
		return fail(`monnaie inconnue : {tostring(grant.currency)}`)
	end

	local amount = tonumber(grant.amount) or 0
	if amount <= 0 or amount % 1 ~= 0 then
		return fail("montant de monnaie invalide")
	end

	profile.BlackTokens = (profile.BlackTokens or 0) + amount
	return succeed(`+{amount} Black Tokens (total {profile.BlackTokens})`)
end

handlers.boost = function(profile, grant, now)
	local boostId = tostring(grant.boostId)
	local duration = tonumber(grant.duration) or 0
	if duration <= 0 then
		return fail("duree de bonus invalide")
	end

	profile.Boosts = profile.Boosts or {}

	-- Un second achat prolonge, il ne remplace pas : le joueur a paye deux
	-- fois, il doit obtenir deux fois la duree.
	local current = tonumber(profile.Boosts[boostId]) or 0
	local base = math.max(current, now)
	profile.Boosts[boostId] = base + duration

	return succeed(`bonus {boostId} jusqu'a {profile.Boosts[boostId]}`)
end

handlers.cosmetics = function(profile, grant, now)
	local ids = grant.cosmeticIds
	if type(ids) ~= "table" or #ids == 0 then
		return fail("aucun cosmetique a accorder")
	end

	profile.Cosmetics = profile.Cosmetics or { Owned = {}, Equipped = {} }
	profile.Cosmetics.Owned = profile.Cosmetics.Owned or {}

	local added = 0
	for _, id in ids do
		if type(id) == "string" and not profile.Cosmetics.Owned[id] then
			profile.Cosmetics.Owned[id] = true
			added += 1
		end
	end

	-- Racheter un lot deja possede n'est pas une erreur : le recu doit etre
	-- honore, sinon Roblox le rejouera indefiniment.
	return succeed(`{added} cosmetique(s) ajoute(s) sur {#ids}`)
end

handlers.stashCapacity = function(profile, grant, now)
	local bonus = tonumber(grant.bonus) or 0
	if bonus <= 0 then
		return fail("bonus de capacite invalide")
	end

	profile.BaseUpgrades = profile.BaseUpgrades or {}
	-- Idempotent : c'est un gamepass, verifie a chaque connexion. On pose
	-- la valeur, on ne l'accumule pas.
	profile.BaseUpgrades.StashCapacity = bonus

	return succeed(`capacite de coffre +{bonus}`)
end

-- ------------------------------------------------------------------ API ---

function Grants.apply(profile: PlayerProfile, grant: any, now: number): GrantResult
	if type(grant) ~= "table" or type(grant.type) ~= "string" then
		return fail("effet mal forme")
	end

	local allowed, reason = checkRules(grant)
	if not allowed then
		return fail(reason :: string)
	end

	local handler = handlers[grant.type]
	if not handler then
		return fail(`type d'effet inconnu : {grant.type}`)
	end

	local ok, result = pcall(handler, profile, grant, now)
	if not ok then
		return fail(`l'octroi a leve : {tostring(result)}`)
	end
	return result
end

-- Multiplicateur de credits actif, ou 1. Lu par EconomyService.
function Grants.creditMultiplier(profile: PlayerProfile, now: number): number
	local boosts = profile.Boosts
	if type(boosts) ~= "table" then
		return 1
	end

	local expiry = tonumber(boosts.credits) or 0
	if expiry <= now then
		return 1
	end

	-- Le plafond est reapplique a la lecture : un profil trafique ou une
	-- config modifiee apres coup ne doit pas pouvoir depasser la regle.
	local product = Config.Monetization.developerProducts.CreditBoost
	local multiplier = if product then product.grant.multiplier else 1
	return math.min(multiplier, Config.Monetization.rules.maxCreditMultiplier)
end

function Grants.hasCosmetic(profile: PlayerProfile, cosmeticId: string): boolean
	local cosmetics = profile.Cosmetics
	return type(cosmetics) == "table"
		and type(cosmetics.Owned) == "table"
		and cosmetics.Owned[cosmeticId] == true
end

-- Enregistre un identifiant d'achat honore, en bornant l'historique.
function Grants.rememberPurchase(profile: PlayerProfile, purchaseId: string)
	local purchases = (profile :: any).Purchases
	if type(purchases) ~= "table" then
		purchases = { seen = {}, order = {} }
		;(profile :: any).Purchases = purchases
	end
	purchases.seen = purchases.seen or {}
	purchases.order = purchases.order or {}

	if purchases.seen[purchaseId] then
		return
	end

	purchases.seen[purchaseId] = true
	table.insert(purchases.order, purchaseId)

	local limit = Config.Monetization.purchaseHistoryLimit
	while #purchases.order > limit do
		local oldest = table.remove(purchases.order, 1)
		if oldest then
			purchases.seen[oldest] = nil
		end
	end
end

function Grants.wasPurchased(profile: PlayerProfile, purchaseId: string): boolean
	local purchases = (profile :: any).Purchases
	return type(purchases) == "table"
		and type(purchases.seen) == "table"
		and purchases.seen[purchaseId] == true
end

return Grants
