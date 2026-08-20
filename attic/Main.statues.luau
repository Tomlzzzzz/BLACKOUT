-- ARCHIVE — script retire de la place le 2026-08-20.
--
-- Il vivait dans ServerScriptService.Main, hors de Rojo (donc invisible
-- depuis `src/`), et s'executait a chaque partie : il posait les avatars de
-- Roblox (userId 1) et de builderman (userId 156) devant le spawn, plus une
-- statue de chaque joueur qui rejoignait. Sans rapport avec BLACKOUT.
--
-- Conserve ici au cas ou. Ne PAS remettre dans src/ : Rojo le synchroniserait
-- dans le jeu.

local Players = game:GetService("Players")

local STATUE_1_CFrame = CFrame.new(5, 5, -15)
local STATUE_2_CFrame = CFrame.new(-5, 5, -15)

local function spawnStatue(userId, cframePos)
	local success, statueModel = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)

	if success and statueModel then
		statueModel.Name = "Statue_" .. tostring(userId)
		statueModel:PivotTo(cframePos)
		for _, part in pairs(statueModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		statueModel.Parent = workspace
		print("Statue generee pour l'ID", userId)
	else
		warn("Impossible de generer la statue pour l'ID", userId)
	end
end

spawnStatue(1, STATUE_1_CFrame)
spawnStatue(156, STATUE_2_CFrame)

Players.PlayerAdded:Connect(function(player)
	spawnStatue(player.UserId, CFrame.new(0, 5, -5))
end)
