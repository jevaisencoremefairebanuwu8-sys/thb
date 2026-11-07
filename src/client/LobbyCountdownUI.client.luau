-- LobbyCountdownUI.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lobbyCountdownRemote = ReplicatedStorage:WaitForChild("LobbyCountdownUpdate")
local matchTimerRemote = ReplicatedStorage:WaitForChild("MatchTimerUpdate")
local matchExpiredRemote = ReplicatedStorage:WaitForChild("MatchTimerExpired")

local stageGui = playerGui:WaitForChild("StageUI")
stageGui.Enabled = false

local screenGui = playerGui:WaitForChild("LobbyCountdownGui")
local frame = screenGui:WaitForChild("Frame")
local countdownLabel = frame:WaitForChild("CountdownLabel")

-- The match timer UI, shown once the lobby countdown hits 0 (or a round is already running)
local timerGui = playerGui:WaitForChild("TimerGui")
timerGui.Enabled = false

-- true between "match timer expired" and the next lobby countdown tick,
-- so a late 00:00 packet can't flip us back to the match UI
local matchOver = false

local function showMatchUI()
	screenGui.Enabled = false
	timerGui.Enabled = true
	stageGui.Enabled = true
end

local function showLobbyUI(secondsRemaining)
	screenGui.Enabled = true
	timerGui.Enabled = false
	stageGui.Enabled = false
	countdownLabel.Text = "Starting in: " .. secondsRemaining
end

-- Intermission: the server fires this every second
lobbyCountdownRemote.OnClientEvent:Connect(function(secondsRemaining)
	matchOver = false
	if secondsRemaining <= 0 then
		showMatchUI()
	else
		showLobbyUI(secondsRemaining)
	end
end)

-- Round in progress: fires every frame, so a player who joins mid-round
-- gets switched to the match UI immediately
matchTimerRemote.OnClientEvent:Connect(function()
	if matchOver then
		return
	end
	showMatchUI()
end)

matchExpiredRemote.OnClientEvent:Connect(function()
	matchOver = true
end)