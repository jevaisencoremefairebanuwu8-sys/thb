-- PalletPromptInput.client.lua
-- Tracks the nearest interactable pallet (drop for survivors, break for
-- killer) and sends E press/hold signals.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local palletsFolder = Workspace:WaitForChild("Pallets")

local interactRemote = ReplicatedStorage:FindFirstChild("PalletInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "PalletInteract"
	interactRemote.Parent = ReplicatedStorage
end

local RANGE = 8
local currentTarget = nil
local isHoldingE = false

local function findMainPart(palletModel)
	for _, descendant in ipairs(palletModel:GetDescendants()) do
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

	local isKiller = player:GetAttribute("IsKiller")
	local nearestPallet, nearestDist = nil, RANGE

	for _, palletModel in ipairs(palletsFolder:GetChildren()) do
		if palletModel:IsA("Model") then
			local isDropped = palletModel:GetAttribute("Dropped")
			local isBroken = palletModel:GetAttribute("Broken")

			-- Survivors interact with standing pallets, killer interacts with dropped ones
			local relevant = false
			if not isBroken then
				if isKiller and isDropped then
					relevant = true
				elseif not isKiller and not isDropped then
					relevant = true
				end
			end

			if relevant then
				local mainPart = findMainPart(palletModel)
				if mainPart then
					local dist = (mainPart.Position - myPosition).Magnitude
					if dist <= nearestDist then
						nearestPallet = palletModel
						nearestDist = dist
					end
				end
			end
		end
	end

	if nearestPallet ~= currentTarget then
		if isHoldingE and currentTarget then
			interactRemote:FireServer(currentTarget, "stop")
			isHoldingE = false
		end
		currentTarget = nearestPallet
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