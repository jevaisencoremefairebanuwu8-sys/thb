-- EscapeObjectiveAnnounceService.server.lua
-- Watches StageManager for all objectives being complete (StageChanged
-- fires with nextStage == nil — the same signal EscapeService uses to open
-- the gates). Shows the "ESCAPE" banner to every survivor. Killer is exempt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StageManager = require(ServerScriptService.Server.StageManager)
local ObjectiveAnnouncementService = require(ReplicatedStorage.Shared.ObjectiveAnnouncementService)

StageManager.StageChanged.Event:Connect(function(nextStage)
	if nextStage ~= nil then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("IsKiller") then
			ObjectiveAnnouncementService.AnnouncePlayer(
				player,
				"ESCAPE",
				"LOCATE THE BUNKER AND ESCAPE THROUGH IT"
			)
		end
	end
end)

print("EscapeObjectiveAnnounceService loaded.")
return true