-- LoadoutPageToggle.client.lua

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("LobbyUI") -- adjust if named differently

local killerPage = screenGui:WaitForChild("KillerLoadoutPage"):WaitForChild("Frame")
local survivorPage = screenGui:WaitForChild("SurvivorLoadoutPage"):WaitForChild("Frame")

local killerFrame = killerPage
local survivorFrame = survivorPage

local swapToSurvivorFrame = killerFrame:WaitForChild("SwapToSurvivor")
local swapToKillerFrame = survivorFrame:WaitForChild("SwapToKiller")

local swapToSurvivorButton = swapToSurvivorFrame:WaitForChild("ClickArea")
local swapToKillerButton = swapToKillerFrame:WaitForChild("ClickArea")

-- Same pop open/close animation as ShopUI (SidebuttonNavigation.client.lua):
-- UIScale tweened 0 -> 1 on open (with a slight overshoot), 1 -> 0 on
-- close, Visible only flips once the close tween finishes.
local ANIMATION_TIME = 0.2
local OPEN_TWEEN_INFO = TweenInfo.new(ANIMATION_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_TWEEN_INFO = TweenInfo.new(ANIMATION_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function getOrCreateScale(frame)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if not scale then
		-- UIScale scales around the frame's own AnchorPoint. Most frames
		-- default to (0, 0) (top-left), which is why this was visually
		-- popping out of the top-left corner instead of the center.
		-- Re-anchor to center once, shifting Position by half the
		-- frame's current size so it doesn't visually jump when the
		-- anchor point changes.
		if frame.AnchorPoint.X ~= 0.5 or frame.AnchorPoint.Y ~= 0.5 then
			local size = frame.AbsoluteSize
			local pos = frame.Position
			frame.Position = UDim2.new(pos.X.Scale, pos.X.Offset + size.X / 2, pos.Y.Scale, pos.Y.Offset + size.Y / 2)
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
		end

		scale = Instance.new("UIScale")
		scale.Parent = frame
	end
	return scale
end

local function animateOpenFrame(frame)
	local scale = getOrCreateScale(frame)
	scale.Scale = 0
	frame.Visible = true
	TweenService:Create(scale, OPEN_TWEEN_INFO, { Scale = 1 }):Play()
end

local function animateCloseFrame(frame, onComplete)
	if not frame.Visible then
		if onComplete then
			onComplete()
		end
		return
	end
	local scale = getOrCreateScale(frame)
	local tween = TweenService:Create(scale, CLOSE_TWEEN_INFO, { Scale = 0 })
	tween.Completed:Connect(function()
		frame.Visible = false
		scale.Scale = 1 -- reset so the next open starts from the right state
		if onComplete then
			onComplete()
		end
	end)
	tween:Play()
end

local function showKillerPage()
	animateCloseFrame(survivorPage, function()
		animateOpenFrame(killerPage)
	end)
end

local function showSurvivorPage()
	animateCloseFrame(killerPage, function()
		animateOpenFrame(survivorPage)
	end)
end

swapToSurvivorButton.MouseButton1Click:Connect(showSurvivorPage)
swapToKillerButton.MouseButton1Click:Connect(showKillerPage)

-- NOTE: no longer calling showKillerPage() here. It used to run
-- unconditionally on load, which force-opened the whole Loadout page
-- regardless of SidebuttonNavigation.client.lua's state -- this page's
-- overall visibility is SidebuttonNavigation's job now (it already
-- defaults to the killer view when it opens the Loadout group). This
-- script only needs to handle the swap buttons.