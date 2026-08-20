--!strict
-- Filtre des charges utiles analytiques.
--
-- Pur : aucune dependance a Player ni a un service, pour que la regle la
-- plus sensible du systeme soit verifiable sans lancer de partie.
--
-- PRINCIPE — refuser plutot que nettoyer.
-- Une cle interdite fait echouer l'emission au lieu d'etre retiree en
-- silence. Un champ qui disparait sans bruit finit toujours par etre
-- reintroduit par quelqu'un qui ne savait pas ; un echec bruyant, non.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Sanitize = {}

export type Result = {
	ok: boolean,
	payload: { [string]: any }?,
	error: string?,
}

local function isForbiddenKey(key: string): boolean
	local lowered = key:lower():gsub("[^%a]", "")
	for _, forbidden in Config.Analytics.forbiddenKeys do
		if lowered == forbidden then
			return true
		end
	end
	return false
end

-- Valeurs acceptees : nombres finis, booleens, et chaines courtes. Les
-- tables sont refusees — une structure imbriquee est un endroit ou de la
-- donnee personnelle passe inapercue, et aucun tableau de bord ne sait
-- l'exploiter de toute facon.
local function checkValue(key: string, value: any): (boolean, string?)
	local kind = type(value)

	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return false, `champ {key} : nombre non fini`
		end
		return true, nil
	end

	if kind == "boolean" then
		return true, nil
	end

	if kind == "string" then
		if #value > Config.Analytics.maxStringLength then
			return false, `champ {key} : chaine de {#value} caracteres, maximum {Config.Analytics.maxStringLength}`
		end
		return true, nil
	end

	return false, `champ {key} : type {kind} non transmissible`
end

-- `forbiddenValues` recoit typiquement le nom et le nom d'affichage du
-- joueur : meme sous une cle anodine comme `source`, ils ne doivent pas
-- partir.
function Sanitize.payload(payload: any, forbiddenValues: { string }?): Result
	if payload == nil then
		return { ok = true, payload = {} }
	end
	if type(payload) ~= "table" then
		return { ok = false, error = "charge utile non tabulaire" }
	end

	local cleaned: { [string]: any } = {}
	local count = 0

	for key, value in payload do
		if type(key) ~= "string" then
			return { ok = false, error = `cle non textuelle : {tostring(key)}` }
		end

		if isForbiddenKey(key) then
			return { ok = false, error = `cle interdite (donnee personnelle) : {key}` }
		end

		local valid, reason = checkValue(key, value)
		if not valid then
			return { ok = false, error = reason }
		end

		if forbiddenValues and type(value) == "string" then
			local lowered = value:lower()
			for _, forbidden in forbiddenValues do
				if forbidden ~= "" and lowered == forbidden:lower() then
					return { ok = false, error = `champ {key} contient une donnee personnelle` }
				end
			end
		end

		count += 1
		if count > Config.Analytics.maxFields then
			return { ok = false, error = `plus de {Config.Analytics.maxFields} champs` }
		end

		cleaned[key] = value
	end

	return { ok = true, payload = cleaned }
end

-- Position de l'evenement dans un entonnoir, ou nil s'il n'y figure pas.
function Sanitize.funnelStep(eventName: string): (string?, number?)
	for _, funnel in Config.Analytics.funnels do
		for index, step in funnel.steps do
			if step == eventName then
				return funnel.name, index
			end
		end
	end
	return nil, nil
end

return Sanitize
