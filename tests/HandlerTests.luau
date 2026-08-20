--!strict
-- Tests du commanditaire.
--
-- Deux natures de verification, et les deux comptent :
--
--   LE VOCABULAIRE  une faute de frappe dans HandlerConfig ne leve aucune
--                   erreur. Un ton inconnu donne du texte blanc, un item
--                   inexistant donne une directive inaccomplissable, un
--                   marqueur mal ecrit laisse « {carg} » a l'ecran. Rien de
--                   tout cela ne se voit sans jouer plusieurs minutes.
--
--   LA CADENCE      interruption, abandon, monotonie, silence. C'est ce qui
--                   decide si la voix pese ou si elle harcele.
--
--   require(game.ServerStorage.Tests.HandlerTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Handler = require(Shared.Handler)

local HandlerTests = {}

local cfg = Config.Handler

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

-- Tirage deterministe : les tests ne doivent pas dependre de math.random.
-- Renvoie toujours la premiere variante.
local function firstVariant(_n: number): number
	return 1
end

-- ---------------------------------------------------------- Vocabulaire --

local TONES = { neutral = true, technical = true, warning = true, danger = true }

local function testVocabulary(report: Report)
	table.insert(report.lines, "vocabulaire")

	-- Les lignes ne portent plus de TEXTE depuis le passage a la
	-- localisation : elles declarent un ton et une priorite, le texte vit
	-- dans Shared/Locale. Le controle des marqueurs a suivi le texte et se
	-- fait desormais dans LocaleTests, qui a acces aux vraies chaines.
	local badTone, badPriority = {}, {}
	local total = 0

	for key, line in cfg.lines do
		total += 1

		if not TONES[line.tone] then
			table.insert(badTone, `{key}={line.tone}`)
		end
		if cfg.priority[line.priority] == nil then
			table.insert(badPriority, `{key}={line.priority}`)
		end
	end

	check(report, "vocabulaire non vide", total > 0, `{total} cles`)
	check(report, "tous les tons connus", #badTone == 0, table.concat(badTone, ", "))
	check(report, "toutes les priorites connues", #badPriority == 0, table.concat(badPriority, ", "))

	-- Les cles que le service appelle nommement doivent exister.
	local required = {
		"deploy", "firstLoot", "cargoLow", "cargoMid", "cargoHigh",
		"bandALERT", "bandDANGER", "bandSEVERE", "bandCRITICAL",
		"hunt", "huntEnd", "teammateDown", "teammateExtracted", "lowHealth",
		"idle", "windowWarning", "windowFinal", "windowClosed",
		"extractionOpen", "extractionDone", "extractionLost",
		"contractAssigned", "objectiveDone", "contractDone", "ambient",
	}
	local missing = {}
	for _, key in required do
		if not cfg.lines[key] then
			table.insert(missing, key)
		end
	end
	check(report, "toutes les cles appelees existent", #missing == 0, table.concat(missing, ", "))
end

-- ------------------------------------------------------------- Cadence ---

local function testInterruption(report: Report)
	table.insert(report.lines, "cadence")

	local state = Handler.new(0)

	local first = Handler.submit(state, "ambient", 0, nil, firstVariant)
	check(report, "premiere transmission passe", first ~= nil)

	-- Immediatement apres, de meme priorite : abandonnee.
	local second = Handler.submit(state, "ambient", 0.1, nil, firstVariant)
	check(report, "meme priorite trop tot : abandonnee", second == nil)

	-- Plus prioritaire : passe malgre la fenetre.
	local urgent = Handler.submit(state, "bandCRITICAL", 0.2, nil, firstVariant)
	check(report, "priorite superieure interrompt", urgent ~= nil)

	-- Apres une critique, la fenetre de silence est plus longue.
	local tooSoon = Handler.submit(state, "bandDANGER", 0.2 + cfg.minGap + 0.1, nil, firstVariant)
	check(report, "silence long apres une critique", tooSoon == nil)

	local later = Handler.submit(state, "bandDANGER", 0.2 + cfg.criticalGap + 0.1, nil, firstVariant)
	check(report, "reprise apres le silence long", later ~= nil)
end

local function testOnce(report: Report)
	table.insert(report.lines, "transmissions uniques")

	local state = Handler.new(0)

	local first = Handler.submit(state, "deploy", 0, nil, firstVariant)
	check(report, "deploiement emis", first ~= nil)

	local again = Handler.submit(state, "deploy", 1000, nil, firstVariant)
	check(report, "deploiement non repete", again == nil)

	-- Une transmission `once` abandonnee par la cadence doit rester
	-- disponible : sinon un evenement unique peut se perdre a jamais.
	local other = Handler.new(0)
	Handler.submit(other, "bandCRITICAL", 0, nil, firstVariant)
	local dropped = Handler.submit(other, "firstLoot", 0.1, nil, firstVariant)
	check(report, "unique abandonnee : pas consommee", dropped == nil)
	local retried = Handler.submit(other, "firstLoot", 100, nil, firstVariant)
	check(report, "unique abandonnee : rejouable plus tard", retried ~= nil)
end

local function testMonotony(report: Report)
	table.insert(report.lines, "monotonie des paliers")

	local state = Handler.new(0)

	local low = Handler.cargoChanged(state, 2000, 0)
	check(report, "palier de cargaison franchi", low ~= nil)

	local same = Handler.cargoChanged(state, 2500, 100)
	check(report, "meme palier : muet", same == nil)

	local down = Handler.cargoChanged(state, 10, 200)
	check(report, "cargaison qui retombe : muet", down == nil)

	local back = Handler.cargoChanged(state, 2000, 300)
	check(report, "palier deja franchi : muet au retour", back == nil)

	local higher = Handler.cargoChanged(state, 7000, 400)
	check(report, "palier superieur : parle", higher ~= nil)

	-- Menace : meme regle.
	local threat = Handler.new(0)
	check(report, "montee en ALERT annoncee", Handler.bandChanged(threat, "ALERT", 0) ~= nil)
	check(report, "retour en SAFE muet", Handler.bandChanged(threat, "SAFE", 100) == nil)
	check(report, "re-montee en ALERT muette", Handler.bandChanged(threat, "ALERT", 200) == nil)
	check(report, "montee en SEVERE annoncee", Handler.bandChanged(threat, "SEVERE", 300) ~= nil)
end

local function testSilence(report: Report)
	table.insert(report.lines, "silence pendant la traque")

	local state = Handler.new(0)

	local hunt = Handler.bandChanged(state, "HUNT", 0)
	check(report, "la traque s'annonce", hunt ~= nil)
	check(report, "le bureau se tait ensuite", state.silenced == true)

	local muted = Handler.submit(state, "bandCRITICAL", 100, nil, firstVariant)
	check(report, "plus rien ne passe", muted == nil)

	local ambient = Handler.tick(state, 10000, firstVariant)
	check(report, "le remplissage se tait aussi", ambient == nil)

	local back = Handler.submit(state, "huntEnd", 200, nil, firstVariant)
	check(report, "la fin de traque perce le silence", back ~= nil)
	check(report, "le bureau reprend", state.silenced == false)

	local resumed = Handler.submit(state, "bandDANGER", 200 + cfg.criticalGap + 1, nil, firstVariant)
	check(report, "transmissions a nouveau possibles", resumed ~= nil)
end

local function testIdle(report: Report)
	table.insert(report.lines, "rappel de rendement")

	local state = Handler.new(0)

	check(report, "silencieux tant que le temps ne passe pas", Handler.tick(state, 1, firstVariant) == nil)

	local nagging = Handler.tick(state, cfg.idleAfter + 1, firstVariant)
	check(report, "rappel apres inactivite", nagging ~= nil)

	-- Un ramassage remet le compteur a zero : c'est ce qui fait que le
	-- rappel ne vise que les joueurs qui ne produisent vraiment rien.
	Handler.recordLoot(state, cfg.idleAfter + 2)
	local quiet = Handler.tick(state, cfg.idleAfter + 3, firstVariant)
	check(report, "un ramassage fait taire le rappel", quiet == nil)
end

-- ------------------------------------------------------------ Formatage --

local function testFormatting(report: Report)
	table.insert(report.lines, "formatage")

	check(report, "petits nombres inchanges", Handler.formatNumber(42) == "42")
	check(report, "millier groupe", utf8.len(Handler.formatNumber(1500)) == 5)
	check(report, "zero", Handler.formatNumber(0) == "0")

	-- Une transmission ne porte plus de TEXTE : elle porte une cle et des
	-- champs, que chaque client traduit dans sa langue. Ce que ce test doit
	-- verifier a donc change de nature — c'est la forme du contrat entre
	-- serveur et client, pas la phrase.
	local state = Handler.new(0)
	local transmission = Handler.submit(state, "firstLoot", 0, nil, firstVariant)
	check(report, "transmission produite", transmission ~= nil)

	if transmission then
		check(
			report,
			"la cle designe la bonne entree de langue",
			transmission.textKey == "handler.firstLoot.1",
			transmission.textKey
		)
		check(report, "aucun texte affichable dans la charge", (transmission :: any).text == nil)
		check(
			report,
			"le nom de societe accompagne la cle",
			transmission.fields ~= nil and transmission.fields.company == cfg.company
		)
		check(
			report,
			"l'emetteur nomme la societe et le bureau",
			transmission.sender:find(cfg.company) ~= nil and transmission.sender:find(cfg.desk) ~= nil,
			transmission.sender
		)
	end

	-- Les nombres sont formates AVANT de partir : le client ne doit pas avoir
	-- a savoir qu'un montant se groupe par milliers.
	local other = Handler.new(0)
	local money = Handler.submit(other, "cargoHigh", 0, { cargo = 12400 }, function()
		return 2
	end)
	check(report, "montant formate a la source", money ~= nil and money.fields ~= nil)
	if money and money.fields then
		check(
			report,
			"milliers groupes dans le champ",
			utf8.len(tostring(money.fields.cargo)) == 6,
			tostring(money.fields.cargo)
		)
	end
end

-- ------------------------------------------------------------ Reglages ---

local function testTuning(report: Report)
	table.insert(report.lines, "reglages")

	check(report, "silence long > silence court", cfg.criticalGap > cfg.minGap)
	check(report, "maintien superieur au silence court", cfg.holdTime > cfg.minGap)
	check(report, "rappel espace", cfg.idleAfter > 30 and cfg.idleRepeat > 30)
	check(report, "remplissage plus rare que le rappel", cfg.ambientEvery > cfg.idleRepeat)
	check(report, "seuil de vie basse sous la moitie", cfg.lowHealthAt < 0.5)

	-- Les paliers doivent etre strictement croissants, sinon la boucle qui
	-- cherche le plus haut atteint renvoie n'importe lequel.
	local increasing = true
	for index = 2, #cfg.cargoTiers do
		if cfg.cargoTiers[index].at <= cfg.cargoTiers[index - 1].at then
			increasing = false
		end
	end
	check(report, "paliers de cargaison croissants", increasing)

	check(report, "alerte finale sous les autres", cfg.windowFinalAt < math.min(table.unpack(cfg.windowWarnAt)))
end

function HandlerTests.run(): string
	local report: Report = { passed = 0, failed = 0, lines = {} }

	testVocabulary(report)
	testInterruption(report)
	testOnce(report)
	testMonotony(report)
	testSilence(report)
	testIdle(report)
	testFormatting(report)
	testTuning(report)

	local verdict = if report.failed == 0 then "TOUT PASSE" else `{report.failed} ECHEC(S)`
	table.insert(report.lines, "")
	table.insert(report.lines, `{verdict} — {report.passed} reussis, {report.failed} echoues`)

	return table.concat(report.lines, "\n")
end

return HandlerTests
