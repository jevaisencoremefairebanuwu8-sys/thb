-- HealPromptInput.client.lua
-- Shows a custom "Hold E to Heal" prompt above the nearest Injured
-- target in range, and sends start/stop signals on E press/release.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local interactRemote = ReplicatedStorage:FindFirstChild("HealInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "HealInteract"
	interactRemote.Parent = ReplicatedStorage
end

local RANGE = 8
local prompts = {} -- [target] = billboard

local function findRootPart(target)
	if target:IsA("Player") then
		local character = target.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	else
		return target:FindFirstChild("HumanoidRootPart")
	end
end

local function createPrompt(target)
	local rootPart = findRootPart(target)
	if not rootPart then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealBillboard"
	billboard.Size = UDim2.new(0, 140, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Parent = rootPart

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bg.BackgroundTransparency = 0.3
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = bg

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "Hold E to Heal"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = bg

	return billboard
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

local currentTarget = nil
local isHoldingE = false

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
		local isInjured
		if target:IsA("Player") then
			isInjured = target:GetAttribute("HealthState") == "Injured"
		else
			isInjured = target:GetAttribute("HealthState") == "Injured"
		end

		if isInjured then
			local rootPart = findRootPart(target)
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
		if currentTarget then
			local oldRoot = findRootPart(currentTarget)
			local oldBillboard = oldRoot and oldRoot:FindFirstChild("HealBillboard")
			if oldBillboard then
				oldBillboard.Enabled = false
			end
			if isHoldingE then
				interactRemote:FireServer(currentTarget, "stop")
				isHoldingE = false
			end
		end

		currentTarget = nearestTarget

		if currentTarget then
			local rootPart = findRootPart(currentTarget)
			if rootPart then
				local billboard = rootPart:FindFirstChild("HealBillboard")
				if not billboard then
					billboard = createPrompt(currentTarget)
				end
				if billboard then
					billboard.Enabled = true
				end
			end
		end
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