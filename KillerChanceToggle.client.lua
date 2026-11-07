-- KillerChanceToggle.client.lua
-- Inside LobbyUI > Other > KillerChance, 4 frames named '0'/'1'/'2'/'3'
-- (each with a TextButton called 'Button') let the player pick their
-- odds of being chosen as killer. 0 = never picked, 1 = default/normal
-- odds, 2/3 = increasingly more likely. Selecting one sends it to the
-- server (KillerChanceService.server.lua), which weights killer
-- selection in LobbyService.server.lua accordingly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("LobbyUI") -- adjust if named differently
local otherFolder = screenGui:WaitForChild("Other")
local killerChanceFrame = otherFolder:WaitForChild("KillerChance")

local killerChanceRemote = ReplicatedStorage:FindFirstChild("SetKillerChance")
if not killerChanceRemote then
	killerChanceRemote = Instance.new("RemoteEvent")
	killerChanceRemote.Name = "SetKillerChance"
	killerChanceRemote.Parent = ReplicatedStorage
end

local options = {} -- [value] = { frame, button, selectedGradient, unselectedGradient }

for _, child in ipairs(killerChanceFrame:GetChildren()) do
	local value = tonumber(child.Name)
	if value then
		local button = child:FindFirstChild("Button")
		local selectedGradient = child:FindFirstChild("Selected")
		local unselectedGradient = child:FindFirstChild("Unselected")
		if button then
			options[value] = {
				frame = child,
				button = button,
				selectedGradient = selectedGradient,
				unselectedGradient = unselectedGradient,
			}
			if not selectedGradient then
				warn("KillerChanceToggle: frame '" .. child.Name .. "' has no 'Selected' gradient.")
			end
			if not unselectedGradient then
				warn("KillerChanceToggle: frame '" .. child.Name .. "' has no 'Unselected' gradient.")
			end
		else
			warn("KillerChanceToggle: frame '" .. child.Name .. "' has no 'Button' child.")
		end
	end
end

local function refreshSelection()
	local current = player:GetAttribute("KillerChance")
	if current == nil then
		current = 1
	end
	for value, option in pairs(options) do
		local isChosen = (value == current)
		if option.selectedGradient then
			option.selectedGradient.Enabled = isChosen
		end
		if option.unselectedGradient then
			option.unselectedGradient.Enabled = not isChosen
		end
	end
end

for value, option in pairs(options) do
	option.button.Activated:Connect(function()
		killerChanceRemote:FireServer(value)
	end)
end

player:GetAttributeChangedSignal("KillerChance"):Connect(refreshSelection)
refreshSelection()