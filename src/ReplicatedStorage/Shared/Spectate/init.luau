--!strict
-- Qui peut etre regarde, et dans quel ordre.
--
-- Module PUR : aucun Player, aucune camera, aucun remote. On lui donne une
-- liste d'entrees decrivant l'etat de chacun, il rend la liste de ceux qu'un
-- actif sorti du raid peut suivre.
--
-- POURQUOI CE MODULE EXISTE SEPAREMENT
--
-- La regle « qui est regardable » a l'air triviale jusqu'a ce qu'on compte
-- les cas : un mort ne se regarde pas, un extrait non plus (il est en
-- securite, il n'y a rien a voir), soi-meme encore moins, et l'ordre doit
-- rester STABLE — une liste qui se reordonne toute seule fait sauter la
-- camera d'un joueur a l'autre sans que personne n'ait rien demande.
--
-- Ces quatre regles se testent sans partie. Le service serveur ne fait plus
-- que les appliquer et diffuser le resultat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

type SpectateTarget = Types.SpectateTarget

local Spectate = {}

-- Matricule affiche. Quatre chiffres derives de l'identifiant Roblox.
--
-- SOURCE UNIQUE : le HUD, le rapport de fin et la vue spectateur affichent
-- tous ce numero. Il etait recalcule a la main aux trois endroits, ce qui
-- garantissait qu'un jour l'un des trois divergerait.
function Spectate.tag(userId: number): string
	return string.format("SCAV-%04d", math.floor(math.abs(userId)) % 10000)
end

export type Entry = {
	userId: number,
	name: string,
	-- Vivant ET encore en zone. Un extrait est vivant mais n'est plus dans
	-- le raid : il n'y a rien a regarder chez lui.
	alive: boolean,
	extracted: boolean,
}

-- Liste des actifs qu'un spectateur peut suivre.
--
-- `viewerId` est exclu : se regarder soi-meme mort n'a aucun sens, et laisser
-- l'entree dans la liste ferait clignoter le nom du spectateur parmi les
-- vivants.
function Spectate.targets(entries: { Entry }, viewerId: number?): { SpectateTarget }
	local out: { SpectateTarget } = {}

	for _, entry in entries do
		if entry.userId == viewerId then
			continue
		end
		if not entry.alive or entry.extracted then
			continue
		end
		table.insert(out, {
			userId = entry.userId,
			name = entry.name,
			tag = Spectate.tag(entry.userId),
		})
	end

	-- Ordre STABLE, par identifiant. Trier par nom serait plus joli mais un
	-- joueur qui change de pseudo deplacerait tout le monde ; l'identifiant
	-- ne bouge jamais.
	table.sort(out, function(a, b)
		return a.userId < b.userId
	end)

	return out
end

-- Cible suivante dans le cycle. `direction` vaut 1 ou -1.
--
-- Renvoie nil quand il n'y a personne a regarder — c'est ce cas qui declenche
-- l'ecran « aucun signal », pas une erreur.
function Spectate.cycle(targets: { SpectateTarget }, currentId: number?, direction: number): number?
	if #targets == 0 then
		return nil
	end

	local index = 1
	for position, target in targets do
		if target.userId == currentId then
			index = position
			break
		end
	end

	local step = if direction < 0 then -1 else 1
	local next = ((index - 1 + step) % #targets) + 1
	return targets[next].userId
end

-- La cible courante est-elle encore regardable ?
--
-- Appelee a chaque diffusion : quand celui qu'on regarde meurt a son tour, il
-- faut basculer, pas rester braque sur un cadavre.
function Spectate.contains(targets: { SpectateTarget }, userId: number?): boolean
	if not userId then
		return false
	end
	for _, target in targets do
		if target.userId == userId then
			return true
		end
	end
	return false
end

-- Cible a afficher apres une diffusion : on garde la courante si elle tient
-- encore debout, sinon on prend la premiere disponible.
function Spectate.resolve(targets: { SpectateTarget }, currentId: number?): number?
	if Spectate.contains(targets, currentId) then
		return currentId
	end
	return if #targets > 0 then targets[1].userId else nil
end

return Spectate
