local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FADE_TIME = 0.25 -- adjust to taste

local OPEN_IMAGE_TRANSPARENCY  = 0

local OPEN_IMAGE_COLOR   = Color3.fromRGB(0, 0, 0)
local CLOSED_IMAGE_COLOR = Color3.fromRGB(255, 255, 255)

local OPEN_BACKGROUND_COLOR = Color3.fromRGB(255, 255, 255)

local tweenInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

-- Wires one sidebutton up to toggle open/closed on click. Image
-- transparency/color and background color fade via tween; the UIGradient
-- itself just switches on/off instantly (TweenService can't tween
-- NumberSequence properties like Transparency at all, so there's no fade
-- option there).
--
-- Returns a forceClose() function so something OUTSIDE this script (i.e.
-- SidebuttonNavigation's CloseButton, or switching to a different
-- sidebutton) can also revert this button's visual — without that, only
-- clicking this exact button again would ever close it.
local function setupSidebutton(button, gradient)
	local isOpen = false
	local closedImageTransparency = button.ImageTransparency -- whatever it's set to in Studio, so the icon doesn't vanish when closed
	local closedBackgroundColor = button.BackgroundColor3 -- whatever it's set to in Studio

	local function setState(open)
		isOpen = open

		TweenService:Create(button, tweenInfo, {
			ImageTransparency = isOpen and OPEN_IMAGE_TRANSPARENCY or closedImageTransparency,
			ImageColor3 = isOpen and OPEN_IMAGE_COLOR or CLOSED_IMAGE_COLOR,
			BackgroundColor3 = isOpen and OPEN_BACKGROUND_COLOR or closedBackgroundColor,
		}):Play()

		gradient.Enabled = isOpen
	end

	button.MouseButton1Click:Connect(function()
		setState(not isOpen)
	end)

	local function forceClose()
		if isOpen then
			setState(false)
		end
	end

	return forceClose
end

-- Real wiring — matches the paths from SidebuttonNavigation.client.lua:
-- PlayerGui.LobbyUI.Other.Sidebuttons, with LoadoutButton /
-- SurvivorKillerInfoPage / SurvivorKillerShop as the three buttons.
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("LobbyUI")
local otherFolder = screenGui:WaitForChild("Other")
local sideButtonsFolder = otherFolder:WaitForChild("Sidebuttons")

local loadoutButton = sideButtonsFolder:WaitForChild("LoadoutButton")
local forceCloseLoadout = setupSidebutton(loadoutButton, loadoutButton:WaitForChild("UIGradient"))

local infoButton = sideButtonsFolder:WaitForChild("SurvivorKillerInfoPage")
local forceCloseInfo = setupSidebutton(infoButton, infoButton:WaitForChild("UIGradient"))

local shopButton = sideButtonsFolder:WaitForChild("SurvivorKillerShop")
local forceCloseShop = setupSidebutton(shopButton, shopButton:WaitForChild("UIGradient"))

-- Keyed by the same group names SidebuttonNavigation.client.lua uses
-- ("Loadout", "Selection", "Shop"), so the bridge event below can just
-- pass a group name without either script needing to know the other's
-- internals (buttons, gradients, frames, etc.).
local forceCloseByGroup = {
	Loadout = forceCloseLoadout,
	Selection = forceCloseInfo,
	Shop = forceCloseShop,
}

-- One-way signal from SidebuttonNavigation: "this group just closed (or
-- is being replaced by another one), revert its button's visual." Created
-- here if SidebuttonNavigation hasn't run yet; either script can create
-- it first, both just need to agree on the name.
local sidebuttonCloseEvent = ReplicatedStorage:FindFirstChild("SidebuttonVisualClose")
if not sidebuttonCloseEvent then
	sidebuttonCloseEvent = Instance.new("BindableEvent")
	sidebuttonCloseEvent.Name = "SidebuttonVisualClose"
	sidebuttonCloseEvent.Parent = ReplicatedStorage
end

sidebuttonCloseEvent.Event:Connect(function(groupName)
	local forceClose = forceCloseByGroup[groupName]
	if forceClose then
		forceClose()
	end
end)