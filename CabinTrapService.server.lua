-- CabinTrapService.server.lua
-- Watches every player's (and the TestDummy's) HealthState -- the
-- moment it becomes Downed, from ANY source (base attack, Scarecrow's
-- Exposed hit, Mark Maker's Mark, anything added later), automatically
-- traps them in a Cabin via CabinService. This is what makes the whole
-- system fully automatic and decoupled from whichever killer caused it
-- -- nothing about Scarecrow or Mark Maker needs to be touched.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Adjust this path if CabinService.lua doesn't live next to this script
-- in your actual Rojo tree.
local CabinService = require(script.Parent.CabinService)

local DOWNED_ANIMATION_DELAY = 2 -- seconds, leaves room for a downed animation before the teleport

local function onHealthStateChanged(target)
	if target:GetAttribute("HealthState") == "Downed" then
		task.delay(DOWNED_ANIMATION_DELAY, function()
			if target:GetAttribute("HealthState") == "Downed" then
				CabinService.TrapDowned(target)
			end
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

-- Also watch the TestDummy, for solo testing.
local dummy = Workspace:FindFirstChild("TestDummy")
if dummy then
	dummy:GetAttributeChangedSignal("HealthState"):Connect(function()
		onHealthStateChanged(dummy)
	end)
end

print("CabinTrapService loaded.")