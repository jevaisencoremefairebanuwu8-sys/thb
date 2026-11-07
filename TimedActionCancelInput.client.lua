-- TimedActionCancelInput.client.lua
-- Pressing any movement key cancels whatever timed action
-- (repairing, healing, etc.) the player is currently doing.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvent = ReplicatedStorage:WaitForChild("CancelTimedAction")

local movementKeys = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Space] = true,
}

print("TimedActionCancelInput script loaded")

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if movementKeys[input.KeyCode] then
		remoteEvent:FireServer()
	end
end)