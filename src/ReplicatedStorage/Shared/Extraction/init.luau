--!strict
-- Coeur d'extraction, pur.
--
-- Une extraction est une machine a trois etats (Running, Cancelled,
-- Completed) qu'on fait avancer par pas de temps. Aucun Player, aucun
-- Instance, aucun Heartbeat : c'est ce qui permet de tester la mort en
-- cours d'extraction, la sortie de zone et cinq joueurs simultanes sans
-- lancer une seule partie.
--
-- ExtractionService se contente de mesurer le monde reel, d'en deduire les
-- quatre conditions, et de faire tourner cette machine.

local Types = require(script.Parent.Types)

type Conditions = Types.ExtractionConditions
type Outcome = Types.ExtractionOutcome
type Progress = Types.ExtractionProgress

local Extraction = {}

function Extraction.begin(zoneName: string, holdTime: number): Progress
	return {
		zoneName = zoneName,
		holdTime = math.max(0, holdTime),
		elapsed = 0,
		phase = "Running",
		reason = nil,
	}
end

-- Avance l'extraction d'un pas.
--
-- L'ordre des verifications est deliberé : la mort prime sur la sortie de
-- zone. Un joueur qui meurt quitte mecaniquement la zone, et les deux
-- conditions tombent au meme instant — annoncer "sorti de zone" a un joueur
-- qui vient de se faire tuer serait faux et deroutant.
function Extraction.step(progress: Progress, dt: number, conditions: Conditions): (Outcome, string?)
	-- Un pas sur une extraction deja close ne produit jamais un second
	-- "completed" : c'est la premiere ligne de defense contre la double
	-- recompense, avant meme celle du service.
	if progress.phase ~= "Running" then
		return "finished", progress.reason
	end

	local function cancel(reason: string): (Outcome, string)
		progress.phase = "Cancelled"
		progress.reason = reason
		return "cancelled", reason
	end

	if not conditions.alive then
		return cancel("DEAD")
	end
	if not conditions.runValid then
		return cancel("RUN_INVALID")
	end
	if not conditions.zoneActive then
		return cancel("ZONE_INACTIVE")
	end
	if not conditions.inZone then
		return cancel("LEFT_ZONE")
	end

	-- Un dt aberrant est ignore plutot que propage : un pas negatif ferait
	-- reculer la barre, un NaN la figerait definitivement puisque toute
	-- comparaison ulterieure serait fausse.
	if type(dt) == "number" and dt == dt and dt > 0 and dt ~= math.huge then
		progress.elapsed += dt
	end

	if progress.elapsed >= progress.holdTime then
		progress.elapsed = progress.holdTime
		progress.phase = "Completed"
		return "completed", nil
	end

	return "running", nil
end

function Extraction.fraction(progress: Progress): number
	if progress.holdTime <= 0 then
		return 1
	end
	return math.clamp(progress.elapsed / progress.holdTime, 0, 1)
end

function Extraction.remaining(progress: Progress): number
	return math.max(0, progress.holdTime - progress.elapsed)
end

function Extraction.isRunning(progress: Progress): boolean
	return progress.phase == "Running"
end

return Extraction
