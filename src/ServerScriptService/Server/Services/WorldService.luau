--!strict
-- Zone, heure et meteo.
--
-- Alimente le bandeau superieur droit du HUD : « NORTH DISTRICT / 17:42 /
-- RAIN ». Trois lectures d'ambiance, mais elles ne sont pas decoratives —
-- elles disent que la ville continue d'exister hors du champ de vision, et
-- l'heure qui avance rappelle qu'on ne reste pas indefiniment.
--
-- La meteo pilote reellement Lighting : brouillard et luminosite changent.
-- Un bandeau qui annonce RAIN sur un ciel degage serait exactement le genre
-- d'affichage qui apprend au joueur a ne plus lire son HUD.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local WeightedRandom = require(Shared.Utils.WeightedRandom)

type ServiceContext = Types.ServiceContext

local WorldService = {}

WorldService.Name = "WorldService"
WorldService.Priority = 28

-- Changement de regime meteo. Le commanditaire le relaie : c'est une
-- information d'environnement reelle, pas du remplissage.
WorldService.WeatherChanged = Signal.new()

local log = Logger.new("World")
local ctx: ServiceContext?

local heartbeat: RBXScriptConnection?
local accumulator = 0

local clock = Config.World.startClock
local weather = Config.World.weathers[1]
local weatherUntil = 0
local districtOf: { [Player]: string } = {}

-- ------------------------------------------------------------ District ---

local function districtFor(player: Player): string
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return Config.World.defaultDistrict
	end

	local position = root.Position
	local best, bestDistance = nil, math.huge

	for _, district in Config.World.districts do
		local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(district.center.X, 0, district.center.Z)).Magnitude
		if distance <= district.radius and distance < bestDistance then
			best = district.name
			bestDistance = distance
		end
	end

	return best or Config.World.defaultDistrict
end

-- ------------------------------------------------------------- Meteo ----

local function applyWeather()
	Lighting.FogEnd = weather.fog
	Lighting.Brightness = weather.brightness
	Lighting.ClockTime = clock
end

local function rollWeather(now: number)
	-- Les entrees de config portent deja leur `weight` : WeightedRandom les
	-- prend telles quelles, pas enveloppees.
	local entries = {}
	for _, candidate in Config.World.weathers do
		-- On ne retire jamais deux fois le meme regime d'affilee : la meteo
		-- doit se remarquer quand elle change.
		if candidate.name ~= weather.name then
			table.insert(entries, candidate)
		end
	end

	local picked = WeightedRandom.pick(entries)
	if picked then
		weather = picked
	end

	local span = Config.World.weatherDuration
	weatherUntil = now + span.min + math.random() * (span.max - span.min)
	applyWeather()
	Signal.fire(WorldService.WeatherChanged, weather.name)
	log:info(`meteo -> {weather.name}`)
end

-- ---------------------------------------------------------- Diffusion ---

local function push(player: Player)
	local context = ctx
	local remote = context and context.Remotes:FindFirstChild("WorldInfoChanged")
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end

	local info: Types.WorldInfo = {
		district = districtOf[player] or Config.World.defaultDistrict,
		weather = weather.name,
		clock = clock,
	}
	remote:FireClient(player, info)
end

function WorldService.GetInfo(player: Player): Types.WorldInfo
	return {
		district = districtOf[player] or Config.World.defaultDistrict,
		weather = weather.name,
		clock = clock,
	}
end

-- ------------------------------------------------------------- Boucle ---

local function tick(dt: number)
	local now = os.clock()

	-- L'heure avance. Elle boucle dans la plage de nuit : la ville ne voit
	-- jamais le jour, c'est le postulat du blackout.
	clock += Config.World.clockPerMinute * (dt / 60)
	local range = Config.World.clockRange
	if clock >= range.max then
		clock = range.min
	end
	Lighting.ClockTime = if clock >= 24 then clock - 24 else clock

	if now >= weatherUntil then
		rollWeather(now)
	end

	for _, player in Players:GetPlayers() do
		local district = districtFor(player)
		local changed = districtOf[player] ~= district
		districtOf[player] = district

		-- Diffusion a chaque tick de toute facon : l'heure avance en continu
		-- et le bandeau doit la suivre. `changed` ne sert qu'a journaliser.
		if changed then
			log:info(`{player.Name} -> {district}`)
		end
		push(player)
	end
end

-- -------------------------------------------------------- Cycle de vie ---

function WorldService.Init(context: ServiceContext)
	ctx = context
end

function WorldService.Start()
	rollWeather(os.clock())
	applyWeather()

	Players.PlayerAdded:Connect(function(player)
		districtOf[player] = Config.World.defaultDistrict
		task.defer(push, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		districtOf[player] = nil
	end)

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.World.pushRate then
			return
		end
		local step = accumulator
		accumulator = 0

		local ok, err = pcall(tick, step)
		if not ok then
			log:error(`tick a leve -> {err}`)
		end
	end)

	log:info(`pret — {#Config.World.districts} districts, meteo {weather.name}`)
end

function WorldService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	table.clear(districtOf)
end

return WorldService
