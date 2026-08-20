--!strict
-- Lance toutes les suites et agrege le verdict.
--
-- Onze suites lancees a la main, c'est onze occasions d'en oublier une et de
-- croire que tout passe. Ce module les enumere par decouverte : ajouter un
-- fichier `XxxTests` dans ce dossier suffit a l'inclure.
--
-- A lancer PENDANT un playtest. Hors partie, l'execution par MCP tourne dans
-- un VM separe dont le cache de modules peut etre perime : on a deja vu des
-- echecs fantomes ou ItemDatabase renvoyait un catalogue tronque.
--
--   require(game.ServerStorage.Tests.RunAll).run()

local RunAll = {}

function RunAll.run(): string
	local suites: { ModuleScript } = {}
	for _, child in script.Parent:GetChildren() do
		if child:IsA("ModuleScript") and child ~= script and child.Name:match("Tests$") then
			table.insert(suites, child)
		end
	end

	table.sort(suites, function(a, b)
		return a.Name < b.Name
	end)

	local lines: { string } = {}
	local passed, failed, broken = 0, 0, 0

	for _, suite in suites do
		local ok, result = pcall(function()
			return (require(suite) :: any).run()
		end)

		if not ok then
			broken += 1
			table.insert(lines, `{suite.Name} : LA SUITE A LEVE -> {tostring(result)}`)
			continue
		end

		local text = tostring(result)

		-- On relit le verdict plutot que de demander a chaque suite de
		-- renvoyer des compteurs : leur format est deja fige et utilise a la
		-- main, le changer pour cet agregat serait une regression d'ergonomie.
		local suitePassed = tonumber(text:match("(%d+) reussis") or "0") or 0
		local suiteFailed = tonumber(text:match("(%d+) echoues") or "0") or 0

		passed += suitePassed
		failed += suiteFailed

		local verdict = if suiteFailed == 0 then "ok" else `{suiteFailed} ECHEC(S)`
		table.insert(lines, string.format("%-20s %4d assertions   %s", suite.Name, suitePassed, verdict))

		-- Le detail n'est utile que s'il y a quelque chose a lire.
		if suiteFailed > 0 then
			for line in text:gmatch("[^\n]+") do
				if line:match("FAIL") then
					table.insert(lines, `    {line}`)
				end
			end
		end
	end

	table.insert(lines, "")
	table.insert(
		lines,
		if failed == 0 and broken == 0
			then `TOUT PASSE — {#suites} suites, {passed} assertions`
			else `{failed} ECHEC(S) et {broken} SUITE(S) CASSEE(S) sur {#suites} — {passed} assertions reussies`
	)

	return table.concat(lines, "\n")
end

return RunAll
