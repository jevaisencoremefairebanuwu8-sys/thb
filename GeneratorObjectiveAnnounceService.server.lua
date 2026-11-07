-- GeneratorObjectiveAnnounceService.server.lua
-- Watches StageManager for the Generators stage becoming active (this
-- fires exactly once when it starts — either as the round's first stage,
-- or after the previous stage is cleared — so no debounce/reset needed).
-- Shows the "NEW OBJECTIVE" banner to every survivor. Killer is exempt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StageManager = require(ServerScriptService.Server.StageManager)
local ObjectiveAnnouncementService = require(ReplicatedStorage.Shared.ObjectiveAnnouncementService)

StageManager.StageChanged.Event:Connect(function(nextStage)
	print("GeneratorObjectiveAnnounceService: StageChanged fired with nextStage =", nextStage)

	if nextStage ~= "Generators" then
		print("  -> not the Generators stage, skipping")
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("IsKiller") then
			print("  -> announcing to", player.Name)
			ObjectiveAnnouncementService.AnnouncePlayer(
				player,
				"NEW OBJECTIVE",
				"LOCATE GENERATORS AND POWER THEM UP"
			)
		else
			print("  -> skipping killer", player.Name)
		end
	end
end)

print("GeneratorObjectiveAnnounceService loaded.")
return true