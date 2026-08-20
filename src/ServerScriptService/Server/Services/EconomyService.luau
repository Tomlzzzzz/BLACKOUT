--!strict
-- Credits, XP et niveaux.
--
-- Toute mutation de credits passe ici, jamais en direct dans un autre
-- service : c'est la seule facon de garder une trace unique de ce qui cree
-- et de ce qui detruit de la monnaie le jour ou l'economie derivera.
--
-- Les valeurs viennent de Config.Economy. Aucun nombre en dur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Logger = require(Shared.Utils.Logger)

type ServiceContext = Types.ServiceContext
type ExtractionReward = Types.ExtractionReward

local EconomyService = {}

EconomyService.Name = "EconomyService"
EconomyService.Priority = 40

local log = Logger.new("EconomyService")
local ctx: ServiceContext?

local function getProfile(player: Player)
	local context = ctx
	local dataService = context and context.Get("DataService")
	if not dataService then
		return nil
	end
	return (dataService :: any).GetProfile(player)
end

local function notify(player: Player, credits: number)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("CreditsChanged")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, credits)
	end
end

function EconomyService.GetCredits(player: Player): number
	local profile = getProfile(player)
	return if profile then profile.Credits else 0
end

function EconomyService.AddCredits(player: Player, amount: number): boolean
	if type(amount) ~= "number" or amount ~= amount or amount % 1 ~= 0 then
		log:warn(`montant de credits invalide pour {player.Name} : {tostring(amount)}`)
		return false
	end

	local profile = getProfile(player)
	if not profile then
		return false
	end

	-- Un solde negatif n'a pas de sens et masquerait un bug de depense
	-- derriere un affichage bizarre plutot que de le signaler.
	profile.Credits = math.max(0, profile.Credits + amount)

	if amount > 0 then
		profile.Statistics.CreditsEarned += amount
	end

	notify(player, profile.Credits)
	return true
end

-- Applique la courbe d'XP jusqu'a stabilisation : un gros gain peut faire
-- passer plusieurs niveaux d'un coup.
function EconomyService.AddXp(player: Player, amount: number): (number, boolean)
	local profile = getProfile(player)
	if not profile or type(amount) ~= "number" or amount <= 0 then
		return if profile then profile.level else 1, false
	end

	profile.XP += math.floor(amount)

	local startLevel = profile.Level
	while profile.XP >= Config.Economy.xpCurve(profile.Level) do
		profile.XP -= Config.Economy.xpCurve(profile.Level)
		profile.Level += 1
	end

	return profile.Level, profile.Level > startLevel
end

-- Recompense d'extraction : la valeur du butin rapatrie, plus la prime de
-- sortie. C'est le seul robinet qui cree de la monnaie pour l'instant.
function EconomyService.GrantExtractionReward(player: Player, lootValue: number): ExtractionReward
	local bonus = Config.Economy.extractionBonus
	local base = math.floor(math.max(0, lootValue)) + bonus

	-- Multiplicateur du produit Credit Boost, s'il est actif. Le plafond
	-- est applique en amont par Grants ; on ne le refait pas ici, mais on
	-- refuse toute valeur aberrante plutot que de la propager.
	local context = ctx
	local monetization = context and context.Get("MonetizationService")
	local multiplier = if monetization then (monetization :: any).GetCreditMultiplier(player) else 1
	if type(multiplier) ~= "number" or multiplier ~= multiplier or multiplier < 1 then
		multiplier = 1
	end

	local credits = math.floor(base * multiplier)

	EconomyService.AddCredits(player, credits)
	local level, leveledUp = EconomyService.AddXp(player, Config.Economy.xpPerExtraction)

	local profile = getProfile(player)
	if profile then
		profile.Statistics.Extractions += 1
	end

	log:info(
		`{player.Name} extrait : {math.floor(lootValue)} de butin + {bonus} de prime`
			.. `{if multiplier > 1 then ` x{multiplier}` else ""}`
			.. ` = {credits} credits (solde {if profile then profile.Credits else 0})`
	)

	return {
		lootValue = math.floor(math.max(0, lootValue)),
		bonus = bonus,
		credits = credits,
		xpGained = Config.Economy.xpPerExtraction,
		level = level,
		leveledUp = leveledUp,
	}
end

function EconomyService.Init(context: ServiceContext)
	ctx = context
end

function EconomyService.Start()
	log:info(`pret — prime d'extraction {Config.Economy.extractionBonus}`)
end

function EconomyService.Stop()
end

return EconomyService
