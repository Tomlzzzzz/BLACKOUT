--!strict
-- Tests de localisation.
--
-- Une traduction se casse SILENCIEUSEMENT. Une cle oubliee affiche
-- « <hud.threat> », un marqueur perdu fait disparaitre un montant, une
-- variante manquante rend une transmission muette — et rien de tout cela ne
-- leve d'erreur. Ces tests sont la pour que ca se voie ici plutot qu'en jeu.
--
--   require(game.ServerStorage.Tests.LocaleTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemDatabase = require(Shared.ItemDatabase)
local Locale = require(Shared.Locale)

local LocaleTests = {}

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

-- Marqueurs {champ} presents dans une chaine.
local function markers(text: string): { [string]: boolean }
	local found: { [string]: boolean } = {}
	for name in text:gmatch("{(%w+)}") do
		found[name] = true
	end
	return found
end

local function keysOf(table_: { [string]: string }): { string }
	local list = {}
	for key in table_ do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

-- ------------------------------------------------------- Completude ----

local function testCoverage(report: Report)
	table.insert(report.lines, "completude")

	local reference = Locale.tables[Locale.fallback]
	check(report, "langue de reference presente", reference ~= nil)
	check(report, "au moins deux langues", #Locale.available >= 2)

	for _, code in Locale.available do
		local gaps = Locale.missing(code)
		check(report, `{code} : aucune cle manquante`, #gaps == 0, table.concat(gaps, ", "))
	end

	-- Le sens inverse compte autant : une cle qui n'existe QUE en francais ne
	-- sera jamais lue par un joueur anglais, et personne ne s'en apercevra.
	for _, code in Locale.available do
		if code == Locale.fallback then
			continue
		end
		local extra = {}
		for key in Locale.tables[code] do
			if not reference[key] then
				table.insert(extra, key)
			end
		end
		table.sort(extra)
		check(report, `{code} : aucune cle orpheline`, #extra == 0, table.concat(extra, ", "))
	end
end

-- ---------------------------------------------------------- Marqueurs ---

-- LE test qui compte vraiment. Un traducteur qui ecrit « Solde credite » au
-- lieu de « Solde credite : {credits} » ne casse rien visiblement : le joueur
-- lit juste une phrase sans le montant. Ici, ca echoue.
local function testMarkers(report: Report)
	table.insert(report.lines, "marqueurs")

	local reference = Locale.tables[Locale.fallback]
	local mismatches = {}

	for _, code in Locale.available do
		if code == Locale.fallback then
			continue
		end
		for key, referenceText in reference do
			local translated = Locale.tables[code][key]
			if not translated then
				continue
			end

			local expected = markers(referenceText)
			local actual = markers(translated)

			for name in expected do
				if not actual[name] then
					table.insert(mismatches, `{code}/{key} perd ` .. "{" .. name .. "}")
				end
			end
			for name in actual do
				if not expected[name] then
					table.insert(mismatches, `{code}/{key} invente ` .. "{" .. name .. "}")
				end
			end
		end
	end

	table.sort(mismatches)
	check(report, "memes marqueurs dans toutes les langues", #mismatches == 0, table.concat(mismatches, ", "))
end

-- --------------------------------------------------- Cles referencees ---

local function testReferenced(report: Report)
	table.insert(report.lines, "cles referencees par le code")

	local reference = Locale.tables[Locale.fallback]

	-- Chaque cle du commanditaire doit avoir au moins une variante, sinon la
	-- transmission est abandonnee en silence par Handler.submit.
	local mute = {}
	for key in Config.Handler.lines do
		if Locale.variants(`handler.{key}`) == 0 then
			table.insert(mute, key)
		end
	end
	table.sort(mute)
	check(report, "toute transmission a une variante", #mute == 0, table.concat(mute, ", "))

	-- Contrats : titre, sous-titre et un libelle par objectif.
	local missing = {}
	for _, contract in Config.Contracts.contracts do
		for _, suffix in { "title", "subtitle" } do
			if not reference[`contract.{contract.id}.{suffix}`] then
				table.insert(missing, `contract.{contract.id}.{suffix}`)
			end
		end
		for index in contract.objectives do
			if not reference[`contract.{contract.id}.obj{index}`] then
				table.insert(missing, `contract.{contract.id}.obj{index}`)
			end
		end
	end
	table.sort(missing)
	check(report, "tout contrat est entierement traduit", #missing == 0, table.concat(missing, ", "))

	-- Objets : le HUD retombe sur le nom brut, mais un nom francais chez un
	-- joueur anglais reste un defaut visible.
	local untranslated = {}
	for id in ItemDatabase.all() do
		if not reference[`item.{id}`] then
			table.insert(untranslated, id)
		end
	end
	table.sort(untranslated)
	check(report, "tout objet a un nom traduit", #untranslated == 0, table.concat(untranslated, ", "))

	-- Paliers de menace.
	local bands = {}
	for _, band in { "SAFE", "ALERT", "DANGER", "SEVERE", "CRITICAL", "HUNT" } do
		if not reference[`hud.band.{band}`] then
			table.insert(bands, band)
		end
	end
	check(report, "tout palier a un libelle", #bands == 0, table.concat(bands, ", "))
end

-- ---------------------------------------------------------- Mecanique ---

local function testMechanics(report: Report)
	table.insert(report.lines, "mecanique")

	local previous = Locale.get()

	check(report, "on peut forcer une langue connue", Locale.set("fr"))
	check(report, "une langue inconnue est refusee", not Locale.set("klingon"))
	check(report, "la langue courante a suivi", Locale.get() == "fr")

	check(report, "traduction francaise", Locale.t("hud.vitals.health") == "VIE")
	Locale.set("en")
	check(report, "traduction anglaise", Locale.t("hud.vitals.health") == "HEALTH")

	-- Substitution.
	local text = Locale.t("hud.extraction.goTo", { zone = "NORTH GATE" })
	check(report, "champ substitue", text:find("NORTH GATE") ~= nil, text)
	check(report, "aucun marqueur residuel", text:find("{") == nil, text)

	-- Champ absent : le marqueur DOIT rester visible.
	local incomplete = Locale.t("hud.extraction.goTo")
	check(report, "champ manquant reste visible", incomplete:find("{zone}") ~= nil, incomplete)

	-- Cle inconnue : lisible et reperable, jamais vide.
	local unknown = Locale.t("cette.cle.n.existe.pas")
	check(report, "cle inconnue signalee", unknown:find("cette.cle") ~= nil, unknown)

	-- Resolution imbriquee : un champ qui EST une cle se traduit.
	local nested = Locale.t("handler.objectiveDone.1", { objective = "contract.C001.obj1" })
	check(report, "champ imbrique traduit", nested:find("Military Batteries") ~= nil, nested)
	check(report, "aucune cle brute affichee", nested:find("contract%.C001") == nil, nested)

	-- `maybe` ne doit rien inventer.
	check(report, "maybe rend nil sur cle inconnue", Locale.maybe("pas.une.cle") == nil)
	check(report, "maybe traduit une vraie cle", Locale.maybe("prompt.search") == "SEARCH")
	check(report, "maybe tolere nil", Locale.maybe(nil) == nil)

	Locale.set(previous)
end

function LocaleTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testCoverage(report)
	testMarkers(report)
	testReferenced(report)
	testMechanics(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return LocaleTests
