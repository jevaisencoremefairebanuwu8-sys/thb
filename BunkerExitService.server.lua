-- BunkerExitService.server.lua
-- Watches for a survivor leaving the starting bunker. If there's still at
-- least 11:00 left on the match clock, shows that player the "PREPARE"
-- banner. Debounced per-player, reset each round.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)
local ObjectiveAnnouncementService = require(ReplicatedStorage.Shared.ObjectiveAnnouncementService) -- adjust path to wherever you place it

local matchTimerScript = ServerScriptService.Server:WaitForChild("MatchTimerService")
local startRoundEvent = matchTimerScript:WaitForChild("MatchTimer_StartRound")
local getRemainingFunction = matchTimerScript:WaitForChild("MatchTimer_GetRemaining")

-- Same physical part as EscapeService.server.lua's TunnelExit — it's reused
-- for both leaving the bunker (this script, gated by time remaining) and
-- the end-of-match escape (EscapeService, gated by allObjectivesComplete).
local lobbyFolder = Workspace:WaitForChild("Lobby")
local tunnelExitModel = lobbyFolder:WaitForChild("TunnelExitModel")
local tunnelExit = tunnelExitModel:WaitForChild("TunnelExit")

local MIN_TIME_REMAINING = 11 * 60 -- 11:00

local playerLeftBunkerRemote = ReplicatedStorage:FindFirstChild("PlayerLeftBunker")
if not playerLeftBunkerRemote then
	playerLeftBunkerRemote = Instance.new("RemoteEvent")
	playerLeftBunkerRemote.Name = "PlayerLeftBunker"
	playerLeftBunkerRemote.Parent = ReplicatedStorage
end

local hasTriggeredThisRound = {} -- [player] = true, for the PREPARE banner (time-gated)
local hasLeftBunkerThisRound = {} -- [player] = true, for the "left bunker" signal (unconditional)

startRoundEvent.Event:Connect(function()
	table.clear(hasTriggeredThisRound)
	table.clear(hasLeftBunkerThisRound)
end)

tunnelExit.Touched:Connect(function(hit)
	print("BunkerExitService: TunnelExit touched by", hit.Name)

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

	if player:GetAttribute("IsKiller") then
		print("  -> blocked: player is the killer")
		return
	end

	-- Unconditional "left the bunker" signal — fires regardless of time
	-- remaining, since StageUI needs to know this happened even if the
	-- player left too late for the PREPARE banner to show.
	if not hasLeftBunkerThisRound[player] then
		hasLeftBunkerThisRound[player] = true
		playerLeftBunkerRemote:FireClient(player)
	end

	print("  -> player:", player.Name, "| IsKiller:", player:GetAttribute("IsKiller"), "| alreadyTriggered:", hasTriggeredThisRound[player] == true)

	if hasTriggeredThisRound[player] then
		print("  -> blocked: already triggered this round")
		return
	end

	local remaining = getRemainingFunction:Invoke()
	print("  -> remaining time:", remaining, "| needs at least:", MIN_TIME_REMAINING)
	if remaining < MIN_TIME_REMAINING then
		print("  -> blocked: not enough time remaining")
		return
	end

	hasTriggeredThisRound[player] = true

	print("  -> firing PREPARE banner to", player.Name)
	ObjectiveAnnouncementService.AnnouncePlayer(
		player,
		"PREPARE",
		"IT'S SAFE FOR NOW, USE THIS TIME TO SEARCH THE LOCATION"
	)
end)

print("BunkerExitService loaded.")
return true