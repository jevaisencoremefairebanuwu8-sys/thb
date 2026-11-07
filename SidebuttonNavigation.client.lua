-- SidebuttonNavigation.client.lua
-- The 3 persistent left-side buttons switch between major page groups.
-- LoadoutButton -> Killer/SurvivorLoadoutPage
-- SurvivorKillerInfoPage (button) -> KillerSelection/SurvivorSelection
-- SurvivorKillerShop -> ShopUI (own ScreenGui) > Container > MainFrame
--
-- Everything Shop-related uses a timeout on WaitForChild and nil-guards
-- throughout. A plain WaitForChild with no timeout blocks FOREVER if the
-- path is wrong, which previously took down Loadout/Selection wiring
-- with it (both are wired further down in this same script). If my
-- assumption about ShopUI's location/structure is still off, this way
-- only the Shop button silently no-ops instead of breaking everything.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("LobbyUI") -- adjust if named differently
local otherFolder = screenGui:WaitForChild("Other")
local sideButtons = otherFolder:WaitForChild("Sidebuttons")

local loadoutButton = sideButtons:WaitForChild("LoadoutButton")
local infoButton = sideButtons:WaitForChild("SurvivorKillerInfoPage")
local shopButton = sideButtons:WaitForChild("SurvivorKillerShop")

local killerLoadoutPage = screenGui:WaitForChild("KillerLoadoutPage"):WaitForChild("Frame")
local survivorLoadoutPage = screenGui:WaitForChild("SurvivorLoadoutPage"):WaitForChild("Frame")
local killerSelectionPage = screenGui:WaitForChild("KillerSelection"):WaitForChild("Killers")
local survivorSelectionPage = screenGui:WaitForChild("SurvivorSelection"):WaitForChild("Survivors")

-- Shop lookups: 5s timeout each, never blocks forever. If any piece is
-- missing, shopContainer/shopMainFrame end up nil and every function
-- below checks for that before touching them.
--
-- Checks both PlayerGui and StarterGui for ShopUI. Normally everything
-- in StarterGui gets auto-copied into PlayerGui when the player joins,
-- so PlayerGui is where it SHOULD be at runtime -- but checking both
-- means this works either way without needing to know why.
local StarterGui = game:GetService("StarterGui")
local SHOP_LOOKUP_TIMEOUT = 5

local function waitForShopUI(timeout)
	local deadline = tick() + timeout
	repeat
		local found = playerGui:FindFirstChild("ShopUI") or StarterGui:FindFirstChild("ShopUI")
		if found then
			return found
		end
		task.wait(0.1)
	until tick() >= deadline
	return nil
end

local shopUI = waitForShopUI(SHOP_LOOKUP_TIMEOUT)
if not shopUI then
	warn("SidebuttonNavigation: no 'ShopUI' found under PlayerGui or StarterGui within " .. SHOP_LOOKUP_TIMEOUT .. "s -- Shop button will not open anything until this is fixed.")
end
local shopContainer = shopUI and shopUI:WaitForChild("Container", SHOP_LOOKUP_TIMEOUT)
if shopUI and not shopContainer then
	warn("SidebuttonNavigation: ShopUI has no 'Container' child within " .. SHOP_LOOKUP_TIMEOUT .. "s.")
end
local shopMainFrame = shopContainer and shopContainer:WaitForChild("MainFrame", SHOP_LOOKUP_TIMEOUT)
if shopContainer and not shopMainFrame then
	warn("SidebuttonNavigation: ShopUI.Container has no 'MainFrame' child within " .. SHOP_LOOKUP_TIMEOUT .. "s.")
end

-- ShopUI is a SEPARATE ScreenGui from LobbyUI (which the Sidebuttons
-- live in), so their stacking/input priority is governed by
-- DisplayOrder, not sibling order. If ShopUI's DisplayOrder ends up
-- equal-or-higher than LobbyUI's, whatever's covering the sidebuttons'
-- screen area (most likely a full-screen Container backdrop) intercepts
-- clicks meant for them -- which is why closing/switching away from the
-- shop via a sidebutton wasn't working. Force LobbyUI above it, always,
-- regardless of whatever was set in Studio.
if shopUI then
	screenGui.DisplayOrder = math.max(screenGui.DisplayOrder, shopUI.DisplayOrder + 1)
end

-- One-way signal to SidebuttonToggle.client.lua: "this group just closed
-- (or is about to be replaced by another one), revert its button's
-- visual." Created here if SidebuttonToggle hasn't run yet; either
-- script can create it first, both just need to agree on the name.
local sidebuttonCloseEvent = ReplicatedStorage:FindFirstChild("SidebuttonVisualClose")
if not sidebuttonCloseEvent then
	sidebuttonCloseEvent = Instance.new("BindableEvent")
	sidebuttonCloseEvent.Name = "SidebuttonVisualClose"
	sidebuttonCloseEvent.Parent = ReplicatedStorage
end

-- Companion signal for SidebuttonPreview.client.lua: "this group just
-- opened." Unlike the toggle script, the preview tooltip needs to know
-- BOTH when a group opens and when it closes (to know whether to keep
-- itself visible even without a hover), so this one's new.
local sidebuttonOpenEvent = ReplicatedStorage:FindFirstChild("SidebuttonVisualOpen")
if not sidebuttonOpenEvent then
	sidebuttonOpenEvent = Instance.new("BindableEvent")
	sidebuttonOpenEvent.Name = "SidebuttonVisualOpen"
	sidebuttonOpenEvent.Parent = ReplicatedStorage
end

-- === Background blur ===
-- BlurEffect lives in Lighting and only blurs the 3D world/viewport --
-- ScreenGui elements (all your menu panels) render on top and are
-- never affected, so this naturally satisfies "everything except UI".
local BLUR_SIZE = 24
local BLUR_FADE_TIME = 0.25

local menuBlur = Lighting:FindFirstChild("MenuBlur")
if not menuBlur then
	menuBlur = Instance.new("BlurEffect")
	menuBlur.Name = "MenuBlur"
	menuBlur.Size = 0
	menuBlur.Parent = Lighting
end

local blurInTween = TweenService:Create(
	menuBlur,
	TweenInfo.new(BLUR_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{ Size = BLUR_SIZE }
)
local blurOutTween = TweenService:Create(
	menuBlur,
	TweenInfo.new(BLUR_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{ Size = 0 }
)

local function fadeBlurIn()
	blurOutTween:Cancel()
	blurInTween:Play()
end

local function fadeBlurOut()
	blurInTween:Cancel()
	blurOutTween:Play()
end
-- === End background blur ===

-- === Open/close animation ===
-- Each panel gets a UIScale tweened 0 -> 1 on open (with a slight
-- overshoot for a "pop" feel) and 1 -> 0 on close. UIScale works on any
-- Frame regardless of what's inside it, and plays nicely alongside
-- UIAspectRatioConstraint. Visible has to stay true for the whole close
-- tween and only flips to false once it finishes, or the panel would
-- just vanish instantly instead of shrinking away.
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

-- Animates frame's scale down to 0, THEN sets Visible = false, THEN
-- calls onComplete. If frame isn't currently visible, skips straight to
-- onComplete (nothing to animate).
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
-- === End open/close animation ===

local currentOpenGroup = nil -- "Loadout", "Selection", "Shop", or nil

-- Which frame(s) belong to each group -- only one of a group's frames
-- is ever actually visible at a time (e.g. Loadout defaults to killer
-- view, but the user may have swapped to survivor view before closing).
local loadoutFrames = { killerLoadoutPage, survivorLoadoutPage }
local selectionFrames = { killerSelectionPage, survivorSelectionPage }
local shopFrames = shopMainFrame and { shopMainFrame } or {}

-- Instant, no animation -- only used once, for the very first frame
-- before anything has ever been opened.
local function hideAllGroupsInstant()
	killerLoadoutPage.Visible = false
	survivorLoadoutPage.Visible = false
	killerSelectionPage.Visible = false
	survivorSelectionPage.Visible = false
	if shopContainer then
		shopContainer.Visible = false
	end
	if shopMainFrame then
		shopMainFrame.Visible = false
	end
end

-- Animates closed whichever single frame in `frames` is currently
-- visible (there's at most one), then calls onComplete.
local function closeGroupFrames(frames, onComplete)
	for _, frame in ipairs(frames) do
		if frame.Visible then
			animateCloseFrame(frame, onComplete)
			return
		end
	end
	if onComplete then
		onComplete()
	end
end

local function closeCurrentGroup(onComplete)
	if currentOpenGroup == "Loadout" then
		closeGroupFrames(loadoutFrames, onComplete)
	elseif currentOpenGroup == "Selection" then
		closeGroupFrames(selectionFrames, onComplete)
	elseif currentOpenGroup == "Shop" then
		closeGroupFrames(shopFrames, function()
			if shopContainer then
				shopContainer.Visible = false
			end
			if onComplete then
				onComplete()
			end
		end)
	elseif onComplete then
		onComplete()
	end
end

-- Used by CloseButton and by re-clicking an already-open sidebutton.
local function closeMenu()
	if currentOpenGroup then
		sidebuttonCloseEvent:Fire(currentOpenGroup)
	end
	closeCurrentGroup(function()
		currentOpenGroup = nil
	end)
	fadeBlurOut()
end

local function showLoadoutGroup()
	closeCurrentGroup(function()
		survivorLoadoutPage.Visible = false
		animateOpenFrame(killerLoadoutPage) -- defaults to killer view when opened
	end)
	fadeBlurIn()
end

local function showSelectionGroup()
	closeCurrentGroup(function()
		survivorSelectionPage.Visible = false
		animateOpenFrame(killerSelectionPage) -- defaults to killer view when opened
	end)
	fadeBlurIn()
end

local function showShopGroup()
	if not (shopContainer and shopMainFrame) then
		warn("SidebuttonNavigation: can't open Shop, ShopUI wasn't found correctly (see earlier warning).")
		return
	end
	closeCurrentGroup(function()
		shopContainer.Visible = true
		animateOpenFrame(shopMainFrame)
	end)
	fadeBlurIn()
end

local function setupCloseButton(pageFrame)
	local closeButtonFrame = pageFrame:FindFirstChild("CloseButton")
	if not closeButtonFrame then
		return
	end
	local imageButton = closeButtonFrame:FindFirstChildOfClass("ImageButton")
	if imageButton then
		imageButton.MouseButton1Click:Connect(closeMenu)
	end
end

setupCloseButton(killerLoadoutPage)
setupCloseButton(survivorLoadoutPage)
setupCloseButton(killerSelectionPage)
setupCloseButton(survivorSelectionPage)

-- ShopUI's CloseButton is a different shape from the other pages: it's
-- directly an ImageButton inside "TopBar", not a Frame wrapping one --
-- so it needs its own wiring instead of going through setupCloseButton.
-- Defensive: if that assumption is wrong and CloseButton is actually a
-- container instead, search inside it for a real button rather than
-- silently failing.
if shopMainFrame then
	local shopTopBar = shopMainFrame:WaitForChild("TopBar", SHOP_LOOKUP_TIMEOUT)
	if not shopTopBar then
		warn("SidebuttonNavigation: ShopUI's MainFrame has no 'TopBar' within " .. SHOP_LOOKUP_TIMEOUT .. "s.")
	else
		local closeButtonInstance = shopTopBar:WaitForChild("CloseButton", SHOP_LOOKUP_TIMEOUT)
		if not closeButtonInstance then
		warn("SidebuttonNavigation: 'TopBar' has no 'CloseButton' within " .. SHOP_LOOKUP_TIMEOUT .. "s.")
		else
			local shopCloseButton = closeButtonInstance:IsA("GuiButton")
				and closeButtonInstance
				or closeButtonInstance:FindFirstChildWhichIsA("GuiButton", true)

			if shopCloseButton then
				shopCloseButton.MouseButton1Click:Connect(closeMenu)
			else
				warn("SidebuttonNavigation: 'CloseButton' (" .. closeButtonInstance.ClassName .. ") isn't a button and has no button inside it -- can't wire a click handler.")
			end
		end
	end
end

local function toggleGroup(groupName, showFunction)
	if currentOpenGroup == groupName then
		closeMenu()
	else
		if currentOpenGroup then
			sidebuttonCloseEvent:Fire(currentOpenGroup)
		end
		showFunction()
		currentOpenGroup = groupName
		sidebuttonOpenEvent:Fire(groupName)
	end
end

if loadoutButton:IsA("GuiButton") then
	loadoutButton.MouseButton1Click:Connect(function()
		toggleGroup("Loadout", showLoadoutGroup)
	end)
end

if infoButton:IsA("GuiButton") then
	infoButton.MouseButton1Click:Connect(function()
		toggleGroup("Selection", showSelectionGroup)
	end)
end

if shopButton:IsA("GuiButton") then
	shopButton.MouseButton1Click:Connect(function()
		toggleGroup("Shop", showShopGroup)
	end)
end

-- Start with everything hidden until a sidebutton is clicked
hideAllGroupsInstant()