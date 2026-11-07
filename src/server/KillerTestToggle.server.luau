-- KillerTestToggle.server.lua
-- TEMPORARY: press K to toggle yourself as Killer.
-- TEMPORARY: press M to toggle "forced survivor" (LobbyService will never pick you as killer).
-- Delete this once real role assignment exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvent = ReplicatedStorage:FindFirstChild("TestKillerToggle")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "TestKillerToggle"
	remoteEvent.Parent = ReplicatedStorage
end

local forceSurvivorRemote = ReplicatedStorage:FindFirstChild("TestForceSurvivorToggle")
if not forceSurvivorRemote then
	forceSurvivorRemote = Instance.new("RemoteEvent")
	forceSurvivorRemote.Name = "TestForceSurvivorToggle"
	forceSurvivorRemote.Parent = ReplicatedStorage
end

remoteEvent.OnServerEvent:Connect(function(player)
	local isKiller = player:GetAttribute("IsKiller") or false
	player:SetAttribute("IsKiller", not isKiller)
	print(player.Name .. " is now " .. (not isKiller and "the KILLER" or "a survivor"))
end)

forceSurvivorRemote.OnServerEvent:Connect(function(player)
	local forced = player:GetAttribute("ForceSurvivor") == true
	player:SetAttribute("ForceSurvivor", not forced)

	if not forced then
		-- turning it ON: drop the killer role right now too
		player:SetAttribute("IsKiller", false)
	end

	print(player.Name .. (not forced and " is now FORCED SURVIVOR (never picked as killer)" or " can be picked as killer again"))
end)