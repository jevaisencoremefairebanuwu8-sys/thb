-- FusePickup.server.lua
-- Lets players pick up fuses scattered around the map (custom E prompt).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FuseService = require(script.Parent.FuseService)

local fusesFolder = Workspace:WaitForChild("Fuses")

local interactRemote = ReplicatedStorage:FindFirstChild("FusePickupInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "FusePickupInteract"
	interactRemote.Parent = ReplicatedStorage
end

local MAX_PICKUP_DISTANCE = 8

local function findMainPart(fuseInstance)
	if fuseInstance:IsA("BasePart") then
		return fuseInstance
	end
	for _, descendant in ipairs(fuseInstance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

interactRemote.OnServerEvent:Connect(function(player, fuseInstance)
	if player:GetAttribute("IsKiller") then
		return
	end
	print("FusePickup received request for:", fuseInstance, "from", player.Name)
	if not fuseInstance or not fuseInstance:IsDescendantOf(fusesFolder) then
		print("  Rejected: not a valid fuse in the folder")
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local mainPart = findMainPart(fuseInstance)
	if not root or not mainPart then
		print("  Rejected: missing root or mainPart")
		return
	end

	local distance = (root.Position - mainPart.Position).Magnitude
	print("  Distance:", distance)
	if distance > MAX_PICKUP_DISTANCE then
		print("  Rejected: too far")
		return
	end

	local success = FuseService.PickUp(player, fuseInstance)
	print("  PickUp result:", success)
end)

-- === Bot support ===
-- Bots can't call FuseService.PickUp directly -- it fires a client remote
-- (FireClient) that requires a real Player, which bots aren't. This
-- bridge mirrors the same validation and the same "remove from world"
-- behavior, but skips the client-facing parts entirely.
local botPickupFuse = Instance.new("BindableFunction")
botPickupFuse.Name = "BotPickupFuse"
botPickupFuse.Parent = script

botPickupFuse.OnInvoke = function(fuseInstance, botCharacter)
	if not fuseInstance or not fuseInstance:IsDescendantOf(fusesFolder) then
		return false -- already taken by someone else, or invalid
	end
	local root = botCharacter and botCharacter:FindFirstChild("HumanoidRootPart")
	local mainPart = findMainPart(fuseInstance)
	if not root or not mainPart then
		return false
	end
	if (root.Position - mainPart.Position).Magnitude > MAX_PICKUP_DISTANCE then
		return false
	end

	fuseInstance.Parent = nil -- matches FuseService.PickUp's own removal-from-world behavior
	return true
end

local getFusePosition = Instance.new("BindableFunction")
getFusePosition.Name = "GetFusePosition"
getFusePosition.Parent = script

getFusePosition.OnInvoke = function(fuseInstance)
	local mainPart = findMainPart(fuseInstance)
	if mainPart then
		return mainPart.Position
	end
	return nil
end
-- === End bot support ===

print("FusePickup loaded (custom prompt). Tracking " .. #fusesFolder:GetChildren() .. " fuse(s).")