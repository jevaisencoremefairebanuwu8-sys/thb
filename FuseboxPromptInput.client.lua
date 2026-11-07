-- FuseboxPromptInput.client.lua
-- Tracks the nearest OPEN fusebox interior in range (door has its own
-- real ProximityPrompt, handled separately by Roblox).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local fuseBoxesFolder = Workspace:WaitForChild("FuseBoxes")

local interactRemote = ReplicatedStorage:FindFirstChild("FuseboxInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "FuseboxInteract"
	interactRemote.Parent = ReplicatedStorage
end

local RANGE = 8
local currentTarget = nil

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

	local nearestFusebox, nearestDist = nil, RANGE

	for _, fuseboxModel in ipairs(fuseBoxesFolder:GetChildren()) do
		if fuseboxModel:IsA("Model") then
			local isOpened = fuseboxModel:GetAttribute("Opened")
			local interior = fuseboxModel:FindFirstChild("Interior")
			if isOpened and interior then
				local dist = (interior.Position - myPosition).Magnitude
				if dist <= nearestDist then
					nearestFusebox = fuseboxModel
					nearestDist = dist
				end
			end
		end
	end

	currentTarget = nearestFusebox
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		print("[FuseboxInput] E pressed. currentTarget:", currentTarget)
		if currentTarget then
			interactRemote:FireServer(currentTarget)
		end
	end
end)