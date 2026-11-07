-- GeneratorUI.client.lua
-- The shared progress bar (used for repairing/healing/rescuing/unhooking).
-- Also shows a dim preview specifically for nearby generators when the
-- bar isn't otherwise in use, and only during the Generators stage.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local generatorsFolder = Workspace:WaitForChild("Generators")

local remoteEvent = ReplicatedStorage:WaitForChild("ProgressUpdate")
local stageUpdateRemote = ReplicatedStorage:WaitForChild("StageUpdate")
local getStageInfoRemote = ReplicatedStorage:WaitForChild("GetStageInfo")

local screenGui = playerGui:WaitForChild("GeneratorUI")
local repairBar = screenGui:WaitForChild("RepairBar")
local title = repairBar:WaitForChild("Title")
local barTrack = repairBar:WaitForChild("BarTrack")
local fill = barTrack:WaitForChild("Fill")
local background = barTrack:WaitForChild("Background")
local outline = repairBar:WaitForChild("Outline")

local VISIBILITY_RANGE = 10
local DIM_EXTRA_TRANSPARENCY = 0.25

local originalFillTransparency = fill.BackgroundTransparency
local originalBackgroundTransparency = background.BackgroundTransparency
local originalOutlineTransparency = outline.ImageTransparency

print("Original transparencies - fill:", originalFillTransparency, "background:", originalBackgroundTransparency, "outline:", originalOutlineTransparency)

repairBar.Visible = false
local isBarActive = false
local currentStage = nil

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

local function setBarTransparency(dimmed)
	if dimmed then
		fill.BackgroundTransparency = math.min(1, originalFillTransparency + DIM_EXTRA_TRANSPARENCY)
		background.BackgroundTransparency = math.min(1, originalBackgroundTransparency + DIM_EXTRA_TRANSPARENCY)
		outline.ImageTransparency = math.min(1, originalOutlineTransparency + DIM_EXTRA_TRANSPARENCY)
	else
		fill.BackgroundTransparency = originalFillTransparency
		background.BackgroundTransparency = originalBackgroundTransparency
		outline.ImageTransparency = originalOutlineTransparency
	end
end

remoteEvent.OnClientEvent:Connect(function(data)
	if data == nil then
		isBarActive = false
		repairBar.Visible = false
	else
		isBarActive = true
		setBarTransparency(false)
		repairBar.Visible = true
		title.Text = string.upper(data.action)
		fill.Size = UDim2.new(data.progress / 100, 0, 1, 0)
	end
end)

stageUpdateRemote.OnClientEvent:Connect(function(stageName)
	currentStage = stageName
end)

currentStage = getStageInfoRemote:InvokeServer()

RunService.Heartbeat:Connect(function()
	if isBarActive then
		return
	end

	if currentStage ~= "Generators" then
		repairBar.Visible = false
		return
	end

	local myPosition = getMyPosition()
	if not myPosition then
		repairBar.Visible = false
		return
	end

	local nearestGenerator, nearestDist = nil, VISIBILITY_RANGE

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

	if nearestGenerator then
		local progress = nearestGenerator:GetAttribute("Progress") or 0
		setBarTransparency(true)
		repairBar.Visible = true
		title.Text = "REPAIRING"
		fill.Size = UDim2.new(progress / 100, 0, 1, 0)
	else
		repairBar.Visible = false
	end
end)