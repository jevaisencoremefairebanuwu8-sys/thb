-- InjuryEffectsClient.client.lua

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local FADE_IN_TIME = 0.4
local HOLD_TIME = 2
local FADE_OUT_TIME = 3

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = playerGui:WaitForChild("BloodUI")
local frame = screenGui:WaitForChild("Frame")
local imageLabel = frame:WaitForChild("ImageLabel")

imageLabel.ImageTransparency = 1

local currentTween = nil
local previousState = player:GetAttribute("HealthState")

local function playBloodFlash()
	if currentTween then
		currentTween:Cancel()
	end

	imageLabel.ImageTransparency = 1

	local fadeIn = TweenService:Create(
		imageLabel,
		TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Linear),
		{ ImageTransparency = 0 }
	)

	currentTween = fadeIn
	fadeIn:Play()

	fadeIn.Completed:Connect(function()
		task.wait(HOLD_TIME)

		local fadeOut = TweenService:Create(
			imageLabel,
			TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Linear),
			{ ImageTransparency = 1 }
		)
		currentTween = fadeOut
		fadeOut:Play()
	end)
end

player:GetAttributeChangedSignal("HealthState"):Connect(function()
	local newState = player:GetAttribute("HealthState")

	-- Only flash when going from Healthy -> Injured (getting hurt),
	-- not when recovering from Downed -> Injured
	if newState == "Injured" and previousState == "Healthy" then
		playBloodFlash()
	end

	previousState = newState
end)