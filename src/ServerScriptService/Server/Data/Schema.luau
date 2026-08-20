--!strict
-- Schema du profil joueur : version courante, valeurs par defaut, et
-- reconciliation.
--
-- Vit cote serveur, hors de ReplicatedStorage : le client n'a aucune raison
-- de pouvoir lire la structure des profils.
--
-- REGLE CENTRALE — la reconciliation ne remplace jamais.
-- Elle comble les cles manquantes avec les defauts et laisse tout le reste
-- intact, y compris les cles qu'elle ne connait pas. Une version future qui
-- aurait ajoute un champ, puis un joueur qui repasse sur un serveur ancien :
-- son champ inconnu doit survivre au passage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)

type PlayerProfile = Types.PlayerProfile

local Schema = {}

-- Incrementer a chaque changement de forme, et ajouter l'etape de migration
-- correspondante dans Migrations.luau.
Schema.CURRENT_VERSION = 4

function Schema.defaults(): PlayerProfile
	return {
		Version = Schema.CURRENT_VERSION,
		-- Lu depuis la config, pas recopie : la valeur etait ecrite en dur
		-- ici ET dans EconomyConfig.startingCredits, si bien que modifier la
		-- config ne changeait rien aux nouveaux profils.
		Credits = Config.Economy.startingCredits,
		XP = 0,
		Level = 1,
		Reputation = {},
		Inventory = {
			Stash = {},
			Equipped = nil,
		},
		UnlockedItems = {},
		BaseUpgrades = {},
		Cosmetics = {
			Owned = {},
			Equipped = {},
		},
		Statistics = {
			Raids = 0,
			Extractions = 0,
			Deaths = 0,
			Kills = 0,
			CreditsEarned = 0,
			ItemsLooted = 0,
			Playtime = 0,
		},

		-- v3 : monetisation.
		BlackTokens = 0,

		-- [boostId] = horodatage d'expiration.
		Boosts = {},

		-- Cache des gamepasses possedes, rafraichi a la connexion.
		Gamepasses = {},

		-- Identifiants d'achat deja honores. `seen` sert au test
		-- d'idempotence, `order` a purger les plus anciens.
		Purchases = {
			seen = {},
			order = {},
		},

		-- v4 : jalons analytiques deja franchis. Les evenements "First*"
		-- valent une fois par joueur A VIE, pas par session : les garder en
		-- memoire seule les ferait rejouer a chaque reconnexion et rendrait
		-- tout entonnoir d'accueil inexploitable.
		Milestones = {},
	}
end

-- Fusion recursive : `template` fournit les cles attendues, `data` gagne
-- partout ou il a deja quelque chose.
--
-- Les listes (tables a indices numeriques) ne sont PAS fusionnees cle par
-- cle : fusionner un inventaire de trois objets avec un defaut vide
-- produirait des trous. Une liste presente est prise telle quelle.
local function isArray(value: { [any]: any }): boolean
	return next(value) == nil or value[1] ~= nil
end

local function reconcileInto(target: { [any]: any }, template: { [any]: any }): { [any]: any }
	for key, default in template do
		local current = target[key]

		if current == nil then
			if type(default) == "table" then
				target[key] = reconcileInto({}, default)
			else
				target[key] = default
			end
		elseif type(default) == "table" and type(current) == "table" and not isArray(default) then
			reconcileInto(current, default)
		end
		-- Sinon : la valeur presente reste, meme si son type surprend. On
		-- ne detruit pas une donnee qu'on ne comprend pas.
	end
	return target
end

function Schema.reconcile(data: any): PlayerProfile
	if type(data) ~= "table" then
		return Schema.defaults()
	end
	return reconcileInto(data, Schema.defaults()) :: PlayerProfile
end

-- Verification minimale, appelee avant ecriture. On ne valide pas tout le
-- schema : on verifie ce dont l'absence rendrait le profil inexploitable au
-- rechargement suivant.
function Schema.isWritable(data: any): (boolean, string?)
	if type(data) ~= "table" then
		return false, "profil absent"
	end
	if type(data.Version) ~= "number" then
		return false, "version absente"
	end
	if data.Version > Schema.CURRENT_VERSION then
		-- Un profil venu d'un serveur plus recent. L'ecraser avec notre
		-- comprehension plus ancienne detruirait des champs qu'on ignore.
		return false, `version {data.Version} superieure a la notre ({Schema.CURRENT_VERSION})`
	end
	if type(data.Credits) ~= "number" or data.Credits ~= data.Credits then
		return false, "credits invalides"
	end
	return true, nil
end

return Schema
