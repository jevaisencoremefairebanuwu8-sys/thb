-- FuseboxObjectiveAnnounceService.server.lua
-- Watches StageManager for the Fuseboxes stage becoming active (fires
-- exactly once when it starts — either as the round's first stage, or
-- after the previous stage is cleared — so no debounce/reset needed).
-- Shows the "NEW OBJECTIVE" banner to every survivor. Killer is exempt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StageManager = require(ServerScriptService.Server.StageManager)
local ObjectiveAnnouncementService = require(ReplicatedStorage.Shared.ObjectiveAnnouncementService)

StageManager.StageChanged.Event:Connect(function(nextStage)
	print("FuseboxObjectiveAnnounceService: StageChanged fired with nextStage =", nextStage)

	if nextStage ~= "Fuseboxes" then
		print("  -> not the Fuseboxes stage, skipping")
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("IsKiller") then
			print("  -> announcing to", player.Name)
			ObjectiveAnnouncementService.AnnouncePlayer(
				player,
				"NEW OBJECTIVE",
				"FIND FUSES AND POWER THE FUSEBOXES"
			)
		else
			print("  -> skipping killer", player.Name)
		end
	end
end)

print("FuseboxObjectiveAnnounceService loaded.")
return true