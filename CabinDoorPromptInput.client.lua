-- CabinDoorPromptInput.client.lua
-- Hold E near a Cabin's door to rescue whoever's trapped inside.
-- Replaces HookPromptInput.client.lua (Blood Circle rescue).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local cabinsFolder = Workspace:WaitForChild("Cabins")

local cabinRescueRemote = ReplicatedStorage:FindFirstChild("CabinRescueInteract")
if not cabinRescueRemote then
	cabinRescueRemote = Instance.new("RemoteEvent")
	cabinRescueRemote.Name = "CabinRescueInteract"
	cabinRescueRemote.Parent = ReplicatedStorage
end

local RANGE = 8
local isHolding = false
local currentTarget = nil -- the trapped Player/dummy Instance, not the cabin itself

local function getMyPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

local function getDoorPosition(cabinModel)
	local door = cabinModel:FindFirstChild("Door", true)
	if not door then
		return nil
	end
	if door:IsA("BasePart") then
		return door.Position
	elseif door:IsA("Attachment") then
		return door.WorldPosition
	elseif door:IsA("Model") then
		return door:GetPivot().Position
	end
	return nil
end

local function stopHolding()
	if isHolding and currentTarget then
		cabinRescueRemote:FireServer(currentTarget, "stop")
	end
	isHolding = false
end

RunService.Heartbeat:Connect(function()
	local myPosition = getMyPosition()
	if not myPosition then
		if isHolding then
			stopHolding()
		end
		currentTarget = nil
		return
	end

	local nearestTarget, nearestDist = nil, RANGE

	for _, cabinModel in ipairs(cabinsFolder:GetChildren()) do
		if cabinModel:IsA("Model") then
			local trappedName = cabinModel:GetAttribute("TrappedPlayerName")
			local doorPosition = trappedName and getDoorPosition(cabinModel)
			if doorPosition then
				local dist = (doorPosition - myPosition).Magnitude
				if dist <= nearestDist then
					local trappedPlayer = Players:FindFirstChild(trappedName)
					local trappedInstance = trappedPlayer or Workspace:FindFirstChild(trappedName)
					if trappedInstance then
						nearestTarget = trappedInstance
						nearestDist = dist
					end
				end
			end
		end
	end

	if nearestTarget ~= currentTarget then
		stopHolding()
		currentTarget = nearestTarget
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.E and currentTarget and not isHolding then
		isHolding = true
		cabinRescueRemote:FireServer(currentTarget, "start")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.E then
		stopHolding()
	end
end)