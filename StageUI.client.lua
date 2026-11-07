-- StageUI.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvent = ReplicatedStorage:WaitForChild("StageUpdate")
local remoteFunction = ReplicatedStorage:WaitForChild("GetStageInfo")
local matchTimerRemote = ReplicatedStorage:WaitForChild("MatchTimerUpdate")
local playerLeftBunkerRemote = ReplicatedStorage:WaitForChild("PlayerLeftBunker")
local roundStartedRemote = ReplicatedStorage:WaitForChild("RoundStarted")

local screenGui = playerGui:WaitForChild("StageUI")
local banner = screenGui:WaitForChild("Banner")
local label = banner:WaitForChild("Label")

local BUNKER_TEXT = "Get out of the bunker"
local EXPLORE_TEXT = "Explore your surroundings"
local EXPLORE_THRESHOLD_SECONDS = 11 * 60 -- show the generic message while more than 11:00 remains

-- Defaults to "still in the first minute" so the label is correct even
-- before the first MatchTimerUpdate tick arrives.
local currentRemainingSeconds = 12 * 60
local hasLeftBunker = false

local currentStageName = nil
local currentCompleted = 0
local currentRequired = 0

local function parseRemainingSeconds(timeString)
	local minutes, seconds = timeString:match("^(%d+):(%d+)$")
	if not minutes then
		return currentRemainingSeconds -- keep last known value if the format is ever unexpected
	end
	return tonumber(minutes) * 60 + tonumber(seconds)
end

local function refreshLabel()
	if not hasLeftBunker then
		label.Text = BUNKER_TEXT
	elseif currentRemainingSeconds > EXPLORE_THRESHOLD_SECONDS then
		label.Text = EXPLORE_TEXT
	elseif currentStageName == nil then
		label.Text = "All Objectives Complete!"
	else
		label.Text = currentStageName .. ": " .. currentCompleted .. "/" .. currentRequired
	end
end

local function updateLabel(stageName, completed, required)
	currentStageName = stageName
	currentCompleted = completed
	currentRequired = required
	refreshLabel()
end

local stageName, completed, required = remoteFunction:InvokeServer()
updateLabel(stageName, completed, required)

remoteEvent.OnClientEvent:Connect(function(newStageName, newCompleted, newRequired)
	updateLabel(newStageName, newCompleted, newRequired)
end)

matchTimerRemote.OnClientEvent:Connect(function(timeString)
	currentRemainingSeconds = parseRemainingSeconds(timeString)
	refreshLabel()
end)

playerLeftBunkerRemote.OnClientEvent:Connect(function()
	hasLeftBunker = true
	refreshLabel()
end)

roundStartedRemote.OnClientEvent:Connect(function()
	hasLeftBunker = false
	refreshLabel()
end)