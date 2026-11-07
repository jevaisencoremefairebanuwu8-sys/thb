-- DebugCompleteObjectivesInput.client.lua
-- TEST-ONLY: press the keybind below to instantly finish every objective
-- stage, so you can test the escape flow without doing the real
-- generator/fusebox repairs first. Remove/disable before shipping.
 
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
 
local DEBUG_KEY = Enum.KeyCode.P
 
local remote = ReplicatedStorage:WaitForChild("DebugCompleteObjectives")
 
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == DEBUG_KEY then
		remote:FireServer()
		print("DebugCompleteObjectivesInput: requested instant objective completion")
	end
end)
 
print("DebugCompleteObjectivesInput loaded. Press " .. DEBUG_KEY.Name .. " to force-complete all objectives.")