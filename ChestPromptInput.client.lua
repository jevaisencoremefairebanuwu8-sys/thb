-- ChestPromptInput.client.lua
-- Tracks the nearest un-searched chest in range (no visual label) and
-- sends hold start/stop signals to search it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local chestsFolder = Workspace:WaitForChild("Chests")

local interactRemote = ReplicatedStorage:FindFirstChild("ChestInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "ChestInteract"
	interactRemote.Parent = ReplicatedStorage
end

local RANGE = 8
local currentTarget = nil
local isHoldingE = false

local function findMainPart(chestModel)
	for _, descendant in ipairs(chestModel:GetDescendants()) do
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

	local nearestChest, nearestDist = nil, RANGE

	for _, chestModel in ipairs(chestsFolder:GetChildren()) do
		if chestModel:IsA("Model") and not chestModel:GetAttribute("Completed") then
			local mainPart = findMainPart(chestModel)
			if mainPart then
				local dist = (mainPart.Position - myPosition).Magnitude
				if dist <= nearestDist then
					nearestChest = chestModel
					nearestDist = dist
				end
			end
		end
	end

	if nearestChest ~= currentTarget then
		if isHoldingE and currentTarget then
			interactRemote:FireServer(currentTarget, "stop")
			isHoldingE = false
		end
		currentTarget = nearestChest
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.E and currentTarget then
		isHoldingE = true
		interactRemote:FireServer(currentTarget, "start")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.E and isHoldingE then
		isHoldingE = false
		if currentTarget then
			interactRemote:FireServer(currentTarget, "stop")
		end
	end
end)