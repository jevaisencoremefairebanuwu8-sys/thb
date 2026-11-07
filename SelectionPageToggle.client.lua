-- SelectionPageToggle.client.lua
-- Inside KillerSelection and SurvivorSelection, clicking the "Killers"
-- or "Survivors" TextButton (nested in Frame > Survivors/Killers)
-- switches which Selection page is shown.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = playerGui:WaitForChild("LobbyUI")

local killerSelectionFolder = screenGui:WaitForChild("KillerSelection")
local survivorSelectionFolder = screenGui:WaitForChild("SurvivorSelection")

local killerSelectionPage = killerSelectionFolder:WaitForChild("Killers")
local survivorSelectionPage = survivorSelectionFolder:WaitForChild("Survivors")

local function showKillerSelection()
	killerSelectionPage.Visible = true
	survivorSelectionPage.Visible = false
end

local function showSurvivorSelection()
	killerSelectionPage.Visible = false
	survivorSelectionPage.Visible = true
end

-- Wires up the tab button inside a given Selection page
local function setupTabButton(pageFrame, onClick)
	local tabsFrame = pageFrame:FindFirstChild("Survivors/Killers")
	if not tabsFrame then
		warn("No 'Survivors/Killers' frame found in " .. pageFrame:GetFullName())
		return
	end

	local killersButton = tabsFrame:FindFirstChild("Killers")
	local survivorsButton = tabsFrame:FindFirstChild("Survivors")

	if killersButton and killersButton:IsA("GuiButton") then
		killersButton.MouseButton1Click:Connect(showKillerSelection)
	end
	if survivorsButton and survivorsButton:IsA("GuiButton") then
		survivorsButton.MouseButton1Click:Connect(showSurvivorSelection)
	end
end

setupTabButton(killerSelectionPage, showKillerSelection)
setupTabButton(survivorSelectionPage, showSurvivorSelection)