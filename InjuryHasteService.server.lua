-- InjuryHasteService.server.lua
-- Any Survivor who becomes Injured -- regardless of which killer or
-- ability caused it -- gets a 50% speed boost for 3 seconds afterward.
--
-- This reacts purely to the HealthState attribute, which
-- PlayerStateService already sets for every source of damage (the base
-- attack, Scarecrow's Exposed hit, Mark Maker's Mark, and anything
-- added later). Nothing about Scarecrow or Mark Maker needs to be
-- touched for this to work.

local Players = game:GetService("Players")

local HASTE_DURATION = 3

local function onHealthStateChanged(player)
	if player:GetAttribute("HealthState") == "Injured" then
		player:SetAttribute("IsHasted", true)
		task.delay(HASTE_DURATION, function()
			player:SetAttribute("IsHasted", false)
		end)
	end
end

local function onPlayerAdded(player)
	player:GetAttributeChangedSignal("HealthState"):Connect(function()
		onHealthStateChanged(player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end