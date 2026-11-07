-- EscapeService.server.lua
-- Watches StageManager for "all objectives complete", opens the escape
-- gates, then marks any survivor who crosses TunnelExit afterward as
-- Escaped. Killer is exempt. Debounced per-player, reset each round.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)
local StageManager = require(ServerScriptService.Server.StageManager)
local GateService = require(ServerScriptService.Server.GateService)

local matchTimerScript = ServerScriptService.Server:WaitForChild("MatchTimerService")
local startRoundEvent = matchTimerScript:WaitForChild("MatchTimer_StartRound")

local playerEscapedRemote = ReplicatedStorage:FindFirstChild("PlayerEscaped")
if not playerEscapedRemote then
	playerEscapedRemote = Instance.new("RemoteEvent")
	playerEscapedRemote.Name = "PlayerEscaped"
	playerEscapedRemote.Parent = ReplicatedStorage
end

local lobbyFolder = Workspace:WaitForChild("Lobby")
local tunnelExitModel = lobbyFolder:WaitForChild("TunnelExitModel")
local tunnelExit = tunnelExitModel:WaitForChild("TunnelExit")

-- States a survivor is allowed to escape from. Downed/Hooked/Dead can't
-- just walk out, and this is naturally skipped for the killer too.
local ESCAPABLE_STATES = {
	[PlayerStateService.States.Healthy] = true,
	[PlayerStateService.States.Injured] = true,
}

local allObjectivesComplete = false
local hasEscapedThisRound = {} -- [player] = true

StageManager.StageChanged.Event:Connect(function(nextStage)
	if nextStage == nil then
		allObjectivesComplete = true
		GateService.OpenGatesForEscape()
	end
end)

startRoundEvent.Event:Connect(function()
	allObjectivesComplete = false
	table.clear(hasEscapedThisRound)
end)

tunnelExit.Touched:Connect(function(hit)
	print("EscapeService: TunnelExit touched by", hit.Name)

	if not allObjectivesComplete then
		print("  -> blocked: allObjectivesComplete is false")
		return
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		print("  -> blocked: no character ancestor found")
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		print("  -> blocked: character does not belong to a player (" .. character.Name .. ")")
		return
	end

	print("  -> player:", player.Name, "| IsKiller:", player:GetAttribute("IsKiller"), "| HealthState:", PlayerStateService.GetState(player), "| alreadyEscaped:", hasEscapedThisRound[player] == true)

	if player:GetAttribute("IsKiller") then
		print("  -> blocked: player is the killer")
		return
	end

	if hasEscapedThisRound[player] then
		print("  -> blocked: already escaped this round")
		return
	end

	local currentState = PlayerStateService.GetState(player)
	if not ESCAPABLE_STATES[currentState] then
		print("  -> blocked: HealthState '" .. tostring(currentState) .. "' is not escapable (needs Healthy or Injured)")
		return
	end

	hasEscapedThisRound[player] = true
	PlayerStateService.SetState(player, PlayerStateService.States.Escaped)
	playerEscapedRemote:FireClient(player)
	print(player.Name .. " escaped!")
end)

print("EscapeService loaded.")

return true