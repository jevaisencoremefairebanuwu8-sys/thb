-- InjuryTestInput.client.lua
-- TEMPORARY: press H to cycle Healthy -> Injured -> Downed -> Healthy.
-- Delete this file once real killer hits exist.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvent = ReplicatedStorage:WaitForChild("TestInjureToggle")

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.H then
		remoteEvent:FireServer()
	end
end)