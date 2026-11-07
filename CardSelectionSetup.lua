-- CardSelectionSetup.lua (ModuleScript, ReplicatedStorage.Shared)
-- Shared logic for any ShopUI page that has a List > ScrollingFrame of
-- cards and a matching Info panel of per-item frames (e.g.
-- SurvivorsContainer + Info.NinjaFrame/MedicFrame/etc., or
-- KillersContainer + Info.<Killer>Frame).
--
-- For a given <containerName> (e.g. "SurvivorsContainer"), clicking a
-- card in <containerName>.List.ScrollingFrame:
--   - shows that card's matching Info.<Item>Frame (matched by
--     normalizing the card's TitleLabel text against each Info frame's
--     name -- cards themselves are NOT individually renamed, they're
--     all still the default "Frame" clone name) and hides the other frames
--   - shows that card's "HighlightedBackground" and hides every other
--     card's (only one card is ever "selected" at a time) -- cloned
--     from whichever card already has one authored in Studio
--   - hides that card's own "Background" while selected
--   - changes that card's TitleLabel/ImageLabel color while selected
-- The first card is auto-selected every time the shop is opened.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LOOKUP_TIMEOUT = 5
local SELECTED_HIGHLIGHT_COLOR = Color3.fromRGB(198, 176, 12)

local CardSelectionSetup = {}

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

-- Finds a "HighlightedBackground" on ANY of the given cards, to use as
-- a clone source for the ones that don't have one.
local function findHighlightTemplate(cards)
	for _, card in ipairs(cards) do
		local existing = card:FindFirstChild("HighlightedBackground")
		if existing then
			return existing
		end
	end
	return nil
end

-- Returns the card's HighlightedBackground, cloning it from the
-- template if this card doesn't have one yet.
local function ensureHighlight(card, template)
	local existing = card:FindFirstChild("HighlightedBackground")
	if existing then
		existing.Active = false -- defensive: never let it block clicks on the card
		return existing
	end
	if not template then
		return nil
	end

	local clone = template:Clone()
	clone.Visible = false -- only the selection logic below should ever show one
	clone.Active = false
	clone.Parent = card
	return clone
end

-- Leaves whichever ONE Info frame was already Visible (if any) as the
-- starting default, and forces every other one to false -- in case more
-- than one was accidentally left visible in Studio.
local function normalizeInitialInfoState(infoFrames)
	local alreadyVisible = nil
	for _, frame in pairs(infoFrames) do
		if frame.Visible and not alreadyVisible then
			alreadyVisible = frame
		end
	end
	for _, frame in pairs(infoFrames) do
		frame.Visible = (frame == alreadyVisible)
	end
end

local function normalizeItemName(text)
	text = text:upper()
	text = text:gsub("^THE", "") -- strip a leading "THE", with or without a following space
	text = text:gsub("[^%u]", "") -- strip anything left that isn't A-Z
	return text
end

local function setupCardSelection(shopUI, containerName, scriptLabel)
	local container = shopUI:WaitForChild("Container", LOOKUP_TIMEOUT)
	local mainFrame = container and container:WaitForChild("MainFrame", LOOKUP_TIMEOUT)
	local itemsContainer = mainFrame and mainFrame:WaitForChild(containerName, LOOKUP_TIMEOUT)
	if not itemsContainer then
		warn(scriptLabel .. ": couldn't find Container.MainFrame." .. containerName .. " within " .. LOOKUP_TIMEOUT .. "s.")
		return
	end

	local info = itemsContainer:WaitForChild("Info", LOOKUP_TIMEOUT)
	local list = itemsContainer:WaitForChild("List", LOOKUP_TIMEOUT)
	local scrollingFrame = list and list:WaitForChild("ScrollingFrame", LOOKUP_TIMEOUT)

	if not (info and scrollingFrame) then
		warn(scriptLabel .. ": couldn't find Info or List.ScrollingFrame within " .. LOOKUP_TIMEOUT .. "s.")
		return
	end

	-- Every child of Info is one of the per-item frames. Keyed by a
	-- normalized version of the name with "Frame" stripped (e.g.
	-- "NinjaFrame" -> "NINJA") so it can be matched against each card's
	-- TitleLabel text below.
	local infoFrames = {}
	local infoFramesByKey = {}
	for _, child in ipairs(info:GetChildren()) do
		if child:IsA("GuiObject") then
			infoFrames[child.Name] = child
			local baseName = child.Name:gsub("Frame$", "")
			infoFramesByKey[normalizeItemName(baseName)] = child
		end
	end
	normalizeInitialInfoState(infoFrames)

	print(scriptLabel .. ": Info frames found:")
	for name, frame in pairs(infoFrames) do
		local baseName = name:gsub("Frame$", "")
		print("  - '" .. name .. "' -> key '" .. normalizeItemName(baseName) .. "'")
	end

	-- Cards are NOT individually renamed (they're all still just
	-- "Frame", the default clone name) -- so matching has to go by each
	-- card's TitleLabel text instead of the card's own instance name.
	local cards = {}
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") and child:FindFirstChild("TitleLabel") then
			table.insert(cards, child)
		end
	end

	print(scriptLabel .. ": cards found:")
	for _, card in ipairs(cards) do
		local titleLabel = card:FindFirstChild("TitleLabel")
		local titleText = titleLabel and titleLabel.Text
		print("  - title '" .. tostring(titleText) .. "' -> key '" .. tostring(titleText and normalizeItemName(titleText)) .. "'")
	end

	local highlightTemplate = findHighlightTemplate(cards)
	if not highlightTemplate then
		warn(scriptLabel .. ": no card has a 'HighlightedBackground' to copy -- add one to a card in Studio first.")
	end

	-- entries[card] = { highlight, background, infoFrame, titleLabel, defaultTitleColor, imageLabel, defaultImageColor }
	local entries = {}
	local function buildEntry(card)
		local titleLabel = card:FindFirstChild("TitleLabel")
		local imageLabel = card:FindFirstChild("ImageLabel")
		local key = titleLabel and normalizeItemName(titleLabel.Text)
		local infoFrame = key and infoFramesByKey[key]
		if not infoFrame then
			warn(scriptLabel .. ": no Info frame matches title '" .. tostring(titleLabel and titleLabel.Text) .. "' (key '" .. tostring(key) .. "').")
		end
		return {
			highlight = ensureHighlight(card, highlightTemplate),
			background = card:FindFirstChild("Background"),
			infoFrame = infoFrame,
			titleLabel = titleLabel,
			defaultTitleColor = titleLabel and titleLabel.TextColor3,
			imageLabel = imageLabel,
			defaultImageColor = imageLabel and imageLabel.ImageColor3,
		}
	end

	for _, card in ipairs(cards) do
		entries[card] = buildEntry(card)
	end

	local function selectCard(chosenCard)
		local chosenEntry = entries[chosenCard]
		if not chosenEntry then
			return
		end

		for card, entry in pairs(entries) do
			local isChosen = (card == chosenCard)
			if entry.highlight then
				entry.highlight.Visible = isChosen
			end
			if entry.background then
				entry.background.Visible = not isChosen
			end
			if entry.titleLabel then
				entry.titleLabel.TextColor3 = isChosen and SELECTED_HIGHLIGHT_COLOR or entry.defaultTitleColor
			end
			if entry.imageLabel then
				entry.imageLabel.ImageColor3 = isChosen and SELECTED_HIGHLIGHT_COLOR or entry.defaultImageColor
			end
		end

		if chosenEntry.infoFrame then
			for _, frame in pairs(infoFrames) do
				frame.Visible = false
			end
			chosenEntry.infoFrame.Visible = true
		else
			warn(scriptLabel .. ": '" .. chosenCard.Name .. "' has no matching Info frame -- leaving Info panel as-is instead of blanking it.")
		end
	end

	local function wireCard(card)
		local clickTarget = card:IsA("GuiButton") and card or card:FindFirstChildWhichIsA("GuiButton", true)
		if not clickTarget then
			warn(scriptLabel .. ": card '" .. card.Name .. "' has no clickable GuiButton, can't wire it up.")
			return
		end

		clickTarget.Active = true
		pcall(function()
			clickTarget.Interactable = true
		end)

		clickTarget.Activated:Connect(function()
			selectCard(card)
		end)
	end

	for _, card in ipairs(cards) do
		wireCard(card)
	end

	-- Any card added later (e.g. built/loaded dynamically) gets picked
	-- up too, instead of only whatever existed at script load.
	scrollingFrame.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			task.defer(function()
				if child:FindFirstChild("TitleLabel") then
					entries[child] = buildEntry(child)
					wireCard(child)
				end
			end)
		end
	end)

	-- Auto-select the first card every time the shop is OPENED (not
	-- just once at script load) -- without this, the panel could land
	-- on a stale/no selection until the player manually clicks a card.
	local function selectFirstCard()
		if cards[1] then
			selectCard(cards[1])
		end
	end

	if container.Visible then
		selectFirstCard()
	end
	container:GetPropertyChangedSignal("Visible"):Connect(function()
		if container.Visible then
			selectFirstCard()
		end
	end)
end

-- Call once per page, e.g.:
--   CardSelectionSetup.Init("SurvivorsContainer", "SurvivorCardSelection")
--   CardSelectionSetup.Init("KillersContainer", "KillerCardSelection")
function CardSelectionSetup.Init(containerName, scriptLabel)
	scriptLabel = scriptLabel or ("CardSelectionSetup:" .. containerName)

	local function initialize()
		local shopUI = waitForShopUI(LOOKUP_TIMEOUT)
		if not shopUI then
			warn(scriptLabel .. ": no 'ShopUI' found within " .. LOOKUP_TIMEOUT .. "s.")
			return
		end
		setupCardSelection(shopUI, containerName, scriptLabel)
	end

	initialize()

	-- Re-wire automatically if ShopUI is ever recreated (respawn with
	-- ResetOnSpawn still true, or anything else that replaces it).
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "ShopUI" then
			setupCardSelection(child, containerName, scriptLabel)
		end
	end)
end

return CardSelectionSetup