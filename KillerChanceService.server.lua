-- KillerChanceService.server.lua
-- Tracks each player's KillerChance (0-3): their relative odds of being
-- picked as killer each round. 0 excludes them entirely, 1 is
-- default/normal odds, 2/3 make them increasingly more likely.
-- LobbyService.server.lua reads this attribute when picking the
-- round's killer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_KILLER_CHANCE = 1
local VALID_VALUES = { [0] = true, [1] = true, [2] = true, [3] = true }

local killerChanceRemote = ReplicatedStorage:FindFirstChild("SetKillerChance")
if not killerChanceRemote then
	killerChanceRemote = Instance.new("RemoteEvent")
	killerChanceRemote.Name = "SetKillerChance"
	killerChanceRemote.Parent = ReplicatedStorage
end

local function onPlayerAdded(player)
	if player:GetAttribute("KillerChance") == nil then
		player:SetAttribute("KillerChance", DEFAULT_KILLER_CHANCE)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

killerChanceRemote.OnServerEvent:Connect(function(player, value)
	if VALID_VALUES[value] then
		player:SetAttribute("KillerChance", value)
	end
end)

print("KillerChanceService loaded.")