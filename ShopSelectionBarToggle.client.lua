-- ShopSelectionBarToggle.client.lua
-- Inside ShopUI's SelectionBar, each header (Killers, Shards&Boosters,
-- Survivors) has its own "Selected" ImageLabel child. Clicking a header
-- shows its own Selected label and hides every other header's, and
-- swaps which "<HeaderName>Container" sibling under MainFrame is visible.
--
-- IMPORTANT: ScreenGui.ResetOnSpawn defaults to true in Roblox, which
-- means PlayerGui.ShopUI gets DESTROYED and re-cloned from
-- StarterGui.ShopUI every time the character respawns -- a fresh,
-- completely unwired copy. Set ShopUI.ResetOnSpawn to false in Studio
-- (it's a persistent menu, not per-life state). This script also
-- re-runs setup automatically if a new ShopUI ever appears, so it stays
-- working even if that property gets missed.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LOOKUP_TIMEOUT = 5

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

local function setupShopSelectionBar(shopUI)
	local container = shopUI:WaitForChild("Container", LOOKUP_TIMEOUT)
	local mainFrame = container and container:WaitForChild("MainFrame", LOOKUP_TIMEOUT)
	local selectionBar = mainFrame and mainFrame:WaitForChild("SelectionBar", LOOKUP_TIMEOUT)

	if not selectionBar then
		warn("ShopSelectionBarToggle: couldn't find Container.MainFrame.SelectionBar within " .. LOOKUP_TIMEOUT .. "s.")
		return
	end

	-- Collect every header that actually has a "Selected" child --
	-- anything else under SelectionBar (padding, layout objects, etc.)
	-- is skipped. Each header's matching content container is a sibling
	-- under mainFrame, named "<HeaderName>Container".
	local headers = {}
	for _, child in ipairs(selectionBar:GetChildren()) do
		local selectedLabel = child:FindFirstChild("Selected")
		if selectedLabel then
			local matchingContainer = mainFrame:FindFirstChild(child.Name .. "Container")
			if not matchingContainer then
				warn("ShopSelectionBarToggle: no '" .. child.Name .. "Container' found under MainFrame -- that header's content won't switch.")
			end
			table.insert(headers, { instance = child, selectedLabel = selectedLabel, container = matchingContainer })
		end
	end

	if #headers == 0 then
		warn("ShopSelectionBarToggle: SelectionBar has no children with a 'Selected' child -- nothing to wire up.")
		return
	end

	local FADE_DURATION = 0.2

	local function fadeSelectedIn(selectedLabel)
		selectedLabel.Visible = true
		selectedLabel.ImageTransparency = 1
		TweenService:Create(selectedLabel, TweenInfo.new(FADE_DURATION), { ImageTransparency = 0 }):Play()
	end

	local function fadeSelectedOut(selectedLabel)
		if not selectedLabel.Visible then
			return
		end
		local tween = TweenService:Create(selectedLabel, TweenInfo.new(FADE_DURATION), { ImageTransparency = 1 })
		tween.Completed:Connect(function()
			selectedLabel.Visible = false
		end)
		tween:Play()
	end

	local function selectHeader(chosenHeader)
		for _, header in ipairs(headers) do
			local isChosen = header.instance == chosenHeader
			if isChosen then
				fadeSelectedIn(header.selectedLabel)
			else
				fadeSelectedOut(header.selectedLabel)
			end
			if header.container then
				header.container.Visible = isChosen
			end
		end
	end

	-- Whatever was left visible in Studio might be stale/inconsistent
	-- (e.g. multiple containers visible at once, or the wrong one) --
	-- clicking a header already fixes this, since selectHeader() forces
	-- exactly one to be visible. This does the same thing automatically
	-- every time the shop is OPENED, not just once at script load, so
	-- you don't have to click a header manually first for anything to
	-- respond. Picks whichever header currently looks selected (its
	-- Selected label or container already visible) as the one to land
	-- on, falling back to the first header if none clearly are.
	local function selectDefaultHeader()
		local defaultHeader = headers[1]
		for _, header in ipairs(headers) do
			if header.selectedLabel.Visible or (header.container and header.container.Visible) then
				defaultHeader = header
				break
			end
		end
		selectHeader(defaultHeader.instance)
	end

	if container.Visible then
		selectDefaultHeader()
	end
	container:GetPropertyChangedSignal("Visible"):Connect(function()
		if container.Visible then
			selectDefaultHeader()
		end
	end)

	-- Prevent Background (rendered on top of the headers if it shares a
	-- ZIndex with them) from ever intercepting clicks meant for them.
	local background = selectionBar:FindFirstChild("Background")
	if background then
		background.Active = false
	end

	for _, header in ipairs(headers) do
		local clickTarget = header.instance:IsA("GuiButton")
			and header.instance
			or header.instance:FindFirstChildWhichIsA("GuiButton", true)

		if clickTarget then
			clickTarget.Active = true
			pcall(function()
				clickTarget.Interactable = true
			end)
			clickTarget.Activated:Connect(function()
				selectHeader(header.instance)
			end)
		else
			warn("ShopSelectionBarToggle: '" .. header.instance.Name .. "' has no clickable GuiButton, can't wire it up.")
		end
	end
end

local function initialize()
	local shopUI = waitForShopUI(LOOKUP_TIMEOUT)
	if not shopUI then
		warn("ShopSelectionBarToggle: no 'ShopUI' found within " .. LOOKUP_TIMEOUT .. "s.")
		return
	end
	setupShopSelectionBar(shopUI)
end

initialize()

-- Re-wire automatically if ShopUI ever gets recreated (respawn with
-- ResetOnSpawn still true, or anything else that replaces it).
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "ShopUI" then
		setupShopSelectionBar(child)
	end
end)