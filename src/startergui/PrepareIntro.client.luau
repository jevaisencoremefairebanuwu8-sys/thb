-- PrepareIntro (LocalScript, StarterGui)

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local announceRemote = remotesFolder:WaitForChild("ObjectiveAnnouncement")

local TITLE_SPACING = 0.5

local ZOOM_START    = 0.2
local ZOOM_TIME     = 1.8
local HOLD_TIME     = 0.3
local SLIDE_TIME    = 0.9
local DISPLAY_TIME  = 3.0
local FADE_OUT_TIME = 1.0

local TITLE_START_Y = 0.31
local TITLE_END_Y   = 0.27
local SUB_START_Y   = 0.29
local SUB_END_Y     = 0.33

local CENTER_X    = 0.52   -- horizontal center — nudge this if it's off from the OBJECTIVE text
local TITLE_WIDTH = 0.75  -- was 0.7 — narrower box means TextScaled produces a smaller, tighter word
local SUB_WIDTH   = 0.5   -- was 0.75 — same idea for the longer subtitle line

local DISPLAY_ORDER = 100 -- above selection screens / other UI so the banner is never hidden

local montserrat = Font.fromName("Montserrat", Enum.FontWeight.Regular, Enum.FontStyle.Normal)

-- Adds the thin-space letter spacing to a title word, same trick as before,
-- just applied to whatever text comes in through the remote instead of a
-- hardcoded word.
local function applyTitleSpacing(word)
	local parts = {}
	for i = 1, #word do
		parts[i] = string.sub(word, i, i)
	end
	return table.concat(parts, string.rep(utf8.char(0x2009), TITLE_SPACING))
end

local queue = {}
local playing = false
local activeGui = nil -- the banner currently on screen (tracked by reference, never by name)

local function clearActiveGui()
	if activeGui then
		activeGui:Destroy()
		activeGui = nil
	end
end

local function playAnnouncement(titleWord, subtitleText)
	print("PrepareIntro: playing banner ->", titleWord, "|", subtitleText)

	clearActiveGui()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PrepareIntro"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = DISPLAY_ORDER
	screenGui.Parent = playerGui
	activeGui = screenGui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.new(CENTER_X, 0, TITLE_START_Y, 0)
	title.Size = UDim2.new(TITLE_WIDTH, 0, 0.09, 0)
	title.BackgroundTransparency = 1
	title.FontFace = montserrat
	title.Text = applyTitleSpacing(titleWord or "")
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.TextTransparency = 1
	title.Parent = screenGui

	local titleScale = Instance.new("UIScale")
	titleScale.Scale = ZOOM_START
	titleScale.Parent = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.Position = UDim2.new(CENTER_X, 0, SUB_START_Y, 0)
	subtitle.Size = UDim2.new(SUB_WIDTH, 0, 0.034, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.FontFace = montserrat
	subtitle.Text = subtitleText or ""
	subtitle.TextColor3 = Color3.fromRGB(230, 230, 230)
	subtitle.TextScaled = true
	subtitle.TextTransparency = 1
	subtitle.Parent = screenGui

	local zoomInfo = TweenInfo.new(ZOOM_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local fadeInfo = TweenInfo.new(ZOOM_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	TweenService:Create(titleScale, zoomInfo, { Scale = 1 }):Play()
	TweenService:Create(title, fadeInfo, { TextTransparency = 0 }):Play()
	task.wait(ZOOM_TIME) -- plain wait instead of Completed:Wait() so it can never hang

	task.wait(HOLD_TIME)

	local slideInfo = TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

	TweenService:Create(title, slideInfo, {
		Position = UDim2.new(CENTER_X, 0, TITLE_END_Y, 0),
	}):Play()

	TweenService:Create(subtitle, slideInfo, {
		Position = UDim2.new(CENTER_X, 0, SUB_END_Y, 0),
		TextTransparency = 0,
	}):Play()
	task.wait(SLIDE_TIME)

	task.wait(DISPLAY_TIME)

	local fadeOutInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(title, fadeOutInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitle, fadeOutInfo, { TextTransparency = 1 }):Play()
	task.wait(FADE_OUT_TIME)

	clearActiveGui()
	print("PrepareIntro: banner finished ->", titleWord)
end

local function processQueue()
	if playing then
		return
	end
	playing = true
	while #queue > 0 do
		local nextAnnouncement = table.remove(queue, 1)
		-- pcall so one bad banner can't leave `playing` stuck on true forever
		local ok, err = pcall(playAnnouncement, nextAnnouncement.text, nextAnnouncement.subtext)
		if not ok then
			warn("PrepareIntro: banner errored:", err)
			clearActiveGui()
		end
	end
	playing = false
end

announceRemote.OnClientEvent:Connect(function(text, subtext)
	print("PrepareIntro: received ->", text, "|", subtext, "| queued:", #queue, "| playing:", playing)
	table.insert(queue, { text = text, subtext = subtext })
	processQueue()
end)

print("PrepareIntro loaded.")