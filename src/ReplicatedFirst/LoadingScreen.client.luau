--!strict
-- Ecran de chargement.
--
-- POURQUOI IL EXISTE, ET CE QU'IL EMPECHE
--
-- Ce n'est pas un habillage. Le personnage apparait des que le serveur le
-- demande, sans attendre que la carte soit arrivee chez le client : sur une
-- vraie carte, le joueur se retrouve quelques secondes dans le vide, tombe,
-- ou voit le decor se materialiser autour de lui. Cet ecran tient jusqu'a ce
-- que le sol existe REELLEMENT sous ses pieds.
--
-- LES QUATRE ETAPES SONT DES MESURES, PAS UNE ANIMATION
--
--   LIAISON      le moteur a fini de repliquer (`game:IsLoaded`)
--   SECTEUR      la carte est arrivee et il y a du sol sous le point d'appari-
--                tion (sonde verticale reelle)
--   EQUIPEMENT   les images du HUD sont prechargees, le HUD est monte
--   DEPLOIEMENT  le personnage est vivant et jouable
--
-- Une barre qui avance sans rien mesurer est pire que pas de barre : elle
-- apprend au joueur que l'affichage ment, exactement comme le compte a
-- rebours de contrat qui ne fermait rien.
--
-- IL NE BLOQUE JAMAIS INDEFINIMENT
--
-- Chaque etape a un delai maximal. Passe ce delai on continue quand meme, en
-- le signalant dans la console : un joueur coince devant un ecran de
-- chargement parce qu'une sonde n'a pas abouti est un bug bien pire que
-- celui qu'on essaie d'eviter.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- On retire l'ecran Roblox par defaut le plus tot possible, avant meme de
-- construire le notre : sinon les deux se chevauchent une fraction de
-- seconde et le raccord se voit.
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

-- ------------------------------------------------------------ Reglages ---
--
-- Volontairement EN DUR ici, contrairement au reste du projet.
--
-- Ce script tourne avant que quoi que ce soit ne soit replique :
-- `ReplicatedStorage.Shared` n'existe pas encore quand il demarre. Aller y
-- chercher une config obligerait a attendre precisement ce qu'on est en
-- train d'attendre.

local STAGE_TIMEOUT = 20
local TOTAL_TIMEOUT = 45

-- Distance de la sonde de sol, en studs. Genereux : le personnage peut
-- apparaitre en hauteur sur une carte a etages.
local FLOOR_PROBE = 400

local COLOR = {
	void = Color3.fromRGB(8, 9, 10),
	panel = Color3.fromRGB(13, 14, 16),
	info = Color3.fromRGB(236, 237, 238),
	neutral = Color3.fromRGB(138, 145, 154),
	dim = Color3.fromRGB(92, 98, 106),
	faint = Color3.fromRGB(62, 67, 73),
	accent = Color3.fromRGB(232, 166, 62),
	done = Color3.fromRGB(74, 196, 118),
}

local ICONS = { 105352149505029, 91714244327633, 116844880554266 }

-- Libelles. Le francais suit la meme regle que le reste du jeu, mais on ne
-- peut pas charger le module de localisation ici : on se limite donc a la
-- langue du client Roblox, lue directement.
local FRENCH = (function(): boolean
	local ok, id = pcall(function()
		return player.LocaleId
	end)
	return ok and typeof(id) == "string" and string.sub(id, 1, 2):lower() == "fr"
end)()

local TEXT = if FRENCH
	then {
		company = "MERIDIAN / SUPERVISION",
		subtitle = "PREPARATION DU DEPLOIEMENT",
		stages = { "LIAISON", "SECTEUR", "EQUIPEMENT", "DEPLOIEMENT" },
		waiting = "EN ATTENTE",
		ready = "PRET",
		hold = "Ne coupez pas la liaison.",
		late = "Liaison degradee. Deploiement forc\u{e9}.",
	}
	else {
		company = "MERIDIAN / OVERSIGHT",
		subtitle = "DEPLOYMENT PREPARATION",
		stages = { "UPLINK", "SECTOR", "EQUIPMENT", "DEPLOYMENT" },
		waiting = "STANDBY",
		ready = "READY",
		hold = "Do not drop the uplink.",
		late = "Uplink degraded. Deployment forced.",
	}

-- ------------------------------------------------------------- Ecran -----

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(class)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local gui = new("ScreenGui", {
	Name = "BlackoutLoading",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 100,
}, playerGui)

local backdrop = new("Frame", {
	BackgroundColor3 = COLOR.void,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 1,
}, gui)

-- Balayage : meme signature visuelle que le moniteur vital et le rapport de
-- fin. Le joueur doit reconnaitre l'appareil avant meme d'etre en jeu.
local scanlines = {}
for index = 1, 22 do
	table.insert(
		scanlines,
		new("Frame", {
			BackgroundColor3 = COLOR.neutral,
			BackgroundTransparency = 0.94,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2),
			Position = UDim2.fromScale(0, (index - 1) / 22),
			ZIndex = 2,
		}, backdrop)
	)
end

local card = new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(520, 320),
	ZIndex = 4,
}, backdrop)

local function label(props: { [string]: any }, parent: Instance): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.RobotoCondensed,
		TextColor3 = COLOR.info,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
	}
	for key, value in props do
		defaults[key] = value
	end
	return new("TextLabel", defaults, parent)
end

local function spaced(text: string): string
	return (text:gsub(".", "%0 "):gsub("%s+$", ""))
end

label({
	Text = spaced(TEXT.company),
	TextSize = 15,
	TextColor3 = COLOR.neutral,
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.fromOffset(0, 0),
}, card)

label({
	Text = spaced(TEXT.subtitle),
	TextSize = 11,
	TextColor3 = COLOR.dim,
	Size = UDim2.new(1, 0, 0, 16),
	Position = UDim2.fromOffset(0, 22),
}, card)

new("Frame", {
	BackgroundColor3 = COLOR.accent,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.fromOffset(0, 52),
	ZIndex = 5,
}, card)

-- Les quatre etapes, en colonne. Chacune porte son propre etat : c'est ce
-- qui distingue « il se passe quelque chose » de « on attend le secteur ».
type Row = { name: TextLabel, state: TextLabel, tick: Frame }

local rows: { Row } = {}
for index, name in TEXT.stages do
	local top = 74 + (index - 1) * 30

	local tick = new("Frame", {
		BackgroundColor3 = COLOR.faint,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromOffset(0, top + 7),
		ZIndex = 5,
	}, card)

	table.insert(rows, {
		tick = tick,
		name = label({
			Text = spaced(name),
			TextSize = 13,
			TextColor3 = COLOR.dim,
			Size = UDim2.fromOffset(300, 20),
			Position = UDim2.fromOffset(20, top),
		}, card),
		state = label({
			Text = TEXT.waiting,
			TextSize = 12,
			Font = Enum.Font.RobotoMono,
			TextColor3 = COLOR.faint,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(1, -20, 0, 20),
			Position = UDim2.fromOffset(20, top),
		}, card),
	})
end

-- Barre de progression : quatre segments, un par etape. Pas de pourcentage
-- invente — un segment s'allume quand une etape est REELLEMENT franchie.
local barTop = 74 + #TEXT.stages * 30 + 18
local segments: { Frame } = {}
for index = 1, #TEXT.stages do
	local width = 1 / #TEXT.stages
	table.insert(
		segments,
		new("Frame", {
			BackgroundColor3 = COLOR.faint,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Size = UDim2.new(width, -4, 0, 3),
			Position = UDim2.new((index - 1) * width, 2, 0, barTop),
			ZIndex = 5,
		}, card)
	)
end

local footer = label({
	Text = TEXT.hold,
	TextSize = 13,
	TextColor3 = COLOR.faint,
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.fromOffset(0, barTop + 18),
}, card)

-- ---------------------------------------------------------- Animation ----

local clock = 0
local heartbeat = RunService.Heartbeat:Connect(function(dt)
	clock += dt
	for index, line in scanlines do
		local offset = ((index - 1) / #scanlines + clock * 0.05) % 1
		line.Position = UDim2.fromScale(0, offset)
	end
	-- Le point de l'etape en cours bat. Le seul mouvement de l'ecran, et il
	-- dit « on attend encore », pas « ca charge ».
	local pulse = 0.5 + math.sin(clock * 4) * 0.5
	for _, row in rows do
		if row.state.Text == TEXT.waiting and row.name.TextColor3 == COLOR.info then
			row.tick.BackgroundTransparency = pulse * 0.7
		end
	end
end)

-- ------------------------------------------------------------ Etapes -----

local function beginStage(index: number)
	local row = rows[index]
	if row then
		row.name.TextColor3 = COLOR.info
		row.tick.BackgroundColor3 = COLOR.accent
	end
end

local function completeStage(index: number, ok: boolean)
	local row = rows[index]
	if row then
		row.state.Text = if ok then TEXT.ready else "—"
		row.state.TextColor3 = if ok then COLOR.done else COLOR.dim
		row.tick.BackgroundColor3 = if ok then COLOR.done else COLOR.faint
		row.tick.BackgroundTransparency = 0
		row.name.TextColor3 = COLOR.neutral
	end
	local segment = segments[index]
	if segment then
		segment.BackgroundColor3 = if ok then COLOR.done else COLOR.faint
		segment.BackgroundTransparency = if ok then 0 else 0.6
	end
end

local startedAt = os.clock()

-- Attend qu'une condition soit vraie. Renvoie false sur delai depasse — et
-- l'appelant CONTINUE quand meme.
local function await(index: number, predicate: () -> boolean): boolean
	beginStage(index)

	local deadline = os.clock() + STAGE_TIMEOUT
	while os.clock() < deadline do
		if os.clock() - startedAt > TOTAL_TIMEOUT then
			break
		end
		local ok, result = pcall(predicate)
		if ok and result then
			completeStage(index, true)
			return true
		end
		task.wait(0.1)
	end

	completeStage(index, false)
	warn(`[Chargement] etape {index} ({TEXT.stages[index]}) : delai depasse, on continue`)
	return false
end

-- --- 1. liaison ----------------------------------------------------------

await(1, function()
	return game:IsLoaded()
end)

-- --- 2. secteur ----------------------------------------------------------
--
-- LE COEUR DE L'ECRAN. On ne se contente pas de compter des instances : on
-- sonde verticalement sous le personnage pour verifier qu'il y a quelque
-- chose sur quoi se poser. C'est ce test-la qui empeche d'apparaitre dans le
-- vide pendant que la carte finit d'arriver.

await(2, function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { character :: Instance }

	local hit = Workspace:Raycast(
		root.Position + Vector3.new(0, 8, 0),
		Vector3.new(0, -FLOOR_PROBE, 0),
		parameters
	)
	return hit ~= nil
end)

-- --- 3. equipement -------------------------------------------------------

await(3, function()
	if not playerGui:FindFirstChild("BlackoutHud") then
		return false
	end
	if not ReplicatedStorage:FindFirstChild("Remotes") then
		return false
	end
	return true
end)

-- Prechargement des pictogrammes. Hors de la condition d'etape : un asset
-- modere ou retire ne doit pas retenir le joueur devant l'ecran.
task.spawn(function()
	local assets = {}
	for _, id in ICONS do
		table.insert(assets, `rbxassetid://{id}`)
	end
	pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)
end)

-- --- 4. deploiement ------------------------------------------------------

local forced = not await(4, function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and (humanoid :: Humanoid).Health > 0
end)

if forced then
	footer.Text = TEXT.late
	footer.TextColor3 = COLOR.accent
end

-- ------------------------------------------------------------ Retrait ----
--
-- Fondu, pas coupure. Le HUD joue sa propre sequence d'allumage juste
-- derriere : un raccord net entre les deux ferait clignoter l'ecran.

task.wait(0.35)

local fade = 0
while fade < 1 do
	fade = math.min(1, fade + task.wait(1 / 60) * 1.8)
	backdrop.BackgroundTransparency = fade
	card.Position = UDim2.new(0.5, 0, 0.5, math.floor(-fade * 14))
	for _, line in scanlines do
		line.BackgroundTransparency = 0.94 + fade * 0.06
	end
	for _, row in rows do
		row.name.TextTransparency = fade
		row.state.TextTransparency = fade
		row.tick.BackgroundTransparency = fade
	end
	for _, segment in segments do
		segment.BackgroundTransparency = math.max(segment.BackgroundTransparency, fade)
	end
	for _, child in card:GetChildren() do
		if child:IsA("TextLabel") then
			child.TextTransparency = fade
		elseif child:IsA("Frame") then
			child.BackgroundTransparency = math.max(child.BackgroundTransparency, fade)
		end
	end
end

heartbeat:Disconnect()
gui:Destroy()
