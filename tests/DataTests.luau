--!strict
-- Tests de la persistance.
--
-- Le backend etant injecte, tout est testable sans toucher a un vrai
-- DataStore : pannes provoquees, verrou vole, migration depuis un profil v1
-- authentique. Les delais de reprise sont neutralises par un faux `sleep`,
-- sinon la suite durerait une minute.
--
--   require(game.ServerStorage.Tests.DataTests).run()

local ServerScriptService = game:GetService("ServerScriptService")

local Data = ServerScriptService.Server.Data
local MemoryBackend = require(Data.MemoryBackend)
local Migrations = require(Data.Migrations)
local Schema = require(Data.Schema)
local Store = require(Data.Store)

local DataTests = {}

type Report = {
	passed: number,
	failed: number,
	lines: { string },
}

local function check(report: Report, name: string, condition: boolean, detail: string?)
	if condition then
		report.passed += 1
		table.insert(report.lines, `  PASS  {name}`)
	else
		report.failed += 1
		table.insert(report.lines, `  FAIL  {name}` .. (if detail then ` -> {detail}` else ""))
	end
end

-- Magasin de test : aucune attente reelle, horloge pilotable.
local function makeStore(jobId: string?, clock: (() -> number)?)
	local backend = MemoryBackend.new()
	local store = Store.new(backend, jobId or "job-A", function() end, clock or function()
		return 1000
	end)
	return store, backend
end

-- Profil tel que le prototype le produisait, en version 1.
local function legacyProfile()
	return {
		userId = 42,
		credits = 7350,
		xp = 480,
		level = 3,
		stash = {
			capacity = 600,
			slots = {
				{ id = "black_box", quantity = 1 },
				{ id = "gold_chain", quantity = 5 },
			},
		},
		stats = { raids = 12, extractions = 7, deaths = 5 },
	}
end

-- --------------------------------------------------------- Defauts ------

local function testDefaults(report: Report)
	table.insert(report.lines, "valeurs par defaut")

	local defaults = Schema.defaults()
	local expected = {
		"Version", "Credits", "XP", "Level", "Reputation",
		"Inventory", "UnlockedItems", "BaseUpgrades", "Cosmetics", "Statistics",
	}
	for _, key in expected do
		check(report, `champ {key} present`, (defaults :: any)[key] ~= nil)
	end

	check(report, "version courante", defaults.Version == Schema.CURRENT_VERSION)
	check(report, "coffre vide", #defaults.Inventory.Stash == 0)
	check(report, "statistiques a zero", defaults.Statistics.Raids == 0 and defaults.Statistics.Kills == 0)

	-- Deux appels doivent rendre deux tables distinctes, sinon deux joueurs
	-- partageraient le meme coffre.
	local a, b = Schema.defaults(), Schema.defaults()
	table.insert(a.Inventory.Stash, { id = "bandage", quantity = 1 })
	check(report, "les defauts ne sont pas partages", #b.Inventory.Stash == 0, tostring(#b.Inventory.Stash))
end

-- --------------------------------------------------- Reconciliation -----

local function testReconcile(report: Report)
	table.insert(report.lines, "reconciliation")

	-- Profil amoindri : les cles manquantes sont comblees, les presentes
	-- gardees.
	local partial = { Version = 2, Credits = 999 }
	local filled = Schema.reconcile(partial)
	check(report, "credits conserves", filled.Credits == 999, tostring(filled.Credits))
	check(report, "niveau comble", filled.Level == 1)
	check(report, "statistiques comblees", filled.Statistics.Kills == 0)

	-- Cle inconnue : conservee telle quelle. C'est la garantie qu'un serveur
	-- ancien ne detruit pas un champ ajoute par un serveur plus recent.
	local future = { Version = 2, Credits = 10, ChampDuFutur = { a = 1 } }
	local kept = Schema.reconcile(future) :: any
	check(report, "champ inconnu conserve", kept.ChampDuFutur ~= nil and kept.ChampDuFutur.a == 1)

	-- Une liste presente n'est pas fusionnee cle par cle.
	local withStash = {
		Version = 2,
		Inventory = { Stash = { { id = "medkit", quantity = 2 } } },
	}
	local stashKept = Schema.reconcile(withStash)
	check(report, "coffre existant intact", #stashKept.Inventory.Stash == 1, tostring(#stashKept.Inventory.Stash))
	check(report, "coffre : contenu preserve", stashKept.Inventory.Stash[1].id == "medkit")

	-- Entree absurde : on rend des defauts plutot que de propager le vide.
	check(report, "entree nil -> defauts", Schema.reconcile(nil).Credits == 2500)
	check(report, "entree non table -> defauts", Schema.reconcile("bonjour").Level == 1)
end

-- ------------------------------------------------------- Migration ------

local function testMigration(report: Report)
	table.insert(report.lines, "migration v1 -> v2")

	local legacy = legacyProfile()
	local migrated, applied, err = Migrations.migrate(legacy, Schema.CURRENT_VERSION)

	check(report, "aucune erreur", err == nil, tostring(err))
	local expectedSteps = Schema.CURRENT_VERSION - 1
	check(report, `{expectedSteps} etape(s) appliquee(s)`, applied == expectedSteps, tostring(applied))
	check(report, "version a jour", migrated.Version == Schema.CURRENT_VERSION, tostring(migrated.Version))

	-- Rien ne doit avoir ete perdu.
	check(report, "credits repris", migrated.Credits == 7350, tostring(migrated.Credits))
	check(report, "xp repris", migrated.XP == 480, tostring(migrated.XP))
	check(report, "niveau repris", migrated.Level == 3, tostring(migrated.Level))
	check(report, "coffre repris", #migrated.Inventory.Stash == 2, tostring(#migrated.Inventory.Stash))
	check(report, "coffre : premier objet", migrated.Inventory.Stash[1].id == "black_box")
	check(report, "statistiques reprises", migrated.Statistics.Extractions == 7, tostring(migrated.Statistics.Extractions))
	check(report, "nouvelles statistiques initialisees", migrated.Statistics.Kills == 0)

	-- Nouveaux champs de la v2.
	check(report, "Reputation cree", type(migrated.Reputation) == "table")
	check(report, "UnlockedItems cree", type(migrated.UnlockedItems) == "table")
	check(report, "BaseUpgrades cree", type(migrated.BaseUpgrades) == "table")
	check(report, "Cosmetics cree", type(migrated.Cosmetics) == "table")

	-- Les anciennes cles restent : un serveur v1 qui reprendrait la main
	-- doit retrouver les siennes.
	check(report, "anciennes cles conservees", (migrated :: any).credits == 7350)

	-- Idempotence : rejouer la migration ne doit rien casser.
	local again, appliedAgain = Migrations.migrate(migrated, Schema.CURRENT_VERSION)
	check(report, "deja a jour : 0 etape", appliedAgain == 0, tostring(appliedAgain))
	check(report, "credits inchanges apres rejeu", again.Credits == 7350)

	-- Version future : aucune etape, pas de boucle infinie.
	local futureProfile = { Version = 99, Credits = 1 }
	local _, futureApplied, futureError = Migrations.migrate(futureProfile, Schema.CURRENT_VERSION)
	check(report, "version future : aucune migration", futureApplied == 0)
	check(report, "version future : pas d'erreur", futureError == nil, tostring(futureError))

	-- Version sans etape declaree : erreur explicite, pas de blocage.
	local orphan = { Version = 0, Credits = 1 }
	local _, _, orphanError = Migrations.migrate(orphan, Schema.CURRENT_VERSION)
	check(report, "version orpheline signalee", orphanError ~= nil, tostring(orphanError))
end

-- ----------------------------------------- Chargement et sauvegarde -----

local function testLoadSave(report: Report)
	table.insert(report.lines, "chargement et sauvegarde")

	local store, backend = makeStore()
	local key = Store.keyFor(42)

	-- Premier chargement : profil neuf.
	local first = Store.load(store, key)
	check(report, "premier chargement reussi", first.ok, tostring(first.error))
	check(report, "profil neuf aux defauts", first.profile.Credits == 2500, tostring(first.profile.Credits))
	check(report, "verrou pose", backend.data[key].session ~= nil)

	-- Modification et sauvegarde.
	first.profile.Credits = 9001
	first.profile.Statistics.Raids = 3
	local saved, saveError = Store.save(store, key, first.profile, false)
	check(report, "sauvegarde reussie", saved, tostring(saveError))

	-- Rechargement dans la meme session : on retrouve ce qu'on a ecrit.
	local second = Store.load(store, key)
	check(report, "rechargement reussi", second.ok)
	check(report, "credits persistes", second.profile.Credits == 9001, tostring(second.profile.Credits))
	check(report, "statistiques persistees", second.profile.Statistics.Raids == 3)

	-- Sauvegarde avec liberation : le verrou disparait.
	Store.save(store, key, second.profile, true)
	check(report, "verrou relache", backend.data[key].session == nil)

	-- Refus d'ecrire un profil inexploitable.
	local badOk, badError = Store.save(store, key, { Credits = 5 }, false)
	check(report, "ecriture sans version refusee", not badOk, tostring(badError))

	local futureOk, futureError = Store.save(store, key, { Version = 99, Credits = 5 }, false)
	check(report, "ecriture d'une version future refusee", not futureOk, tostring(futureError))
	check(report, "credits intacts apres refus", backend.data[key].profile.Credits == 9001)
end

-- ----------------------------------- Chargement d'un profil hérité ------

local function testLegacyLoad(report: Report)
	table.insert(report.lines, "chargement d'un profil v1 existant")

	local store, backend = makeStore()
	local key = Store.keyFor(7)

	-- On depose directement un profil v1 dans le magasin, comme s'il avait
	-- ete ecrit par une version anterieure du jeu.
	backend.data[key] = { profile = legacyProfile() }

	local result = Store.load(store, key)
	check(report, "chargement reussi", result.ok, tostring(result.error))
	check(
		report,
		"toutes les migrations appliquees",
		result.migrated == Schema.CURRENT_VERSION - 1,
		tostring(result.migrated)
	)
	check(report, "credits preserves", result.profile.Credits == 7350, tostring(result.profile.Credits))
	check(report, "coffre preserve", #result.profile.Inventory.Stash == 2)
	check(report, "version a jour", result.profile.Version == Schema.CURRENT_VERSION)
	check(report, "champs v2 combles", type(result.profile.Cosmetics.Owned) == "table")
end

-- ------------------------------------------------- Reprise sur erreur ---

local function testRetry(report: Report)
	table.insert(report.lines, "reprise sur erreur")

	local store, backend = makeStore()
	local key = Store.keyFor(1)

	-- Trois pannes puis succes : le chargement doit passer.
	backend.failNext = 3
	local result = Store.load(store, key)
	check(report, "chargement malgre 3 pannes", result.ok, tostring(result.error))
	check(report, "tentatives comptees", result.attempts >= 4, tostring(result.attempts))
	check(report, "reprises comptabilisees", store.stats.retries >= 3, tostring(store.stats.retries))

	-- Panne permanente : abandon propre, pas de profil fantome.
	local store2, backend2 = makeStore()
	backend2.failAlways = true
	local failed = Store.load(store2, Store.keyFor(2))
	check(report, "panne permanente : echec signale", not failed.ok)
	check(report, "aucun profil rendu", failed.profile == nil)
	check(report, "message explicite", failed.error ~= nil and failed.error:find("tentatives") ~= nil, tostring(failed.error))

	-- Meme chose a la sauvegarde.
	local store3, backend3 = makeStore()
	local key3 = Store.keyFor(3)
	local loaded = Store.load(store3, key3)
	backend3.failAlways = true
	local ok, err = Store.save(store3, key3, loaded.profile, false)
	check(report, "sauvegarde en panne : echec signale", not ok, tostring(err))
end

-- --------------------------------------------- Protection de session ----

local function testSessionLock(report: Report)
	table.insert(report.lines, "protection de session")

	local backend = MemoryBackend.new()
	local now = 1000
	local clock = function()
		return now
	end
	local noSleep = function() end

	local serverA = Store.new(backend, "job-A", noSleep, clock)
	local serverB = Store.new(backend, "job-B", noSleep, clock)
	local key = Store.keyFor(55)

	-- A prend le joueur.
	local loadA = Store.load(serverA, key)
	check(report, "serveur A charge", loadA.ok)

	-- B tente pendant que A tient le verrou : refuse.
	local loadB = Store.load(serverB, key)
	check(report, "serveur B refuse pendant le verrou", not loadB.ok, tostring(loadB.error))
	check(report, "conflit comptabilise", serverB.stats.conflicts > 0, tostring(serverB.stats.conflicts))

	-- A modifie et relache.
	loadA.profile.Credits = 4242
	Store.save(serverA, key, loadA.profile, true)

	-- B peut maintenant prendre la main, et voit les donnees de A.
	local loadB2 = Store.load(serverB, key)
	check(report, "serveur B charge apres liberation", loadB2.ok, tostring(loadB2.error))
	check(report, "B voit les donnees de A", loadB2.profile.Credits == 4242, tostring(loadB2.profile.Credits))

	-- A tente d'ecrire alors que B tient le verrou : refuse, sinon la
	-- progression de B serait ecrasee par l'etat perime de A.
	local staleOk, staleError = Store.save(serverA, key, loadA.profile, false)
	check(report, "ecriture perimee refusee", not staleOk, tostring(staleError))
	check(report, "donnees de B intactes", backend.data[key].profile.Credits == 4242)

	-- Verrou abandonne : apres expiration, un autre serveur le reprend.
	local backend2 = MemoryBackend.new()
	local now2 = 1000
	local clock2 = function()
		return now2
	end
	local crashed = Store.new(backend2, "job-mort", noSleep, clock2)
	local rescuer = Store.new(backend2, "job-vivant", noSleep, clock2)
	local key2 = Store.keyFor(56)

	Store.load(crashed, key2)
	now2 += 10
	check(report, "verrou frais : reprise refusee", not Store.load(rescuer, key2).ok)

	now2 += 200
	check(report, "verrou expire : reprise autorisee", Store.load(rescuer, key2).ok)
end

-- --------------------------------------------------------------- Run ----

function DataTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testDefaults(report)
	testReconcile(report)
	testMigration(report)
	testLoadSave(report)
	testLegacyLoad(report)
	testRetry(report)
	testSessionLock(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return DataTests
