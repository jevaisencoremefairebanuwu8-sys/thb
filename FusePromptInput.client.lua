-- FusePromptInput.client.lua

print("FusePromptInput script starting")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local fusesFolder = Workspace:WaitForChild("Fuses")

print("FusePromptInput found Fuses folder")

-- ... rest of the script stays the same

local player = Players.LocalPlayer
local fusesFolder = Workspace:WaitForChild("Fuses")

local interactRemote = ReplicatedStorage:FindFirstChild("FusePickupInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "FusePickupInteract"
	interactRemote.Parent = ReplicatedStorage
end

local RANGE = 8
local currentTarget = nil

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

local function getMyPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

RunService.Heartbeat:Connect(function()
	local myPosition = getMyPosition()
	if not myPosition then
		return
	end

	local nearestFuse, nearestDist = nil, RANGE

	for _, fuseInstance in ipairs(fusesFolder:GetChildren()) do
		local mainPart = findMainPart(fuseInstance)
		if mainPart then
			local dist = (mainPart.Position - myPosition).Magnitude
			if dist <= nearestDist then
				nearestFuse = fuseInstance
				nearestDist = dist
			end
		end
	end

	currentTarget = nearestFuse
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		print("E pressed. currentTarget:", currentTarget)
		if currentTarget then
			interactRemote:FireServer(currentTarget)
			print("Fired pickup request for", currentTarget.Name)
		end
	end
end)