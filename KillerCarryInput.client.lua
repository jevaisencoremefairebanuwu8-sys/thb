-- KillerCarryInput.client.lua
-- Press E to pick up / drop a nearby Downed survivor (killer only).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remoteEvent = ReplicatedStorage:WaitForChild("KillerCarryToggle")

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		if player:GetAttribute("IsKiller") then
			remoteEvent:FireServer()
		end
	end
end)