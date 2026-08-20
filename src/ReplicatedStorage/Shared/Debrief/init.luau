--!strict
-- Assemblage du rapport de fin de raid.
--
-- Module PUR : il ne connait ni joueur, ni service, ni remote. On lui donne
-- ce qui s'est passe, il rend le rapport. Deux benefices, et le second est
-- le vrai :
--
--   1. il se teste sans partie ;
--   2. les TROIS issues produisent exactement la meme structure.
--
-- Le point 2 evite l'erreur classique : un bel ecran de victoire, et un
-- « VOUS ETES MORT » bricole a cote. Mort, extrait ou lache par la fenetre
-- de contrat, le joueur lit le meme document — seules les valeurs et la
-- couleur changent. C'est aussi ce que raconte le jeu : le commanditaire
-- remplit le meme formulaire dans les trois cas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemDatabase = require(Shared.ItemDatabase)
local Types = require(Shared.Types)

type ItemStack = Types.ItemStack
type Contract = Types.Contract
type ReportLine = Types.ReportLine
type RaidReport = Types.RaidReport
type RaidOutcome = Types.RaidOutcome

local Debrief = {}

-- ------------------------------------------------------------ Manifeste --

-- Resout des piles brutes en lignes chiffrees, triees par valeur
-- decroissante.
--
-- Le tri n'est pas cosmetique : le manifeste est tronque, et ce qui est
-- coupe doit etre ce qui compte le moins. Un joueur qui ramene un noyau
-- prototype et onze bandages doit voir le noyau en premiere ligne.
--
-- Departage par identifiant a valeur egale, sinon l'ordre depend de
-- l'implementation du tri et deux rapports identiques s'affichent
-- differemment.
function Debrief.lines(stacks: { ItemStack }): { ReportLine }
	local lines: { ReportLine } = {}

	for _, stack in stacks do
		local quantity = math.max(0, math.floor(stack.quantity or 0))
		if quantity > 0 then
			local definition = ItemDatabase.get(stack.id)
			local unit = if definition then definition.value else 0
			table.insert(lines, {
				id = stack.id,
				quantity = quantity,
				unitValue = unit,
				value = unit * quantity,
				rarity = if definition then definition.rarity else "Common",
			})
		end
	end

	table.sort(lines, function(a, b)
		if a.value == b.value then
			return a.id < b.id
		end
		return a.value > b.value
	end)

	return lines
end

function Debrief.total(lines: { ReportLine }): number
	local total = 0
	for _, line in lines do
		total += line.value
	end
	return total
end

-- ------------------------------------------------------------- Notation --

-- La note du commanditaire.
--
-- Elle porte sur la VALEUR RAPATRIEE, jamais sur la performance. Survivre
-- sans rien ramener reste deficitaire ; mourir efface le bareme.
function Debrief.rate(outcome: RaidOutcome, value: number, contractComplete: boolean): string
	if outcome ~= "EXTRACTED" then
		return Config.Debrief.lostRating
	end

	local tiers = Config.Debrief.rating
	local index = #tiers
	for i, tier in tiers do
		if value >= tier.minValue then
			index = i
			break
		end
	end

	if contractComplete then
		index = math.max(1, index - Config.Debrief.contractPromotion)
	end

	return tiers[index].key
end

-- ------------------------------------------------------------ Reference --

-- Numero de dossier, stable pour un meme actif et une meme sortie.
--
-- Deterministe a dessein : un rapport reaffiche doit porter le meme numero,
-- sinon il cesse d'etre un document et redevient un habillage.
function Debrief.reference(userId: number, raids: number): string
	local asset = math.floor(math.abs(userId)) % 10000
	local run = math.floor(math.abs(raids)) % 10000
	return string.format("%s-%04d-%04d", Config.Debrief.referencePrefix, asset, run)
end

-- -------------------------------------------------------------- Rapport --

export type BuildInput = {
	outcome: RaidOutcome,
	userId: number,
	raids: number,
	duration: number,

	-- Ce qui a change de mains. En reussite : ce qui est entre au coffre.
	-- En echec : ce qui est perdu. Meme champ, parce que c'est la meme
	-- colonne a l'ecran.
	manifest: { ItemStack },
	-- Piles restees dans le sac faute de place au coffre. Une perte reelle,
	-- et la seule que le joueur peut eviter en gerant son coffre.
	leftBehind: { ItemStack }?,

	bonus: number?,
	credits: number?,
	xpGained: number?,
	level: number?,
	leveledUp: boolean?,
	balance: number?,

	zone: string?,
	kills: number?,
	damageTaken: number?,
	peakThreat: number?,
	contract: Contract?,
}

local function count(value: number?): number
	return math.max(0, math.floor(value or 0))
end

function Debrief.build(input: BuildInput): RaidReport
	local all = Debrief.lines(input.manifest)
	local manifestValue = Debrief.total(all)

	-- Troncature. Ce qui deborde n'est pas jete mais agrege : sans cela le
	-- total affiche ne correspondrait plus a la somme des lignes visibles,
	-- et le joueur croirait a une erreur de comptage.
	local limit = Config.Debrief.manifestLimit
	local shown: { ReportLine } = {}
	local overflowCount, overflowValue = 0, 0

	for index, line in all do
		if index <= limit then
			table.insert(shown, line)
		else
			-- Une ligne de plus, pas une unite de plus : « ET 4 AUTRES »
			-- repond a « combien de postes je ne vois pas », qui est la
			-- question posee. Compter les unites donnait « ET 74 AUTRES »
			-- pour quatre lignes, dont soixante cartouches.
			overflowCount += 1
			overflowValue += line.value
		end
	end

	local contract = input.contract
	local objectivesTotal = 0
	local objectivesDone = 0
	if contract then
		objectivesTotal = #contract.objectives
		for _, objective in contract.objectives do
			if objective.done then
				objectivesDone += 1
			end
		end
	end

	local contractComplete = contract ~= nil and contract.complete == true
	local extracted = input.outcome == "EXTRACTED"

	return {
		outcome = input.outcome,
		reference = Debrief.reference(input.userId, input.raids),
		zone = input.zone,
		duration = count(input.duration),
		rating = Debrief.rate(input.outcome, manifestValue, contractComplete),

		manifest = shown,
		overflowCount = overflowCount,
		overflowValue = overflowValue,
		manifestValue = manifestValue,
		leftBehind = if input.leftBehind then #input.leftBehind else 0,

		-- Rien n'est verse quand rien n'est rentre. On le pose ICI plutot
		-- que de faire confiance a l'appelant : un rapport de mort qui
		-- afficherait une prime serait un mensonge de l'interface.
		bonus = if extracted then count(input.bonus) else 0,
		credits = if extracted then count(input.credits) else 0,
		xpGained = if extracted then count(input.xpGained) else 0,
		level = count(input.level),
		leveledUp = extracted and input.leveledUp == true,
		balance = count(input.balance),

		kills = count(input.kills),
		damageTaken = count(input.damageTaken),
		peakThreat = count(input.peakThreat),

		objectivesDone = objectivesDone,
		objectivesTotal = objectivesTotal,
		contractKey = if contract then contract.titleKey else nil,
		contractComplete = contractComplete,
	}
end

return Debrief
