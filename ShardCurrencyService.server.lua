-- ShardCurrencyService.server.lua
-- Minimal starting point for the Shards currency: gives each player a
-- "Shards" attribute (defaulting to 0) so the counter in LobbyUI has
-- something real to display.
--
-- Nothing earns or spends Shards yet -- this is just the data backbone.
-- Future systems (shop purchases, match rewards, etc.) can read/modify
-- it via player:SetAttribute("Shards", newAmount). Also doesn't persist
-- between sessions yet (no DataStore) -- add that here when you're
-- ready to make Shards actually save.

local Players = game:GetService("Players")

local STARTING_SHARDS = 0

local function onPlayerAdded(player)
	if player:GetAttribute("Shards") == nil then
		player:SetAttribute("Shards", STARTING_SHARDS)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end