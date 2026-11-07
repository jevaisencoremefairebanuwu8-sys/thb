-- PlayerStateService.lua
-- Tracks each survivor's health state (Healthy, Injured, Downed, Dead, Escaped).
-- Stored as a Player Attribute so it replicates automatically to every client.

local Players = game:GetService("Players")

local PlayerStateService = {}

local States = {
	Healthy = "Healthy",
	Injured = "Injured",
	Downed = "Downed",
	Dead = "Dead",
	Hooked = "Hooked",
	Escaped = "Escaped",
}
PlayerStateService.States = States

local function initializePlayer(player)
	player:SetAttribute("HealthState", States.Healthy)
	player:SetAttribute("DownedProgress", 0)

	player.CharacterAdded:Connect(function()
		player:SetAttribute("HealthState", States.Healthy)
		player:SetAttribute("DownedProgress", 0)
	end)
end

Players.PlayerAdded:Connect(initializePlayer)
for _, player in ipairs(Players:GetPlayers()) do
	initializePlayer(player)
end

function PlayerStateService.GetState(player)
	return player:GetAttribute("HealthState") or States.Healthy
end

function PlayerStateService.SetState(player, newState)
	if not States[newState] then
		warn("Invalid state: " .. tostring(newState))
		return
	end
	player:SetAttribute("HealthState", newState)
	print(player.Name .. " is now " .. newState)
end

return PlayerStateService