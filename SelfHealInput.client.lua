-- SelfHealInput.client.lua
-- Hold R to self-heal while Injured (and crouched).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remoteEvent = ReplicatedStorage:WaitForChild("SelfHealToggle")

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.R then
		remoteEvent:FireServer("start")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.R then
		remoteEvent:FireServer("stop")
	end
end)