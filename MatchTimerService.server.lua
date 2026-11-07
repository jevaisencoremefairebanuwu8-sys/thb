-- MatchTimerService.server.lua
-- Runs the match countdown, but only while a round is active.
-- LobbyService controls StartRound/EndRound via BindableEvents.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)

local MATCH_DURATION_SECONDS = 12 * 60

local timerRemote = ReplicatedStorage:FindFirstChild("MatchTimerUpdate")
if not timerRemote then
	timerRemote = Instance.new("RemoteEvent")
	timerRemote.Name = "MatchTimerUpdate"
	timerRemote.Parent = ReplicatedStorage
end

local timeoutRemote = ReplicatedStorage:FindFirstChild("MatchTimerExpired")
if not timeoutRemote then
	timeoutRemote = Instance.new("RemoteEvent")
	timeoutRemote.Name = "MatchTimerExpired"
	timeoutRemote.Parent = ReplicatedStorage
end

local StartRoundEvent = Instance.new("BindableEvent")
StartRoundEvent.Name = "MatchTimer_StartRound"
StartRoundEvent.Parent = script

local RoundEndedEvent = Instance.new("BindableEvent")
RoundEndedEvent.Name = "MatchTimer_RoundEnded"
RoundEndedEvent.Parent = script

local ALIVE_STATES = {
	Healthy = true,
	Injured = true,
	Downed = true,
	Hooked = true,
}

local roundActive = false
local matchStartTime = 0

local GetRemainingTimeFunction = Instance.new("BindableFunction")
GetRemainingTimeFunction.Name = "MatchTimer_GetRemaining"
GetRemainingTimeFunction.Parent = script

GetRemainingTimeFunction.OnInvoke = function()
	if not roundActive then
		return 0
	end
	local elapsed = tick() - matchStartTime
	return math.max(0, MATCH_DURATION_SECONDS - elapsed)
end

local function formatTime(secondsRemaining)
	local minutes = math.floor(secondsRemaining / 60)
	local seconds = math.floor(secondsRemaining % 60)
	return string.format("%02d:%02d", minutes, seconds)
end

local function killAllSurvivors()
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("IsKiller") then
			local state = PlayerStateService.GetState(player)
			if ALIVE_STATES[state] then
				PlayerStateService.SetState(player, PlayerStateService.States.Dead)
			end
		end
	end
end

StartRoundEvent.Event:Connect(function()
	matchStartTime = tick()
	roundActive = true
	print("MatchTimerService: round started.")
end)

RunService.Heartbeat:Connect(function()
	if not roundActive then
		return
	end

	local elapsed = tick() - matchStartTime
	local remaining = math.max(0, MATCH_DURATION_SECONDS - elapsed)

	timerRemote:FireAllClients(formatTime(remaining))

	if remaining <= 0 then
		roundActive = false
		print("Match timer expired.")
		timeoutRemote:FireAllClients()
		killAllSurvivors()
		RoundEndedEvent:Fire()
	end
end)

print("MatchTimerService loaded (round-controlled). Duration: " .. MATCH_DURATION_SECONDS .. " seconds.")