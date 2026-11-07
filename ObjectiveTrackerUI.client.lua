-- ObjectiveTrackerUI.client.lua
-- Colors Objective1/Objective2's UIStroke based on which one is the
-- currently active objective (this round's first vs second stage --
-- StageManager randomizes which actual stage that is each round, so we
-- go by currentStageIndex, not by stage name). Also fades in a green
-- "finished" circle over each grey pip as individual generators/
-- fuseboxes complete.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ACTIVE_COLOR = Color3.fromRGB(251, 255, 37)
local FADE_IN_TIME = 0.4

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = playerGui:WaitForChild("LobbyUI")
local otherFolder = screenGui:WaitForChild("Other")

local objective1 = otherFolder:WaitForChild("Objective1")
local objective2 = otherFolder:WaitForChild("Objective2")

local objective1Stroke = objective1:WaitForChild("UIStroke")
local objective2Stroke = objective2:WaitForChild("UIStroke")

-- Whatever color these start at is treated as the "not active yet" look,
-- so Objective2 resets correctly at the start of a fresh round instead
-- of staying green from the previous round.
local defaultStroke1Color = objective1Stroke.Color
local defaultStroke2Color = objective2Stroke.Color

local function updateStrokes(stageIndex)
	if stageIndex == 1 then
		objective1Stroke.Color = ACTIVE_COLOR
		objective2Stroke.Color = defaultStroke2Color
	elseif stageIndex == 2 then
		objective1Stroke.Color = defaultStroke1Color
		objective2Stroke.Color = ACTIVE_COLOR
	elseif stageIndex and stageIndex >= 3 then
		objective1Stroke.Color = defaultStroke1Color
		objective2Stroke.Color = defaultStroke2Color
	end
end

-- === Per-objective progress circles ===
local function getGreyCircles(objectiveFrame)
	local circles = {}
	local i = 1
	while true do
		local circle = objectiveFrame:FindFirstChild("GreyCircle" .. i)
		if not circle then
			break
		end
		table.insert(circles, circle)
		i += 1
	end
	return circles
end

local slots = {
	[1] = {
		frame = objective1,
		greyCircles = getGreyCircles(objective1),
		template = objective1:WaitForChild("FinishedGreyCircle1"),
		shownCount = 0,
		clones = {},
	},
	[2] = {
		frame = objective2,
		greyCircles = getGreyCircles(objective2),
		template = objective2:WaitForChild("FinishedGreyCircle1"),
		shownCount = 0,
		clones = {},
	},
}

slots[1].template.Visible = false
slots[2].template.Visible = false

local function fadeInFinishedCircle(slot, greyCircle)
	local clone = slot.template:Clone()
	clone.Position = greyCircle.Position
	clone.Size = greyCircle.Size
	clone.AnchorPoint = greyCircle.AnchorPoint
	clone.Visible = true
	clone.Parent = slot.frame

	if clone:IsA("ImageLabel") or clone:IsA("ImageButton") then
		local targetImageTransparency = clone.ImageTransparency
		clone.ImageTransparency = 1
		TweenService:Create(clone, TweenInfo.new(FADE_IN_TIME), { ImageTransparency = targetImageTransparency }):Play()
	end
	if clone:IsA("GuiObject") and clone.BackgroundTransparency < 1 then
		local targetBgTransparency = clone.BackgroundTransparency
		clone.BackgroundTransparency = 1
		TweenService:Create(clone, TweenInfo.new(FADE_IN_TIME), { BackgroundTransparency = targetBgTransparency }):Play()
	end

	table.insert(slot.clones, clone)
end

local function showFinishedCircles(slotIndex, completedCount)
	local slot = slots[slotIndex]
	if not slot then
		return
	end
	while slot.shownCount < completedCount and slot.shownCount < #slot.greyCircles do
		slot.shownCount += 1
		fadeInFinishedCircle(slot, slot.greyCircles[slot.shownCount])
	end
end

local function resetSlot(slotIndex)
	local slot = slots[slotIndex]
	for _, clone in ipairs(slot.clones) do
		clone:Destroy()
	end
	slot.clones = {}
	slot.shownCount = 0
end
-- === End per-objective progress circles ===

local stageUpdateRemote = ReplicatedStorage:WaitForChild("StageUpdate")

stageUpdateRemote.OnClientEvent:Connect(function(stageName, completedCount, requiredCount, stageIndex)
	updateStrokes(stageIndex)

	-- Genuine round start (not just "stage 1 still in progress") is
	-- uniquely identified by stageIndex 1 arriving WITH completedCount 0
	-- together -- completedCount can never return to 0 mid-round once
	-- above 0, so this combination only happens at ResetRound().
	if stageIndex == 1 and completedCount == 0 then
		resetSlot(1)
		resetSlot(2)
	end

	if stageName and stageIndex then
		showFinishedCircles(stageIndex, completedCount)
	end
end)

print("ObjectiveTrackerUI loaded.")