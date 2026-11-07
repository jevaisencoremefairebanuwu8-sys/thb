-- SidebuttonPreview.client.lua
-- Small popup describing each sidebutton. Visible while hovering it, AND
-- stays visible for as long as that button's page is currently open
-- (even without hovering) -- so it's an OR of two states, not just a
-- plain hover tooltip.
--
-- Animation: the frame fades in first, then the title/description text
-- fades in after. Hiding does the reverse -- text fades out first, then
-- the frame -- so it doesn't look like an abrupt cut in either direction.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("LobbyUI")
local otherFolder = screenGui:WaitForChild("Other")
local sideButtons = otherFolder:WaitForChild("Sidebuttons")

local loadoutButton = sideButtons:WaitForChild("LoadoutButton")
local infoButton = sideButtons:WaitForChild("SurvivorKillerInfoPage")
local shopButton = sideButtons:WaitForChild("SurvivorKillerShop")

local previewsFolder = screenGui:WaitForChild("SideButtonPreviews")
local survivorKillerPreview = previewsFolder:WaitForChild("SurvivorKillerPreview")
local loadoutPreview = previewsFolder:WaitForChild("LoadoutCustomPreview")
local shopPreview = previewsFolder:WaitForChild("ShopPreview")

local FRAME_FADE_TIME = 0.15
local TEXT_FADE_TIME = 0.15

local frameFadeInInfo = TweenInfo.new(FRAME_FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local frameFadeOutInfo = TweenInfo.new(FRAME_FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
local textFadeInfo = TweenInfo.new(TEXT_FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

-- Wraps one preview frame: captures its "fully shown" transparency values
-- up front, then exposes show()/hide() that animate toward/away from
-- them. isVisible tracks the frame's actual current state so overlapping
-- show/hide calls (e.g. mouse re-entering mid-fade-out) don't stack
-- redundant tweens or skip steps.
local function wrapPreview(frame)
	local textElements = {}
	local title = frame:FindFirstChild("Title")
	if title then
		table.insert(textElements, title)
	end
	local textLabel = frame:FindFirstChild("TextLabel")
	if textLabel then
		table.insert(textElements, textLabel)
	end

	local shownBackgroundTransparency = frame.BackgroundTransparency
	local shownTextTransparency = {}
	for _, element in ipairs(textElements) do
		shownTextTransparency[element] = element.TextTransparency
	end

	-- Start fully hidden regardless of whatever was left set in Studio.
	frame.Visible = false
	frame.BackgroundTransparency = 1
	for _, element in ipairs(textElements) do
		element.TextTransparency = 1
	end

	local isVisible = false
	local activeToken = nil -- lets a new show()/hide() cancel a fade still in progress

	local function show()
		if isVisible then
			return
		end
		isVisible = true

		local token = {}
		activeToken = token

		frame.Visible = true
		local frameTween = TweenService:Create(frame, frameFadeInInfo, { BackgroundTransparency = shownBackgroundTransparency })
		frameTween:Play()
		frameTween.Completed:Connect(function()
			if activeToken ~= token then
				return -- superseded by a hide() that started before the frame finished fading in
			end
			for _, element in ipairs(textElements) do
				TweenService:Create(element, textFadeInfo, { TextTransparency = shownTextTransparency[element] }):Play()
			end
		end)
	end

	local function hide()
		if not isVisible then
			return
		end
		isVisible = false

		local token = {}
		activeToken = token

		for _, element in ipairs(textElements) do
			TweenService:Create(element, frameFadeOutInfo, { TextTransparency = 1 }):Play()
		end

		local frameTween = TweenService:Create(frame, frameFadeOutInfo, { BackgroundTransparency = 1 })
		frameTween:Play()
		frameTween.Completed:Connect(function()
			if activeToken ~= token then
				return -- a show() started again before this finished
			end
			frame.Visible = false
		end)
	end

	return show, hide
end

local survivorKillerShow, survivorKillerHide = wrapPreview(survivorKillerPreview)
local loadoutShow, loadoutHide = wrapPreview(loadoutPreview)
local shopShow, shopHide = wrapPreview(shopPreview)

-- Keyed by the same group names SidebuttonNavigation.client.lua uses.
local previewsByGroup = {
	Loadout = { button = loadoutButton, show = loadoutShow, hide = loadoutHide },
	Selection = { button = infoButton, show = survivorKillerShow, hide = survivorKillerHide },
	Shop = { button = shopButton, show = shopShow, hide = shopHide },
}

local isHovering = {} -- [groupName] = true/false
local isPageOpen = {} -- [groupName] = true/false

-- Visible if EITHER hovering OR the page is open -- only hidden once
-- both are false.
local function refresh(groupName)
	local entry = previewsByGroup[groupName]
	if not entry then
		return
	end

	if isHovering[groupName] or isPageOpen[groupName] then
		entry.show()
	else
		entry.hide()
	end
end

for groupName, entry in pairs(previewsByGroup) do
	entry.button.MouseEnter:Connect(function()
		isHovering[groupName] = true
		refresh(groupName)
	end)

	entry.button.MouseLeave:Connect(function()
		isHovering[groupName] = false
		refresh(groupName)
	end)
end

local sidebuttonOpenEvent = ReplicatedStorage:WaitForChild("SidebuttonVisualOpen")
local sidebuttonCloseEvent = ReplicatedStorage:WaitForChild("SidebuttonVisualClose")

sidebuttonOpenEvent.Event:Connect(function(groupName)
	isPageOpen[groupName] = true
	refresh(groupName)
end)

sidebuttonCloseEvent.Event:Connect(function(groupName)
	isPageOpen[groupName] = false
	refresh(groupName)
end)