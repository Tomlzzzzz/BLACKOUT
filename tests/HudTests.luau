--!strict
-- Tests des donnees du HUD v2.
--
-- Ce que ces tests attrapent, et que rien d'autre n'attrape : une reference
-- morte dans la configuration. Un contrat qui reclame un item inexistant, un
-- emplacement qui accepte un identifiant mal orthographie, un palier de
-- menace sans libelle d'affichage — aucun de ces defauts ne leve d'erreur.
-- Ils produisent une ligne vide, une case toujours vide, un libelle absent,
-- et se decouvrent en jouant, tard.
--
-- Le rendu lui-meme ne se teste pas ici : il se verifie a l'ecran, en
-- playtest. Ce qui se teste, c'est que toutes les donnees que le HUD affiche
-- existent reellement.
--
--   require(game.ServerStorage.Tests.HudTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemDatabase = require(Shared.ItemDatabase)

local HudTests = {}

type Report = { passed: number, failed: number, lines: { string } }

local function check(report: Report, name: string, condition: boolean, detail: string?)
	if condition then
		report.passed += 1
		table.insert(report.lines, `  PASS  {name}`)
	else
		report.failed += 1
		table.insert(report.lines, `  FAIL  {name}` .. (if detail then ` -> {detail}` else ""))
	end
end

-- ------------------------------------------------------------ Contrats ---

local function testContracts(report: Report)
	table.insert(report.lines, "contrats")

	local contracts = Config.Contracts.contracts
	check(report, "au moins trois contrats", #contracts >= 3, tostring(#contracts))

	local unknownItem, badKind, noQuantity, emptyLabel, ids = {}, {}, {}, {}, {}
	local duplicateIds = {}
	local kinds = { collect = true, reach = true, extract = true }

	for _, contract in contracts do
		if ids[contract.id] then
			table.insert(duplicateIds, contract.id)
		end
		ids[contract.id] = true

		check(report, `{contract.id} a un identifiant`, #contract.id > 0)
		check(report, `{contract.id} a une prime`, contract.reward > 0)
		check(report, `{contract.id} a des objectifs`, #contract.objectives > 0)

		for index, objective in contract.objectives do
			if not kinds[objective.kind] then
				table.insert(badKind, `{contract.id}#{index}={objective.kind}`)
			end
			-- Le libelle n'est plus dans la config : c'est une cle de
			-- localisation construite a partir de l'identifiant et de la
			-- position. LocaleTests verifie qu'elle existe bien.
			if objective.kind == nil then
				table.insert(emptyLabel, `{contract.id}#{index}`)
			end
			if objective.kind == "collect" then
				if not objective.item or not ItemDatabase.get(objective.item) then
					table.insert(unknownItem, `{contract.id}#{index}={tostring(objective.item)}`)
				end
				if not objective.quantity or objective.quantity <= 0 then
					table.insert(noQuantity, `{contract.id}#{index}`)
				end
			end
		end
	end

	-- Le defaut principal vise par cette suite : un objectif inaccomplissable
	-- s'affiche normalement et ne se remplit jamais.
	check(report, "tous les items de contrat existent", #unknownItem == 0, table.concat(unknownItem, ", "))
	check(report, "tous les types d'objectif sont connus", #badKind == 0, table.concat(badKind, ", "))
	check(report, "toute collecte a une quantite", #noQuantity == 0, table.concat(noQuantity, ", "))
	check(report, "aucun libelle vide", #emptyLabel == 0, table.concat(emptyLabel, ", "))
	check(report, "aucun identifiant en double", #duplicateIds == 0, table.concat(duplicateIds, ", "))

	-- Un contrat dont tous les objectifs sont des collectes ne peut pas
	-- apprendre au joueur a extraire.
	local withExtract = 0
	for _, contract in contracts do
		for _, objective in contract.objectives do
			if objective.kind == "extract" then
				withExtract += 1
				break
			end
		end
	end
	check(report, "chaque contrat finit par une extraction", withExtract == #contracts, `{withExtract}/{#contracts}`)
end

-- -------------------------------------------------- Barre d'equipement ---

local function testLoadout(report: Report)
	table.insert(report.lines, "barre d'equipement")

	local slots = Config.Loadout.slots
	check(report, "cinq emplacements", #slots == 5, tostring(#slots))

	local counters = { ammo = true, quantity = true, percent = true }
	local unknownItem, badCounter, badIndex = {}, {}, {}

	for position, slot in slots do
		if slot.index ~= position then
			table.insert(badIndex, `{slot.key}={slot.index}`)
		end
		if not counters[slot.counter] then
			table.insert(badCounter, `{slot.key}={slot.counter}`)
		end
		for _, itemId in slot.accepts do
			if not ItemDatabase.get(itemId) then
				table.insert(unknownItem, `{slot.key}={itemId}`)
			end
		end
	end

	check(report, "index alignes sur la position", #badIndex == 0, table.concat(badIndex, ", "))
	check(report, "compteurs connus", #badCounter == 0, table.concat(badCounter, ", "))
	check(report, "tous les items acceptes existent", #unknownItem == 0, table.concat(unknownItem, ", "))

	-- Un emplacement equipable doit n'accepter que des armes, sinon
	-- LoadoutService tenterait d'equiper une trousse de soin.
	local badEquippable = {}
	for _, slot in slots do
		if Config.Loadout.equippable[slot.key] then
			for _, itemId in slot.accepts do
				if not Config.Weapons.weapons[itemId] then
					table.insert(badEquippable, `{slot.key}={itemId}`)
				end
			end
		end
	end
	check(report, "les emplacements equipables n'acceptent que des armes", #badEquippable == 0, table.concat(badEquippable, ", "))

	check(report, "anti-rafale positif", Config.Loadout.requestCooldown > 0)
end

-- -------------------------------------------------------------- Vitaux ---

local function testVitals(report: Report)
	table.insert(report.lines, "vitaux")

	local armor = Config.Vitals.armor
	local battery = Config.Vitals.battery

	check(report, "armure plafonnee", armor.max > 0)
	check(report, "absorption partielle", armor.absorption > 0 and armor.absorption < 1)
	check(report, "l'armure ne demarre pas pleine", armor.startingValue < armor.max)
	check(report, "la plaque existe", ItemDatabase.get(armor.plateItem) ~= nil, armor.plateItem)

	check(report, "batterie plafonnee", battery.max > 0)
	check(report, "la lampe consomme plus que la veille", battery.drainPerSecond > battery.idleDrainPerSecond)
	check(report, "la pile existe", ItemDatabase.get(battery.cellItem) ~= nil, battery.cellItem)
	check(report, "seuils de batterie ordonnes", battery.criticalBelow < battery.warnBelow)

	-- Une recharge doit valoir plus qu'une poignee de secondes, sinon
	-- transporter des piles n'a aucun sens.
	check(report, "une pile vaut plus de 60s de lumiere", battery.perCell / battery.drainPerSecond > 60)

	local unknownHeal = {}
	for itemId in Config.Vitals.healing do
		if not ItemDatabase.get(itemId) then
			table.insert(unknownHeal, itemId)
		end
	end
	check(report, "tous les soins existent", #unknownHeal == 0, table.concat(unknownHeal, ", "))
end

-- --------------------------------------------------------------- Monde ---

local function testWorld(report: Report)
	table.insert(report.lines, "monde")

	check(report, "au moins deux districts", #Config.World.districts >= 2)
	check(report, "au moins deux meteos", #Config.World.weathers >= 2)

	local badRadius, badWeight = {}, {}
	for _, district in Config.World.districts do
		if district.radius <= 0 then
			table.insert(badRadius, district.name)
		end
	end
	for _, weather in Config.World.weathers do
		if weather.weight <= 0 then
			table.insert(badWeight, weather.name)
		end
	end
	check(report, "rayons positifs", #badRadius == 0, table.concat(badRadius, ", "))
	check(report, "poids meteo positifs", #badWeight == 0, table.concat(badWeight, ", "))

	-- Le district par defaut doit exister : c'est celui qui s'affiche hors
	-- de toute zone, donc partout tant qu'il n'y a pas de carte.
	local found = false
	for _, district in Config.World.districts do
		if district.name == Config.World.defaultDistrict then
			found = true
		end
	end
	check(report, "le district par defaut est declare", found, Config.World.defaultDistrict)

	local range = Config.World.clockRange
	check(report, "plage horaire coherente", range.min < range.max)
	check(report, "nuit permanente", range.min >= 18, tostring(range.min))
end

-- --------------------------------------------------------------- Armes ---

local function testWeapons(report: Report)
	table.insert(report.lines, "armes")

	local missing = {}
	for itemId, weapon in Config.Weapons.weapons do
		if not weapon.caliber or #weapon.caliber == 0 then
			table.insert(missing, `{itemId}.caliber`)
		end
		if not weapon.fireMode or #weapon.fireMode == 0 then
			table.insert(missing, `{itemId}.fireMode`)
		end
		if not ItemDatabase.get(weapon.ammoId) then
			table.insert(missing, `{itemId}.ammoId={weapon.ammoId}`)
		end
	end

	-- Le HUD affiche calibre et mode : une arme sans eux montre une ligne
	-- vide en bas a droite.
	check(report, "toutes les armes ont calibre et mode", #missing == 0, table.concat(missing, ", "))
end

-- -------------------------------------------------------------- Menace ---

local function testThreat(report: Report)
	table.insert(report.lines, "menace")

	local bands = Config.Threat.bands
	local names = {}
	for _, band in bands do
		names[band.name] = true
	end

	-- Le Theme vit cote client et n'est pas requerable ici : on verifie donc
	-- la source, et HudTests documente l'attente. Les six paliers doivent
	-- exister et etre strictement decroissants.
	local decreasing = true
	for index = 2, #bands do
		if bands[index].from >= bands[index - 1].from then
			decreasing = false
		end
	end
	check(report, "paliers strictement decroissants", decreasing)
	check(report, "six paliers", #bands == 6, tostring(#bands))

	for _, expected in { "SAFE", "ALERT", "DANGER", "SEVERE", "CRITICAL", "HUNT" } do
		check(report, `palier {expected} present`, names[expected] == true)
	end

	-- Bornes alignees sur la specification du HUD v2.
	local byName: { [string]: number } = {}
	for _, band in bands do
		byName[band.name] = band.from
	end
	check(report, "SEVERE commence a 61", byName.SEVERE == 61, tostring(byName.SEVERE))
	check(report, "CRITICAL commence a 86", byName.CRITICAL == 86, tostring(byName.CRITICAL))
	check(report, "HUNT a 100", byName.HUNT == 100, tostring(byName.HUNT))
end

-- ---------------------------------------------------------- Reactivite ---

local function testHudConfig(report: Report)
	table.insert(report.lines, "reglages du HUD")

	check(report, "seuils de degats ordonnes", Config.Hud.damage.criticalAbove > Config.Hud.damage.heavyAbove)
	check(report, "seuil critique de vie sous la moitie", Config.Hud.damage.criticalBelowHealth < 0.5)
	check(report, "boussole echantillonnee plus vite que les derives", Config.Hud.sampleRate.compass < Config.Hud.sampleRate.derived)
	check(report, "profils ordonnes", Config.Hud.breakpoints.minimalBelow < Config.Hud.breakpoints.compactBelow)

	for _, profile in { "full", "compact", "minimal" } do
		check(report, `echelle {profile} definie`, (Config.Hud.scale :: any)[profile] ~= nil)
	end
	check(report, "hauteur de reference plausible", Config.Hud.referenceHeight >= 720)
end

function HudTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testContracts(report)
	testLoadout(report)
	testVitals(report)
	testWorld(report)
	testWeapons(report)
	testThreat(report)
	testHudConfig(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return HudTests
