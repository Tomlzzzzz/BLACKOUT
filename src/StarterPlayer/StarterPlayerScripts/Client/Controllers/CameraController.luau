--!strict
-- Camera premiere personne.
--
-- Deux responsabilites, et rien d'autre :
--   1. verrouiller la vue en premiere personne et l'y maintenir
--   2. porter l'escalade de menace dans l'image elle-meme
--
-- Aucune autorite de jeu ici. Le controller ne lit que des valeurs deja
-- repliquees (vie, vitesse du personnage) et le palier de menace que le
-- serveur diffuse.
--
-- POURQUOI BindToRenderStep ET PAS Heartbeat
--
-- C'est l'exception a la regle posee dans HudController. Le HUD anime des
-- opacites, ce qui n'a aucun besoin de s'executer avant le rendu ; la camera
-- si. Une correction de CFrame appliquee sur Heartbeat est ecrasee par les
-- scripts de camera Roblox, qui tournent eux sur RenderStep. On se branche
-- donc juste apres eux.
--
-- Corollaire a connaitre pour le debug : quand la fenetre Studio affiche la
-- vue serveur, RenderStep ne part pas et cette boucle est muette. Cela ne se
-- verifie que depuis une vraie fenetre client.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Logger = require(Shared.Utils.Logger)

type ServiceContext = Types.ServiceContext
type ThreatBand = Types.ThreatBand

local CameraController = {}

CameraController.Name = "CameraController"
-- Avant le HUD : la vue doit etre verrouillee avant que quoi que ce soit
-- s'affiche par-dessus.
CameraController.Priority = 5

local log = Logger.new("Camera")
local player = Players.LocalPlayer
local settings = Config.Camera

local connections: { RBXScriptConnection } = {}
local bound = false

-- Un autre systeme tient-il la camera ?
--
-- La vue spectateur pose la camera elle-meme. Sans ce drapeau, ce controller
-- continuerait d'empiler respiration, balancement et tremblement PAR-DESSUS,
-- et de lutter contre son interpolation : le flux de surveillance se mettrait
-- a respirer comme un vivant, ce qui est exactement le contraire de ce qu'il
-- raconte.
local suspended = false

local band: ThreatBand = "SAFE"

-- Charge de la cellule, 0 a 1. Elle alimente la lampe ET la camera embarquee :
-- a plat, l'image que le joueur voit se degrade. C'est la seule consequence
-- visuelle d'une batterie vide, et elle justifie la jauge.
local battery = 1
local blur: BlurEffect? = nil
-- La traque est un etat, pas un palier : le compteur redescend pendant que
-- le Warden chasse encore. Sans ce drapeau, la camera relachait sa vision
-- tunnel au moment precis ou elle devait la serrer.
local hunting = false
local clock = 0

-- Phase du balancement, avancee a la cadence des PAS et non a l'horloge.
-- Une phase liee a l'horloge continue de tourner a l'arret : le joueur
-- repart alors sur un point arbitraire du cycle, et la tete part parfois
-- vers le bas au moment ou il fait son premier pas.
local bobPhase = 0
local kick = 0
local lastHealth = -1
local exhausted = false
local sprinting = false

local RENDER_NAME = "BlackoutCamera"

-- ----------------------------------------------------------- Verrouillage

-- Le verrouillage se pose a trois endroits, et les trois sont necessaires :
-- la propriete StarterPlayer couvre l'apparition, cet appel couvre les
-- joueurs deja presents quand le script demarre, et le rebranchement sur
-- CharacterAdded couvre les reapparitions, ou Roblox remet parfois la
-- valeur par defaut.
local function lockFirstPerson()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
end

-- ---------------------------------------------------------------- Etats --

local function activeBand(): string
	return if hunting then "HUNT" else band
end

local function bandValue(map: { [string]: number }): number
	return map[activeBand()] or map.SAFE or 0
end

local function watchCharacter(character: Model)
	lockFirstPerson()

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	lastHealth = humanoid.Health

	table.insert(
		connections,
		humanoid.HealthChanged:Connect(function(health)
			-- Seules les pertes secouent. Un soin ne doit rien faire bouger.
			if lastHealth >= 0 and health < lastHealth then
				local lost = lastHealth - health
				kick = math.min(
					settings.damageKick.maximum,
					kick + (lost / 100) * settings.damageKick.perHundred
				)
			end
			lastHealth = health
		end)
	)
end

-- ----------------------------------------------------------- Boucle vue --

local function step(dt: number)
	if suspended then
		return
	end

	clock += dt

	local camera = Workspace.CurrentCamera
	local character = player.Character
	if not camera or not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	-- --- accroupi ---------------------------------------------------------
	--
	-- On lit l'ATTRIBUT pose par le serveur, jamais une variable locale :
	-- c'est la meme source que celle que les creatures consultent, donc la
	-- camera ne peut pas descendre sans que la discretion suive.
	--
	-- CameraOffset plutot qu'un redimensionnement du personnage : c'est le
	-- seul moyen d'abaisser le point de vue sans toucher aux collisions ni
	-- au rig, et il s'interpole proprement.
	local crouchDrop = 0
	if player:GetAttribute("Crouched") == true then
		crouchDrop = -Config.Player.crouch.cameraDrop
	end

	-- --- champ de vision ------------------------------------------------
	local target = settings.baseFov
		+ (if sprinting and not exhausted then settings.sprintFov - settings.baseFov else 0)
		+ bandValue(settings.threatFov)

	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * settings.fovLerp)

	-- --- respiration ----------------------------------------------------
	local breath = settings.breath[activeBand()] or settings.breath.SAFE
	local breathPitch = math.sin(clock * breath.speed * math.pi * 2) * breath.amplitude
	local breathRoll = math.sin(clock * breath.speed * math.pi * 2 * 0.5) * breath.amplitude * 0.6

	-- --- balancement de marche -------------------------------------------
	--
	-- Il produit un DECALAGE DE POSITION, jamais une rotation : faire pivoter
	-- la camera en premiere personne deplace le viseur a chaque pas.
	--
	-- La phase avance a la cadence des PAS et non a l'horloge : elle s'arrete
	-- net quand le joueur s'arrete, au lieu de continuer a tourner dans le
	-- vide et de faire repartir la tete vers le bas au premier pas suivant.
	local bobRise, bobSway = 0, 0
	if root and root:IsA("BasePart") and humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
		local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		local ratio = math.clamp(speed / settings.bob.referenceSpeed, 0, 1)

		if ratio > 0.02 then
			local running = sprinting and not exhausted
			local gain = ratio * (if running then settings.bob.sprintAmplitude else 1)

			local cadence = if running
				then settings.bob.sprintCadence
				else settings.bob.walkCadence * (0.65 + ratio * 0.35)
			bobPhase += dt * cadence * math.pi * 2

			-- Une montee-descente par pas.
			bobRise = math.sin(bobPhase) * settings.bob.rise * gain
			-- Un balancement lateral par FOULEE : deux pas, donc demi-frequence.
			bobSway = math.sin(bobPhase * 0.5) * settings.bob.sway * gain
		end
	end

	-- --- tremblement ------------------------------------------------------
	local jitter = bandValue(settings.shake)
	local shakePitch = if jitter > 0 then (math.random() - 0.5) * 2 * jitter else 0
	local shakeYaw = if jitter > 0 then (math.random() - 0.5) * 2 * jitter else 0

	-- --- optique de la camera embarquee -----------------------------------
	--
	-- Le flou n'apparait que sur la fin de charge, et reste LEGER : il doit
	-- inquieter, pas empecher de jouer. A zero pour cent il plafonne a une
	-- valeur ou l'on distingue encore une silhouette a vingt metres.
	local current = blur
	if current then
		local fade = math.clamp((settings.opticsBlurBelow - battery) / settings.opticsBlurBelow, 0, 1)
		local target = fade * settings.opticsBlurMax
		current.Size += (target - current.Size) * math.min(1, dt * 2)
	end

	-- --- encaissement -----------------------------------------------------
	if kick > 0 then
		kick = math.max(0, kick - dt * settings.damageKick.decay)
	end
	local kickPitch = kick

	-- DECALAGE DU POINT DE VUE : accroupi et balancement, ensemble.
	--
	-- Un seul ecrivain pour `CameraOffset`. Deux blocs qui l'ecrivent chacun
	-- de leur cote se seraient ecrases mutuellement une image sur deux.
	if humanoid then
		local wanted = Vector3.new(bobSway, crouchDrop + bobRise, 0)
		local current = humanoid.CameraOffset
		humanoid.CameraOffset = current:Lerp(wanted, math.min(1, dt * settings.bob.follow))
	end

	-- ROTATION : uniquement ce qui doit DERANGER LA VISEE — la respiration, le
	-- tremblement de peur, le coup encaisse. Le balancement de marche n'y est
	-- pas, et c'est tout l'objet de la correction.
	camera.CFrame = camera.CFrame
		* CFrame.Angles(
			math.rad(breathPitch + shakePitch - kickPitch),
			math.rad(shakeYaw),
			math.rad(breathRoll)
		)
end

-- -------------------------------------------------------- Cycle de vie ---

-- Rend la camera a un autre systeme, ou la reprend.
function CameraController.SetSuspended(value: boolean)
	if suspended == value then
		return
	end
	suspended = value

	-- A la reprise, on remet la camera dans son mode normal : la vue
	-- spectateur l'a laissee en Scriptable, et le verrouillage premiere
	-- personne ne se rattraperait jamais tout seul.
	if not value then
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		lockFirstPerson()
	end
end

function CameraController.Init(context: ServiceContext) end

function CameraController.Start()
	lockFirstPerson()

	-- Abonnement defensif.
	--
	-- La premiere version faisait un FindFirstChild sans attente et repartait
	-- en silence si le remote manquait. Ce controller demarre en priorite 5,
	-- avant tous les autres : le dossier Remotes existait deja mais ses
	-- enfants n'avaient pas fini de se repliquer, l'abonnement a la menace
	-- n'a jamais ete pris, et la camera est restee bloquee sur SAFE toute la
	-- partie sans lever la moindre erreur.
	--
	-- Le seul symptome etait un champ de vision qui refusait de bouger. On
	-- attend, et si le remote manque vraiment on le DIT.
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local function bind(remoteName: string, handler: (...any) -> ())
		local remote = remotes:WaitForChild(remoteName, 10)
		if not remote or not remote:IsA("RemoteEvent") then
			log:warn(`remote absent : {remoteName} — la camera ne suivra pas cet etat`)
			return
		end
		table.insert(connections, remote.OnClientEvent:Connect(handler))
	end

	bind("ThreatLevelChanged", function(_value: number, nextBand: string)
		band = nextBand :: ThreatBand
	end)

	bind("HudSnapshot", function(snapshot: Types.HudSnapshot)
		band = snapshot.band
	end)

	bind("HuntStarted", function()
		hunting = true
	end)

	bind("HuntEnded", function()
		hunting = false
	end)

	-- L'endurance pilote le champ de vision : on ne veut pas du cadrage de
	-- course chez un joueur epuise qui n'avance plus.
	bind("StaminaChanged", function(value: number, max: number, isExhausted: boolean)
		exhausted = isExhausted
		sprinting = value < max * 0.995 and not isExhausted
	end)

	bind("VitalsChanged", function(vitals: Types.Vitals)
		battery = if vitals.maxBattery > 0 then math.clamp(vitals.battery / vitals.maxBattery, 0, 1) else 0
	end)

	-- Flou de la camera embarquee. Cree ici et non dans Lighting au montage :
	-- il appartient a la vue du joueur, et Stop doit pouvoir le retirer.
	local existing = Lighting:FindFirstChild("BlackoutOpticsBlur")
	if existing then
		existing:Destroy()
	end
	local effect = Instance.new("BlurEffect")
	effect.Name = "BlackoutOpticsBlur"
	effect.Size = 0
	effect.Parent = Lighting
	blur = effect

	if player.Character then
		watchCharacter(player.Character)
	end
	table.insert(connections, player.CharacterAdded:Connect(watchCharacter))

	-- Juste apres les scripts de camera Roblox, sinon leur ecriture de
	-- CFrame ecrase la notre a chaque image.
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local ok, err = pcall(step, dt)
		if not ok and bound then
			bound = false
			RunService:UnbindFromRenderStep(RENDER_NAME)
			log:error(`step a leve, camera relachee -> {tostring(err)}`)
		end
	end)
	bound = true

	log:info("premiere personne verrouillee")
end

function CameraController.Stop()
	if blur then
		blur:Destroy()
		blur = nil
	end
	if bound then
		RunService:UnbindFromRenderStep(RENDER_NAME)
		bound = false
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return CameraController
