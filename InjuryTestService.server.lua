-- InjuryTestService.server.lua
-- TEMPORARY: press H to cycle Healthy -> Injured -> Downed -> Healthy.
-- Delete this file once real killer hits exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)

local remoteEvent = ReplicatedStorage:FindFirstChild("TestInjureToggle")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "TestInjureToggle"
	remoteEvent.Parent = ReplicatedStorage
end

remoteEvent.OnServerEvent:Connect(function(player)
	local States = PlayerStateService.States
	local currentState = PlayerStateService.GetState(player)

	if currentState == States.Healthy then
		PlayerStateService.SetState(player, States.Injured)
	elseif currentState == States.Injured then
		PlayerStateService.SetState(player, States.Downed)
	elseif currentState == States.Downed then
		PlayerStateService.SetState(player, States.Healthy)
		player:SetAttribute("DownedProgress", 0)
	end
end)