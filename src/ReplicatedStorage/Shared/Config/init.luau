--!strict
-- Agregateur de config. Tout ce qui se tune pendant le dev passe ici,
-- jamais en dur dans un service.

local Config = {}

Config.Economy = require(script.EconomyConfig)
Config.Loot = require(script.LootConfig)
Config.Enemies = require(script.EnemyConfig)
Config.Extraction = require(script.ExtractionConfig)
Config.Threat = require(script.ThreatConfig)
Config.Player = require(script.PlayerConfig)
Config.Data = require(script.DataConfig)
Config.Monetization = require(script.MonetizationConfig)
Config.Analytics = require(script.AnalyticsConfig)
Config.Weapons = require(script.WeaponConfig)
Config.Handler = require(script.HandlerConfig)
Config.Match = require(script.MatchConfig)
Config.Camera = require(script.CameraConfig)
Config.Vitals = require(script.VitalsConfig)
Config.World = require(script.WorldConfig)
Config.Contracts = require(script.ContractConfig)
Config.Loadout = require(script.LoadoutConfig)
Config.Hud = require(script.HudConfig)
Config.Debrief = require(script.DebriefConfig)

return Config
