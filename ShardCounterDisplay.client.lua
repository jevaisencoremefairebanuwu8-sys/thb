-- ShardCounterDisplay.client.lua
-- Keeps LobbyUI > Other > Frame > ShardAmount in sync with the player's
-- "Shards" attribute (set server-side by ShardCurrencyService).

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("LobbyUI") -- adjust if named differently
local otherFolder = screenGui:WaitForChild("Other")
local shardFrame = otherFolder:WaitForChild("Frame")
local shardAmount = shardFrame:WaitForChild("ShardAmount")

local function updateShardDisplay()
	shardAmount.Text = tostring(player:GetAttribute("Shards") or 0)
end

player:GetAttributeChangedSignal("Shards"):Connect(updateShardDisplay)
updateShardDisplay()