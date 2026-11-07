-- KillerTestInput.client.lua
-- TEMPORARY: press K to toggle Killer role.
-- TEMPORARY: press M to toggle "never killer" (forced survivor).

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvent = ReplicatedStorage:WaitForChild("TestKillerToggle")
local forceSurvivorRemote = ReplicatedStorage:WaitForChild("TestForceSurvivorToggle")

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.K then
		remoteEvent:FireServer()
	elseif input.KeyCode == Enum.KeyCode.M then
		forceSurvivorRemote:FireServer()
	end
end)