-- DebugCompleteObjectivesService.server.lua
-- TEST-ONLY: listens for the debug keybind and force-completes every
-- objective stage via StageManager. Remove/disable before shipping.
 
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
 
local StageManager = require(ServerScriptService.Server.StageManager)
 
local remote = ReplicatedStorage:FindFirstChild("DebugCompleteObjectives")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "DebugCompleteObjectives"
	remote.Parent = ReplicatedStorage
end
 
remote.OnServerEvent:Connect(function(player)
	print(player.Name .. " triggered debug: force-complete all objectives")
	StageManager.ForceCompleteAllStages()
end)
 
print("DebugCompleteObjectivesService loaded.")