-- FuseDropService.server.lua
-- Listens for drop requests and puts the held fuse back into the world.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FuseService = require(script.Parent.FuseService)

local remoteEvent = ReplicatedStorage:FindFirstChild("DropFuseRequest")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "DropFuseRequest"
	remoteEvent.Parent = ReplicatedStorage
end

remoteEvent.OnServerEvent:Connect(function(player)
	FuseService.Drop(player)
end)