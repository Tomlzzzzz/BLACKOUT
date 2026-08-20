--!strict
-- Tests du coeur de tir.
--
-- Portent sur Shared.Weapons, pur. Le temps etant un argument, une rafale
-- de trente balles, un rechargement interrompu ou un client qui tire mille
-- fois par seconde se simulent en quelques appels.
--
-- Ce que ces tests NE couvrent pas : le raycast, la dispersion et la
-- validation d'origine, qui vivent dans CombatService parce qu'ils ont
-- besoin du monde. Ils se verifient en playtest.
--
--   require(game.ServerStorage.Tests.WeaponTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Weapons)
local Config = require(Shared.Config)
local ItemDatabase = require(Shared.ItemDatabase)

local WeaponTests = {}

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

-- ---------------------------------------------------------- Catalogue ----

local function testCatalogue(report: Report)
	table.insert(report.lines, "catalogue")

	local count = 0
	for itemId, weapon in Config.Weapons.weapons do
		count += 1

		-- Une arme doit exister comme item : c'est l'emplacement equipe de
		-- l'inventaire qui la designe.
		check(report, `{itemId} existe dans ItemDatabase`, ItemDatabase.has(itemId))

		-- Ses munitions aussi, sinon recharger est impossible.
		check(report, `munition {weapon.ammoId} connue`, ItemDatabase.has(weapon.ammoId), weapon.ammoId)

		check(report, `{itemId} : cadence positive`, weapon.fireRate > 0)
		check(report, `{itemId} : chargeur non vide`, weapon.magazine > 0)
		check(report, `{itemId} : degats positifs`, weapon.damage > 0)
		check(report, `{itemId} : portee positive`, weapon.range > 0)
	end

	check(report, "au moins une arme", count > 0)
	check(report, "arme par defaut valide", Weapons.isWeapon(Config.Weapons.defaultWeapon))

	check(report, "un item ordinaire n'est pas une arme", not Weapons.isWeapon("bandage"))
	check(report, "un item inexistant n'est pas une arme", not Weapons.isWeapon("nope"))
	check(report, "new() refuse un non-arme", Weapons.new("bandage", 0) == nil)
end

-- --------------------------------------------------------- Cadence ------

local function testFireRate(report: Report)
	table.insert(report.lines, "cadence")

	local state = Weapons.new("rifle_ak", 0) :: any
	local definition = Weapons.definition("rifle_ak")

	check(report, "chargeur plein au depart", state.ammoInMagazine == definition.magazine)

	local first = Weapons.fire(state, 10)
	check(report, "premier tir accepte", first.ok, tostring(first.error))
	check(report, "une munition consommee", state.ammoInMagazine == definition.magazine - 1)

	-- Immediatement apres : trop rapide.
	local tooFast = Weapons.fire(state, 10 + definition.fireRate / 2)
	check(report, "tir trop rapide refuse", not tooFast.ok and tooFast.error == "TOO_FAST", tostring(tooFast.error))
	check(report, "refus sans consommation", state.ammoInMagazine == definition.magazine - 1)

	-- Une fois la cadence ecoulee.
	local ok = Weapons.fire(state, 10 + definition.fireRate + 0.001)
	check(report, "tir accepte apres la cadence", ok.ok, tostring(ok.error))

	-- Un client qui tire mille fois d'affilee ne doit vider que le chargeur.
	local burst = Weapons.new("rifle_ak", 0) :: any
	local accepted = 0
	local now = 100
	for _ = 1, 1000 do
		if Weapons.fire(burst, now).ok then
			accepted += 1
		end
		now += definition.fireRate + 0.001
	end
	check(report, "rafale bornee par le chargeur", accepted == definition.magazine, tostring(accepted))
	check(report, "chargeur vide", burst.ammoInMagazine == 0)

	local empty = Weapons.fire(burst, now + 10)
	check(report, "chargeur vide -> EMPTY", not empty.ok and empty.error == "EMPTY", tostring(empty.error))

	-- Plafond absolu : meme avec une cadence nulle, on ne depasse pas.
	local flood = Weapons.new("rifle_ak", 0) :: any
	local passed = 0
	for _ = 1, 200 do
		-- Meme instant : la cadence de l'arme laisserait passer le premier
		-- seulement, mais on verifie surtout que rien n'explose.
		if Weapons.fire(flood, 50).ok then
			passed += 1
		end
	end
	check(report, "meme instant : un seul tir", passed == 1, tostring(passed))
end

-- ------------------------------------------------------ Rechargement ----

local function testReload(report: Report)
	table.insert(report.lines, "rechargement")

	local state = Weapons.new("pistol_mk1", 0) :: any
	local definition = Weapons.definition("pistol_mk1")

	-- Chargeur plein : rien a faire.
	local full, _, fullError = Weapons.beginReload(state, 0, 100)
	check(report, "chargeur plein -> refus", not full and fullError == "FULL", tostring(fullError))

	-- On vide un peu.
	-- On avance d'un poil PLUS que la cadence : additionner fireRate a
	-- l'identique accumule l'erreur flottante et finit sous le seuil, ce qui
	-- ferait echouer le test sur un code parfaitement correct.
	local step = definition.fireRate + 0.001
	local now = 10
	for _ = 1, 5 do
		Weapons.fire(state, now)
		now += step
	end
	check(report, "5 tirs consommes", state.ammoInMagazine == definition.magazine - 5)

	-- Sans munitions : refus.
	local noAmmo, _, noAmmoError = Weapons.beginReload(state, now, 0)
	check(report, "sans munition -> refus", not noAmmo and noAmmoError == "NO_AMMO", tostring(noAmmoError))

	-- Avec assez : on retire exactement ce qui manque, pas un chargeur plein.
	local started, taken = Weapons.beginReload(state, now, 100)
	check(report, "rechargement demarre", started)
	check(report, "retire seulement ce qui manque", taken == 5, tostring(taken))
	check(report, "en rechargement", Weapons.isReloading(state, now))

	-- Pendant : tir refuse.
	local blocked = Weapons.fire(state, now + 0.1)
	check(report, "tir refuse pendant le rechargement", not blocked.ok and blocked.error == "RELOADING", tostring(blocked.error))

	-- Avant la fin du delai : pas encore rempli.
	check(report, "pas fini avant le delai", not Weapons.finishReload(state, now + definition.reloadTime / 2))
	check(report, "chargeur inchange", state.ammoInMagazine == definition.magazine - 5)

	-- Apres.
	check(report, "termine apres le delai", Weapons.finishReload(state, now + definition.reloadTime + 0.01))
	check(report, "chargeur rempli", state.ammoInMagazine == definition.magazine, tostring(state.ammoInMagazine))
	check(report, "plus en rechargement", not Weapons.isReloading(state, now + 10))

	-- Idempotent : rappeler ne rajoute rien.
	Weapons.finishReload(state, now + 100)
	check(report, "finishReload idempotent", state.ammoInMagazine == definition.magazine, tostring(state.ammoInMagazine))

	-- Munitions insuffisantes : on remplit partiellement.
	local partial = Weapons.new("pistol_mk1", 0) :: any
	local t = 200
	for _ = 1, 8 do
		Weapons.fire(partial, t)
		t += definition.fireRate + 0.001
	end
	local _, takenPartial = Weapons.beginReload(partial, t, 3)
	check(report, "rechargement partiel : 3 prises", takenPartial == 3, tostring(takenPartial))
	Weapons.finishReload(partial, t + definition.reloadTime + 0.01)
	check(report, "chargeur partiellement rempli", partial.ammoInMagazine == definition.magazine - 8 + 3, tostring(partial.ammoInMagazine))

	-- Annulation : les munitions retenues sont rendues.
	local cancelled = Weapons.new("pistol_mk1", 0) :: any
	Weapons.fire(cancelled, 300)
	local _, reserved = Weapons.beginReload(cancelled, 300, 50)
	local returned = Weapons.cancelReload(cancelled)
	check(report, "annulation rend les munitions", returned == reserved, `{returned} vs {reserved}`)
	check(report, "plus en rechargement apres annulation", not Weapons.isReloading(cancelled, 300))
	check(report, "chargeur non rempli apres annulation", cancelled.ammoInMagazine == definition.magazine - 1)
end

-- ------------------------------------------------------- Entrees sales --

local function testBadInput(report: Report)
	table.insert(report.lines, "entrees aberrantes")

	local state = Weapons.new("rifle_ak", 0) :: any

	local nan = Weapons.fire(state, 0 / 0)
	check(report, "temps NaN refuse", not nan.ok, tostring(nan.error))

	local infinite = Weapons.fire(state, math.huge)
	check(report, "temps infini refuse", not infinite.ok, tostring(infinite.error))

	check(report, "chargeur intact apres refus", state.ammoInMagazine == Weapons.definition("rifle_ak").magazine)

	local badAmmo = Weapons.beginReload(state, 0, 0 / 0)
	check(report, "quantite de munitions NaN refusee", not badAmmo)

	local negative = Weapons.beginReload(state, 0, -50)
	check(report, "quantite negative refusee", not negative)
end

-- ------------------------------------------------------------ Run ------

function WeaponTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testCatalogue(report)
	testFireRate(report)
	testReload(report)
	testBadInput(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)
	return table.concat(report.lines, "\n")
end

return WeaponTests
