-- ProgressBarService.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvent = ReplicatedStorage:FindFirstChild("ProgressUpdate")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "ProgressUpdate"
	remoteEvent.Parent = ReplicatedStorage
end

local ProgressBarService = {}

function ProgressBarService.Update(player, action, progress)
	if not player:IsA("Player") then
		return
	end
	remoteEvent:FireClient(player, { action = action, progress = progress })
end

function ProgressBarService.Hide(player)
	if not player:IsA("Player") then
		return
	end
	remoteEvent:FireClient(player, nil)
end

return ProgressBarService