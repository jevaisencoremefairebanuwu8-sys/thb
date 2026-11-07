-- FuseUI.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvent = ReplicatedStorage:WaitForChild("FuseHeldUpdate")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FuseUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 250, 0, 40)
label.Position = UDim2.new(0.02, 0, 0.88, 0)
label.BackgroundTransparency = 0.4
label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.Visible = false
label.Parent = screenGui

remoteEvent.OnClientEvent:Connect(function(isHolding)
	label.Visible = isHolding
	if isHolding then
		label.Text = "Holding a Fuse"
	end
end)