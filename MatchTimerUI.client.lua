-- MatchTimerUI.client.lua
-- Connects to your custom timer TextLabel and updates it with MM:SS.
-- Also plays a fade-to-black-and-back when the match timer expires.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local timerRemote = ReplicatedStorage:WaitForChild("MatchTimerUpdate")
local timeoutRemote = ReplicatedStorage:WaitForChild("MatchTimerExpired")

-- CHANGE THESE PATHS to match your actual timer UI:
local screenGui = playerGui:WaitForChild("TimerGui")
local frame = screenGui:WaitForChild("Frame")
local timerLabel = frame:WaitForChild("Timer")
timerRemote.OnClientEvent:Connect(function(timeText)
	timerLabel.Text = timeText
end)

-- Fade to black, hold, fade back — 1 sec / 1 sec / 1 sec
local function playDeathFade()
	local fadeGui = Instance.new("ScreenGui")
	fadeGui.Name = "DeathFade"
	fadeGui.DisplayOrder = 100
	fadeGui.Parent = playerGui

	local blackFrame = Instance.new("Frame")
	blackFrame.Size = UDim2.new(1, 0, 1, 0)
	blackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	blackFrame.BackgroundTransparency = 1
	blackFrame.BorderSizePixel = 0
	blackFrame.Parent = fadeGui

	local fadeIn = TweenService:Create(
		blackFrame,
		TweenInfo.new(1, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 0 }
	)
	fadeIn:Play()

	fadeIn.Completed:Connect(function()
		task.wait(1)
		local fadeOut = TweenService:Create(
			blackFrame,
			TweenInfo.new(1, Enum.EasingStyle.Linear),
			{ BackgroundTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			fadeGui:Destroy()
		end)
	end)
end

timeoutRemote.OnClientEvent:Connect(function()
	playDeathFade()
end)