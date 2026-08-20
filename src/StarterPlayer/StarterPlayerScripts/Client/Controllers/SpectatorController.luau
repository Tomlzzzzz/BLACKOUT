--!strict
-- Vue spectateur.
--
-- Quand l'actif est sorti du raid — mort ou extrait — il ne revient pas
-- avant la fenetre de contrat suivante. Il passe DE L'AUTRE COTE DE L'ECRAN :
-- il regarde ses coequipiers a travers le meme flux degrade que le
-- commanditaire regarde depuis le debut.
--
-- CE QUI DISPARAIT
--
-- Tout le HUD de jeu. Il n'a plus de vitaux, plus d'arme, plus de contrat a
-- suivre : garder ces panneaux a l'ecran raconterait qu'il joue encore.
-- Restent le nom et le matricule de ceux qui sont encore en zone.
--
-- CE QUI RESTE VISIBLE
--
-- Le flux lui-meme, brouille : bruit, balayage, aberration, chute de signal
-- de temps en temps. C'est ce brouillage qui fait la difference entre « je
-- suis mort » et « on me diffuse ce que voit quelqu'un d'autre ».
--
-- AUCUNE AUTORITE
--
-- Ce controller ne demande rien au serveur. Choisir qui l'on regarde n'a
-- aucune consequence de jeu ; le serveur envoie la liste des regardables et
-- le client se contente de deplacer une camera.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Locale = require(Shared.Locale)
local Spectate = require(Shared.Spectate)
local Logger = require(Shared.Utils.Logger)

local HUD = script.Parent.Parent.UI.HUD
local Components = require(HUD.Components)
local HUDController = require(HUD.HUDController)
local Theme = require(HUD.Theme)

type ServiceContext = Types.ServiceContext
type SpectateState = Types.SpectateState
type SpectateTarget = Types.SpectateTarget

local SpectatorController = {}

SpectatorController.Name = "SpectatorController"

-- Apres CameraController (priorite 5) : quand la vue spectateur prend la
-- camera, elle doit pouvoir passer par-dessus.
SpectatorController.Priority = 20

local log = Logger.new("Spectator")
local player = Players.LocalPlayer

local connections: { RBXScriptConnection } = {}
local render: RBXScriptConnection?

local active = false
local reason = ""
local targets: { SpectateTarget } = {}
local currentId: number? = nil
local clock = 0
local nextDropout = 0
local dropout = 0

-- Elements d'ecran, crees une fois.
local gui: ScreenGui? = nil
local grain: Frame? = nil
local scanlines: { Frame } = {}
local statusLabel: TextLabel? = nil
local subjectLabel: TextLabel? = nil
local tagLabel: TextLabel? = nil
local rosterFrame: Frame? = nil
local rosterRows: { TextLabel } = {}
local hintLabel: TextLabel? = nil
local blur: BlurEffect? = nil
local desaturate: ColorCorrectionEffect? = nil

local RENDER_NAME = "BlackoutSpectate"
local ROSTER_ROWS = 6

-- Distance et hauteur de la camera derriere l'epaule du sujet.
--
-- Assez loin pour qu'on lise la scene autour de lui, assez pres pour qu'on
-- reste dans SON danger et pas au-dessus.
local BACK = 11
local UP = 3.4

-- ------------------------------------------------------------- Ecran ----

local function build()
	if gui then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("BlackoutSpectate")
	if existing then
		existing:Destroy()
	end

	local screen = Components.new("ScreenGui", {
		Name = "BlackoutSpectate",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 15,
		Enabled = false,
	}, playerGui) :: ScreenGui

	-- Nappe de bruit. Une seule Frame dont l'opacite bat legerement : moins
	-- couteux qu'un vrai grain, et suffisant pour dire « image transmise »
	-- plutot que « image regardee ».
	-- ECRAN NOIR, PAS UNE TEINTE.
	--
	-- Un mort ne doit pas continuer a voir le monde : le laisser regarder
	-- la zone qu'il vient de perdre dit exactement le contraire de ce que
	-- la mort raconte. La nappe est donc OPAQUE, et tout ce qui reste a
	-- l'ecran, c'est le brouillage.
	--
	-- Le flux d'un coequipier vivant est deja calcule dessous : le jour ou
	-- on voudra le montrer, c'est cette opacite-la qu'on baissera, et rien
	-- d'autre.
	local noise = Components.new("Frame", {
		Name = "Grain",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, screen) :: Frame

	for index = 1, 26 do
		table.insert(
			scanlines,
			Components.new("Frame", {
				-- Claires, pas sombres : sur un fond noir opaque, des lignes
				-- noires ne se voient pas. C'est la LUMIERE du balayage qui
				-- fait l'ecran de moniteur, pas son ombre.
				BackgroundColor3 = Theme.color.neutral,
				BackgroundTransparency = 0.93,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 2),
				Position = UDim2.fromScale(0, (index - 1) / 26),
				ZIndex = 3,
			}, screen) :: Frame
		)
	end

	-- Bandes noires haut et bas : cadrage de moniteur, pas de jeu.
	for _, y in { 0, 1 } do
		Components.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, y),
			Position = UDim2.fromScale(0, y),
			Size = UDim2.new(1, 0, 0, 54),
			ZIndex = 4,
		}, screen)
	end

	local status = Components.label({
		text = "",
		size = 13,
		color = Theme.color.danger,
		sizeUDim = UDim2.new(0, 520, 0, 18),
		position = UDim2.fromOffset(30, 18),
		zIndex = 6,
	}, screen)

	-- Sujet suivi : le pseudo en grand, le matricule dessous. C'est
	-- exactement ce que la compagnie affiche sur ses propres ecrans.
	local subject = Components.label({
		text = "",
		size = 30,
		font = Theme.font.hero,
		color = Theme.color.info,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.new(1, 0, 0, 36),
		position = UDim2.new(0, 0, 1, -96),
		zIndex = 6,
	}, screen)

	local tag = Components.label({
		text = "",
		size = 14,
		font = Theme.font.mono,
		color = Theme.color.neutral,
		align = Enum.TextXAlignment.Center,
		sizeUDim = UDim2.new(1, 0, 0, 18),
		position = UDim2.new(0, 0, 1, -62),
		zIndex = 6,
	}, screen)

	-- Liste des actifs encore en zone, en haut a droite.
	local roster = Components.new("Frame", {
		Name = "Roster",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -30, 0, 76),
		Size = UDim2.fromOffset(300, ROSTER_ROWS * 24),
		ZIndex = 6,
	}, screen) :: Frame

	for index = 1, ROSTER_ROWS do
		table.insert(
			rosterRows,
			Components.label({
				text = "",
				size = 15,
				color = Theme.color.dim,
				align = Enum.TextXAlignment.Right,
				sizeUDim = UDim2.new(1, 0, 0, 22),
				position = UDim2.fromOffset(0, (index - 1) * 24),
				zIndex = 6,
			}, roster)
		)
	end

	local hint = Components.label({
		text = "",
		size = 13,
		font = Theme.font.mono,
		color = Theme.color.faint,
		align = Enum.TextXAlignment.Right,
		sizeUDim = UDim2.new(0, 420, 0, 18),
		position = UDim2.new(1, -450, 1, -34),
		zIndex = 6,
	}, screen)

	gui = screen
	grain = noise
	statusLabel = status
	subjectLabel = subject
	tagLabel = tag
	rosterFrame = roster
	hintLabel = hint
end

-- ------------------------------------------------------------ Effets ----

local function effects(on: boolean)
	if on then
		if not blur then
			local created = Instance.new("BlurEffect")
			created.Name = "BlackoutSpectateBlur"
			created.Size = 0
			created.Parent = Lighting
			blur = created
		end
		if not desaturate then
			local created = Instance.new("ColorCorrectionEffect")
			created.Name = "BlackoutSpectateGrade"
			created.Saturation = -0.55
			created.Contrast = 0.12
			created.Brightness = -0.03
			created.Parent = Lighting
			desaturate = created
		end
	else
		if blur then
			blur:Destroy()
			blur = nil
		end
		if desaturate then
			desaturate:Destroy()
			desaturate = nil
		end
	end
end

-- ------------------------------------------------------------ Camera ----

local function characterOf(userId: number?): Model?
	if not userId then
		return nil
	end
	local target = Players:GetPlayerByUserId(userId)
	return if target then target.Character else nil
end

local function updateCamera(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local character = characterOf(currentId)
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		-- AUCUN SUJET. On ne laisse pas la camera en plan : on la pose en
		-- orbite lente autour du corps du joueur.
		--
		-- C'est le plan le plus juste que le jeu puisse montrer a ce
		-- moment-la : la compagnie n'a plus rien a regarder d'autre que
		-- ce qu'elle vient de perdre, et elle le regarde quand meme.
		local own = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not own or not own:IsA("BasePart") then
			return
		end

		local centre = own.Position + Vector3.new(0, 1.2, 0)
		local angle = clock * 0.12
		local eye = centre + Vector3.new(math.cos(angle) * 9, 5.5, math.sin(angle) * 9)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, centre), math.clamp(dt * 2, 0, 1))
		return
	end

	local focus = root.Position + Vector3.new(0, 1.6, 0)
	local behind = focus - root.CFrame.LookVector * BACK + Vector3.new(0, UP, 0)

	-- Petite derive laterale continue : une camera de surveillance n'est
	-- jamais parfaitement immobile, et c'est ce qui la distingue d'un
	-- verrouillage de jeu.
	local drift = math.sin(clock * 0.35) * 1.2
	behind += root.CFrame.RightVector * drift

	local wanted = CFrame.lookAt(behind, focus)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camera.CFrame:Lerp(wanted, math.clamp(dt * 3.5, 0, 1))
end

-- ------------------------------------------------------------ Affichage --

local function refresh()
	if not gui then
		return
	end

	local status = statusLabel :: TextLabel
	local subject = subjectLabel :: TextLabel
	local tag = tagLabel :: TextLabel
	local hint = hintLabel :: TextLabel

	status.Text = Components.spaced(
		Locale.t(if reason == "EXTRACTED" then "spectate.extracted" else "spectate.down")
	)
	status.TextColor3 = if reason == "EXTRACTED" then Theme.color.extraction else Theme.color.danger

	local watched = nil
	for _, target in targets do
		if target.userId == currentId then
			watched = target
		end
	end

	if watched then
		subject.Text = watched.name
		tag.Text = watched.tag
		hint.Text = Locale.t("spectate.hint")
	else
		subject.Text = Locale.t("spectate.noSignal")
		tag.Text = ""
		hint.Text = ""
	end

	for index, row in rosterRows do
		local target = targets[index]
		if target then
			row.Text = `{target.name}   {target.tag}`
			row.TextColor3 = if target.userId == currentId then Theme.color.info else Theme.color.dim
			row.Visible = true
		else
			row.Visible = false
		end
	end
end

local function step(dt: number)
	clock += dt

	updateCamera(dt)

	-- Chute de signal : l'image se voile completement une fraction de
	-- seconde, a intervalle irregulier. Rare, sinon c'est illisible.
	if clock >= nextDropout then
		nextDropout = clock + 4 + math.random() * 7
		dropout = 0.18
	end
	if dropout > 0 then
		dropout = math.max(0, dropout - dt)
	end

	-- La nappe reste opaque en permanence. Ce qui « vit », c'est le
	-- brouillage par-dessus.
	local noise = grain :: Frame
	noise.BackgroundTransparency = 0

	for index, line in scanlines do
		local offset = ((index - 1) / #scanlines + clock * 0.08) % 1
		line.Position = UDim2.fromScale(0, offset)
		line.BackgroundTransparency = if dropout > 0 then 0.72 else 0.93
	end

	if blur then
		local wanted = if dropout > 0 then 14 else 3
		blur.Size += (wanted - blur.Size) * math.clamp(dt * 8, 0, 1)
	end
end

-- ------------------------------------------------------------- Bascule --

local function setActive(on: boolean)
	if active == on then
		return
	end
	active = on

	build()
	local screen = gui :: ScreenGui
	screen.Enabled = on
	effects(on)

	if camerasController then
		pcall(function()
			(camerasController :: any).SetSuspended(on)
		end)
	end

	-- Le HUD de jeu disparait entierement : le spectateur n'a plus ni
	-- vitaux, ni arme, ni contrat.
	--
	-- On passe par son proprietaire plutot que de couper le ScreenGui a la
	-- main : sa boucle d'animation reaffirme la visibilite a chaque image
	-- et rallumerait le HUD aussitot.
	HUDController.setSuppressed(on)

	if on then
		clock = 0
		nextDropout = 2
		dropout = 0
		if not render then
			render = RunService.Heartbeat:Connect(step)
		end
		log:info(`vue spectateur active ({reason})`)
	else
		if render then
			render:Disconnect()
			render = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		log:info("retour en jeu")
	end
end

local function onState(state: SpectateState)
	if type(state) ~= "table" then
		return
	end

	reason = tostring(state.reason or "")
	targets = state.targets or {}

	-- La cible courante est reevaluee a chaque diffusion : celui qu'on
	-- regardait vient peut-etre de mourir a son tour.
	currentId = Spectate.resolve(targets, currentId)

	setActive(state.active == true)
	if active then
		refresh()
	end
end

-- -------------------------------------------------------- Cycle de vie ---

local camerasController: any? = nil

function SpectatorController.Init(context: ServiceContext)
	-- On garde la reference : la camera doit etre prevenue a chaque
	-- bascule, et la chercher a ce moment-la ferait dependre l'effet de
	-- l'ordre de demarrage.
	camerasController = context.Get("CameraController")
end

function SpectatorController.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("SpectateChanged", 10)

	if not remote or not remote:IsA("RemoteEvent") then
		log:warn("remote SpectateChanged absent : aucune vue spectateur")
		return
	end

	table.insert(connections, remote.OnClientEvent:Connect(onState))

	-- Changement de sujet. Aucune validation serveur : c'est une camera.
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or not active then
				return
			end

			local direction = 0
			if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Left then
				direction = -1
			elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
				direction = 1
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				direction = 1
			end

			if direction ~= 0 then
				currentId = Spectate.cycle(targets, currentId, direction)
				refresh()
			end
		end)
	)

	log:info("pret — en attente de sortie de raid")
end

function SpectatorController.Stop()
	setActive(false)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	RunService:UnbindFromRenderStep(RENDER_NAME)
end

return SpectatorController
