-- ActiveGameUIToggle.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local roundStartedRemote = ReplicatedStorage:WaitForChild("RoundStarted")
local roundEndedRemote = ReplicatedStorage:WaitForChild("RoundEndedForClients")

local screenGui = playerGui:WaitForChild("LobbyUI")
local otherFolder = screenGui:WaitForChild("Other")

local sideButtons = otherFolder:WaitForChild("Sidebuttons")
local lobbyFrame = otherFolder:WaitForChild("Frame")
local killerChance = otherFolder:WaitForChild("KillerChance")
local objective1 = otherFolder:WaitForChild("Objective1")
local objective2 = otherFolder:WaitForChild("Objective2")

-- Whatever Visible was set to in Studio is what Frame returns to when it's allowed to show
local frameDefaultVisible = lobbyFrame.Visible

local isRoundActive = false
local isInTunnelExit = false
local isKiller = player:GetAttribute("IsKiller") == true

local function updateVisibility()
	-- Sidebuttons: lobby only, not in the tunnel exit, not the killer
	sideButtons.Visible = not isRoundActive and not isInTunnelExit and not isKiller

	-- Frame: hidden in the tunnel exit and for the killer
	lobbyFrame.Visible = frameDefaultVisible and not isInTunnelExit and not isKiller
end

local function setActiveGameState(isActive)
	isRoundActive = isActive
	killerChance.Visible = not isActive
	objective1.Visible = isActive
	objective2.Visible = isActive
	updateVisibility()
end

roundStartedRemote.OnClientEvent:Connect(function()
	setActiveGameState(true)
end)

roundEndedRemote.OnClientEvent:Connect(function()
	setActiveGameState(false)
end)

player:GetAttributeChangedSignal("IsKiller"):Connect(function()
	isKiller = player:GetAttribute("IsKiller") == true
	updateVisibility()
end)

setActiveGameState(false)

-- Track whether the local player is inside Workspace.Lobby.TunnelExitModel
task.spawn(function()
	local lobbyFolder = Workspace:WaitForChild("Lobby")
	local tunnelExitModel = lobbyFolder:WaitForChild("TunnelExitModel")

	-- The tunnel is static, so compute its bounding box once instead of every frame
	local boxCFrame, boxSize = tunnelExitModel:GetBoundingBox()
	local halfSize = boxSize / 2

	local function isInsideTunnel(position)
		local relative = boxCFrame:PointToObjectSpace(position)
		return math.abs(relative.X) <= halfSize.X
			and math.abs(relative.Y) <= halfSize.Y
			and math.abs(relative.Z) <= halfSize.Z
	end

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local inside = root ~= nil and isInsideTunnel(root.Position)

		if inside ~= isInTunnelExit then
			isInTunnelExit = inside
			updateVisibility()
		end
	end)
end)