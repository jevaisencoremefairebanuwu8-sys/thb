-- DownedPromptInput.client.lua
-- Tracks the nearest Downed target in range (no visual label) and
-- sends hold start/stop signals to rescue them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local rescueRemote = ReplicatedStorage:FindFirstChild("RescueInteract")
if not rescueRemote then
	rescueRemote = Instance.new("RemoteEvent")
	rescueRemote.Name = "RescueInteract"
	rescueRemote.Parent = ReplicatedStorage
end

local RANGE = 8
local currentTarget = nil
local isHoldingE = false

local function getRootPart(target)
	if target:IsA("Player") then
		local character = target.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	else
		return target:FindFirstChild("HumanoidRootPart")
	end
end

local function getAllTargets()
	local targets = {}
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			table.insert(targets, otherPlayer)
		end
	end
	local dummy = Workspace:FindFirstChild("TestDummy")
	if dummy then
		table.insert(targets, dummy)
	end
	return targets
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

	local nearestTarget, nearestDist = nil, RANGE

	for _, target in ipairs(getAllTargets()) do
		local state = target:GetAttribute("HealthState")
		if state == "Downed" and not target:GetAttribute("IsBeingCarried") then
			local rootPart = getRootPart(target)
			if rootPart then
				local dist = (rootPart.Position - myPosition).Magnitude
				if dist <= nearestDist then
					nearestTarget = target
					nearestDist = dist
				end
			end
		end
	end

	if nearestTarget ~= currentTarget then
		if isHoldingE and currentTarget then
			rescueRemote:FireServer(currentTarget, "stop")
			isHoldingE = false
		end
		currentTarget = nearestTarget
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.E and currentTarget then
		isHoldingE = true
		rescueRemote:FireServer(currentTarget, "start")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.E and isHoldingE then
		isHoldingE = false
		if currentTarget then
			rescueRemote:FireServer(currentTarget, "stop")
		end
	end
end)