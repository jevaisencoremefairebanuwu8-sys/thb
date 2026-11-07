-- EscapeConfirmationUI.client.lua
-- Shows a simple "You Escaped!" fade in/out when the server confirms
-- this player has escaped. Builds its own UI so there's no dependency
-- on a hand-placed GuiObject that could go missing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local playerEscapedRemote = ReplicatedStorage:WaitForChild("PlayerEscaped")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EscapeConfirmationUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 0.15, 0)
label.Position = UDim2.new(0, 0, 0.35, 0)
label.BackgroundTransparency = 1
label.Text = "You Escaped!"
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.TextTransparency = 1
label.Parent = screenGui

local fadeIn = TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 })
local fadeOut = TweenService:Create(label, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })

playerEscapedRemote.OnClientEvent:Connect(function()
	fadeIn:Play()
	task.wait(2)
	fadeOut:Play()
end)

print("EscapeConfirmationUI loaded.")