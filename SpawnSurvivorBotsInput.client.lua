-- SpawnSurvivorBotsInput.client.lua
-- TEST-ONLY: press the keybind below to spawn a survivor bot for testing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SPAWN_KEY = Enum.KeyCode.B

local remote = ReplicatedStorage:WaitForChild("SpawnSurvivorBots")

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == SPAWN_KEY then
		remote:FireServer(1)
		print("Requested 1 survivor bot spawn")
	end
end)

print("SpawnSurvivorBotsInput loaded. Press " .. SPAWN_KEY.Name .. " to spawn a survivor bot.")