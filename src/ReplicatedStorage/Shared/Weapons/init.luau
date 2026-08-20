--!strict
-- Etat de tir d'une arme, pur.
--
-- Cadence, chargeur, rechargement. Aucun Player, aucun raycast, aucun
-- Instance : le temps est un argument. C'est ce qui rend testable une rafale
-- de trente balles, un rechargement interrompu ou un client qui tire mille
-- fois par seconde, sans lancer de partie.
--
-- Ce module ne decide PAS si un tir touche. Il decide si un tir est permis.
-- Ce que la balle rencontre appartient a CombatService, qui seul voit le
-- monde.

local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)

type WeaponState = Types.WeaponState
type FireDecision = Types.FireDecision

local Weapons = {}

local function isUsable(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Weapons.definition(itemId: string)
	if type(itemId) ~= "string" then
		return nil
	end
	return Config.Weapons.weapons[itemId]
end

function Weapons.isWeapon(itemId: string): boolean
	return Weapons.definition(itemId) ~= nil
end

function Weapons.new(itemId: string, now: number): WeaponState?
	local definition = Weapons.definition(itemId)
	if not definition then
		return nil
	end

	return {
		itemId = itemId,
		-- Le chargeur demarre plein : le joueur qui ramasse une arme ne
		-- doit pas decouvrir qu'elle est vide au moment ou il en a besoin.
		ammoInMagazine = definition.magazine,
		lastFiredAt = -math.huge,
		reloadingUntil = nil,
		shotsThisSecond = 0,
		secondStartedAt = now,
	}
end

function Weapons.isReloading(state: WeaponState, now: number): boolean
	local until_ = state.reloadingUntil
	return until_ ~= nil and now < until_
end

-- Le tir est-il permis ? Rend un code stable, pas un message : le client
-- comme les tests branchent dessus.
function Weapons.canFire(state: WeaponState, now: number): (boolean, string?)
	local definition = Weapons.definition(state.itemId)
	if not definition then
		return false, "NO_WEAPON"
	end
	if not isUsable(now) then
		return false, "BAD_TIME"
	end
	if Weapons.isReloading(state, now) then
		return false, "RELOADING"
	end
	if state.ammoInMagazine <= 0 then
		return false, "EMPTY"
	end
	if (now - state.lastFiredAt) < definition.fireRate then
		return false, "TOO_FAST"
	end

	-- Plafond absolu, independant de la cadence de l'arme. Une arme mal
	-- configuree a fireRate = 0 passerait le test precedent sans celui-ci.
	local elapsed = now - state.secondStartedAt
	if elapsed >= 1 then
		state.secondStartedAt = now
		state.shotsThisSecond = 0
	elseif state.shotsThisSecond >= Config.Weapons.validation.maxShotsPerSecond then
		return false, "RATE_LIMIT"
	end

	return true, nil
end

-- Consomme une munition et horodate le tir. A n'appeler qu'apres canFire.
function Weapons.fire(state: WeaponState, now: number): FireDecision
	local allowed, reason = Weapons.canFire(state, now)
	if not allowed then
		return { ok = false, error = reason, ammoInMagazine = state.ammoInMagazine }
	end

	state.ammoInMagazine -= 1
	state.lastFiredAt = now
	state.shotsThisSecond += 1

	return { ok = true, error = nil, ammoInMagazine = state.ammoInMagazine }
end

-- Demarre un rechargement. `available` est la quantite de munitions du bon
-- calibre reellement possedee ; la fonction rend combien il faut retirer de
-- l'inventaire.
function Weapons.beginReload(state: WeaponState, now: number, available: number): (boolean, number, string?)
	local definition = Weapons.definition(state.itemId)
	if not definition then
		return false, 0, "NO_WEAPON"
	end
	if Weapons.isReloading(state, now) then
		return false, 0, "RELOADING"
	end
	if state.ammoInMagazine >= definition.magazine then
		return false, 0, "FULL"
	end
	if not isUsable(available) or available <= 0 then
		return false, 0, "NO_AMMO"
	end

	local missing = definition.magazine - state.ammoInMagazine
	local taken = math.min(missing, math.floor(available))
	if taken <= 0 then
		return false, 0, "NO_AMMO"
	end

	state.reloadingUntil = now + definition.reloadTime
	-- Les munitions sont retirees de l'inventaire MAINTENANT, pas a la fin.
	-- Sinon un joueur qui meurt en rechargeant garde ses balles alors que
	-- son chargeur est deja compte comme rempli cote client.
	state.pendingReload = taken

	return true, taken, nil
end

-- Termine le rechargement si le delai est ecoule. Idempotent.
function Weapons.finishReload(state: WeaponState, now: number): boolean
	if state.reloadingUntil == nil or now < state.reloadingUntil then
		return false
	end

	state.ammoInMagazine += state.pendingReload or 0
	state.pendingReload = nil
	state.reloadingUntil = nil
	return true
end

-- Annule un rechargement en cours et rend les munitions a restituer.
function Weapons.cancelReload(state: WeaponState): number
	local pending = state.pendingReload or 0
	state.pendingReload = nil
	state.reloadingUntil = nil
	return pending
end

return Weapons
