-- KillerAttackInput.client.lua

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("KillerAttackInput script loaded")

local player = Players.LocalPlayer

local remoteEvent = ReplicatedStorage:WaitForChild("KillerAttackRequest")
print("KillerAttackInput found remote")

local mouseDownTime = nil

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		print("Mouse clicked. IsKiller:", player:GetAttribute("IsKiller"))
		if not player:GetAttribute("IsKiller") then
			return
		end
		mouseDownTime = tick()
		remoteEvent:FireServer("start")
		print("Fired start to server")
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not player:GetAttribute("IsKiller") then
			return
		end
		if mouseDownTime then
			local holdDuration = tick() - mouseDownTime
			remoteEvent:FireServer("end", holdDuration)
			print("Fired end to server, holdDuration:", holdDuration)
			mouseDownTime = nil
		end
	end
end)