--!strict
-- Localisation.
--
-- Le jeu suit la langue du client Roblox : un joueur francais lit du
-- francais, un joueur anglais lit de l'anglais, dans la MEME partie.
--
-- LA REGLE QUI DECOULE DE CA
--
-- Le serveur n'envoie jamais de texte affichable. Il envoie une CLE et des
-- champs, et chaque client traduit pour lui-meme. Composer la phrase cote
-- serveur reviendrait a imposer une seule langue a six joueurs, ou a devoir
-- traduire six fois la meme chose avant de l'envoyer.
--
-- C'est pour cela que Transmission porte `textKey` et non `text`, et que les
-- objectifs de contrat portent `labelKey`.
--
-- AJOUTER UNE LANGUE
--
-- Poser un fichier a cote de `en` et `fr`, l'ajouter a `Locale.tables`, et
-- c'est tout. Les cles manquantes retombent sur l'anglais, puis sur la cle
-- elle-meme : une traduction incomplete degrade, elle ne casse pas.

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Locale = {}

export type Table = { [string]: string }

Locale.fallback = "en"

Locale.tables = {
	en = require(script.en) :: Table,
	fr = require(script.fr) :: Table,
}

-- Langues declarees, dans l'ordre d'affichage d'un eventuel selecteur.
Locale.available = { "en", "fr" }

-- Langue courante du client. Le serveur ne s'en sert pas : il n'a pas de
-- langue, il n'envoie que des cles.
local current = Locale.fallback

-- Correspondance code Roblox -> table. `RobloxLocaleId` vaut « fr-fr »,
-- « en-us », « pt-br »... On ne garde que la partie avant le tiret : on ne
-- distingue pas le francais de France de celui du Canada.
local function normalise(localeId: string): string
	local base = localeId:lower():match("^(%a+)") or Locale.fallback
	return if Locale.tables[base] then base else Locale.fallback
end

-- Detecte la langue du joueur local. A n'appeler que cote client.
function Locale.detect(): string
	if not RunService:IsClient() then
		return Locale.fallback
	end

	local player = Players.LocalPlayer
	local id = nil

	-- LocaleId du joueur d'abord (sa preference de compte), puis celui du
	-- systeme. Le premier est plus fidele a ce qu'il attend.
	local ok = pcall(function()
		id = player.LocaleId
	end)
	if not ok or not id or id == "" then
		pcall(function()
			id = LocalizationService.RobloxLocaleId
		end)
	end

	current = normalise(id or Locale.fallback)
	return current
end

function Locale.get(): string
	return current
end

-- Force une langue. Sert au selecteur manuel et aux tests.
function Locale.set(code: string): boolean
	if not Locale.tables[code] then
		return false
	end
	current = code
	return true
end

-- Substitution des champs : « Go to {zone} » + { zone = "NORTH GATE" }.
--
-- Un champ absent laisse son marqueur VISIBLE. C'est volontaire : une phrase
-- amputee passe pour une tournure voulue, un « {zone} » a l'ecran se voit
-- immediatement en playtest.
local function interpolate(text: string, fields: { [string]: any }?): string
	if not fields then
		return text
	end
	local table_ = Locale.tables[current]
	local fallbackTable = Locale.tables[Locale.fallback]

	local result = text:gsub("{(%w+)}", function(key: string): string
		local value = fields[key]
		if value == nil then
			return "{" .. key .. "}"
		end

		-- Champ imbrique : « Objective cleared: {objective} » ou {objective}
		-- vaut « contract.C001.obj1 ». On traduit avant de substituer, sinon
		-- le joueur lirait la cle brute.
		if type(value) == "string" then
			local nested = (table_ and table_[value]) or (fallbackTable and fallbackTable[value])
			if nested then
				return nested
			end
		end

		return tostring(value)
	end)
	return result
end

-- Traduit une cle. Trois niveaux de repli, du plus precis au plus visible :
--   1. la langue courante
--   2. l'anglais
--   3. la cle elle-meme, entre chevrons
function Locale.t(key: string, fields: { [string]: any }?): string
	local table_ = Locale.tables[current]
	local text = table_ and table_[key]

	if not text then
		local fallbackTable = Locale.tables[Locale.fallback]
		text = fallbackTable and fallbackTable[key]
	end

	if not text then
		return `<{key}>`
	end

	return interpolate(text, fields)
end

-- Traduit UNIQUEMENT si la cle existe, sinon rend nil.
--
-- Sert aux textes qui traversent une frontiere ou l'on ne controle pas la
-- forme — les ProximityPrompt, dont ActionText porte une cle chez nous mais
-- pourrait porter du texte brut ailleurs. `Locale.maybe(x) or x` degrade
-- proprement au lieu d'afficher « <truc> ».
function Locale.maybe(key: string?): string?
	if not key or key == "" then
		return nil
	end
	local table_ = Locale.tables[current]
	local fallbackTable = Locale.tables[Locale.fallback]
	return (table_ and table_[key]) or (fallbackTable and fallbackTable[key])
end

-- Variante pour les cles a variantes numerotees (`handler.idle.1`,
-- `handler.idle.2`...). Renvoie le nombre de variantes existantes.
function Locale.variants(prefix: string): number
	local table_ = Locale.tables[Locale.fallback]
	if not table_ then
		return 0
	end
	local count = 0
	while table_[`{prefix}.{count + 1}`] do
		count += 1
	end
	return count
end

-- Cles presentes en anglais mais absentes d'une autre langue. Utilise par
-- les tests : une traduction qui prend du retard doit se voir en CI, pas en
-- production.
function Locale.missing(code: string): { string }
	local reference = Locale.tables[Locale.fallback]
	local target = Locale.tables[code]
	local gaps: { string } = {}

	if not reference or not target then
		return gaps
	end

	for key in reference do
		if not target[key] then
			table.insert(gaps, key)
		end
	end

	table.sort(gaps)
	return gaps
end

return Locale
