-- GeneratorPromptInput.client.lua
-- Tracks the nearest generator in range (no visual label) and
-- sends hold start/stop signals to repair it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local generatorsFolder = Workspace:WaitForChild("Generators")

local interactRemote = ReplicatedStorage:FindFirstChild("GeneratorInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "GeneratorInteract"
	interactRemote.Parent = ReplicatedStorage
end

local RANGE = 10
local currentTarget = nil
local isHoldingE = false

local function findMainPart(generatorModel)
	for _, descendant in ipairs(generatorModel:GetDescendants()) do
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

	local nearestGenerator, nearestDist = nil, RANGE

	for _, generatorModel in ipairs(generatorsFolder:GetChildren()) do
		if generatorModel:IsA("Model") and not generatorModel:GetAttribute("Completed") then
			local mainPart = findMainPart(generatorModel)
			if mainPart then
				local dist = (mainPart.Position - myPosition).Magnitude
				if dist <= nearestDist then
					nearestGenerator = generatorModel
					nearestDist = dist
				end
			end
		end
	end

	if nearestGenerator ~= currentTarget then
		if isHoldingE and currentTarget then
			interactRemote:FireServer(currentTarget, "stop")
			isHoldingE = false
		end
		currentTarget = nearestGenerator
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