-- KillerSelectionUI.client.lua (diagnostic)
-- Generic version: works with however many killer cards exist inside
-- CardContainer. Each card must be named "Card_<TemplateName>".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
print("KSUI 1. Got PlayerGui")

local promptRemote = ReplicatedStorage:WaitForChild("KillerSelectionPrompt")
print("KSUI 2. Got KillerSelectionPrompt remote")

local selectionRemote = ReplicatedStorage:WaitForChild("KillerSelectionChosen")
print("KSUI 3. Got KillerSelectionChosen remote")

local screenGui = playerGui:WaitForChild("KillerSelectionGui", 15)
print("KSUI 4. KillerSelectionGui =", screenGui)

local frame = screenGui:WaitForChild("Frame", 15)
print("KSUI 5. Frame =", frame)

local timerLabel = frame:WaitForChild("TimerLabel", 15)
print("KSUI 6. TimerLabel =", timerLabel)

local cardContainer = screenGui:WaitForChild("CardContainer", 15)
print("KSUI 7. CardContainer =", cardContainer, "-- ALL WAITFORCHILDS PASSED")

-- Force this above LobbyUI (and anything else) so it can't get hidden
-- behind another ScreenGui sitting at the same/default DisplayOrder.
screenGui.DisplayOrder = 10
print("KSUI: DisplayOrder set to", screenGui.DisplayOrder)

screenGui.Enabled = false

-- Click feedback: the chosen card's border fades to red. The choice is sent
-- right away, but the GUI stays open (showing the countdown) until the server
-- closes it when the full selection time is up.
local FADE_COLOR = Color3.fromRGB(255, 0, 0)
local FADE_TIME = 0.6

local countdownTask = nil
local selectionLocked = false
local activeTween = nil
local originalBorderColors = {} -- [card] = original BorderColor3

local function resetCards()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	for card, color in pairs(originalBorderColors) do
		card.BorderColor3 = color
	end
	selectionLocked = false
end

local function chooseKiller(card, killerTemplateName)
	if selectionLocked then
		return -- already picked one, ignore extra clicks
	end
	selectionLocked = true

	selectionRemote:FireServer(killerTemplateName)

	local tween = TweenService:Create(
		card,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ BorderColor3 = FADE_COLOR }
	)
	activeTween = tween
	tween:Play()
end

for _, card in ipairs(cardContainer:GetChildren()) do
	if card.Name:sub(1, 5) == "Card_" then
		local templateName = card.Name:sub(6)
		print("Wiring up card:", card.Name, "-> templateName:", templateName)

		originalBorderColors[card] = card.BorderColor3

		local clickable = card
		if not card:IsA("GuiButton") then
			local existingButton = card:FindFirstChild("ClickButton")
			if existingButton then
				clickable = existingButton
			end
		end

		print("  clickable:", clickable, "IsA GuiButton:", clickable:IsA("GuiButton"))

		if clickable:IsA("GuiButton") then
			clickable.MouseButton1Click:Connect(function()
				print("Clicked card for:", templateName)
				chooseKiller(card, templateName)
			end)
		end
	end
end

print("KSUI 8. All cards wired, now listening for prompt remote")

promptRemote.OnClientEvent:Connect(function(shouldShow, selectionTime)
	print("KSUI: promptRemote fired! shouldShow =", shouldShow, "selectionTime =", selectionTime)

	if shouldShow then
		resetCards() -- borders back to normal, selection unlocked for this round

		screenGui.Enabled = true
		frame.Visible = true
		cardContainer.Visible = true

		print("KSUI: screenGui.Enabled =", screenGui.Enabled, "| DisplayOrder =", screenGui.DisplayOrder)
		print("KSUI: frame.Visible =", frame.Visible, "| Position =", frame.Position, "| Size =", frame.Size, "| BackgroundTransparency =", frame.BackgroundTransparency, "| ZIndex =", frame.ZIndex)
		print("KSUI: cardContainer.Visible =", cardContainer.Visible, "| Position =", cardContainer.Position, "| Size =", cardContainer.Size)
		print("KSUI: cardContainer child count =", #cardContainer:GetChildren())
		for _, card in ipairs(cardContainer:GetChildren()) do
			print("  card:", card.Name, "| Visible:", card:IsA("GuiObject") and card.Visible or "N/A", "| Size:", card:IsA("GuiObject") and card.Size or "N/A")
		end

		local remaining = selectionTime

		if countdownTask then
			task.cancel(countdownTask)
		end

		countdownTask = task.spawn(function()
			while remaining > 0 and screenGui.Enabled do
				timerLabel.Text = math.ceil(remaining) .. "s"
				task.wait(0.25)
				remaining -= 0.25
			end
		end)
	else
		screenGui.Enabled = false
		if countdownTask then
			task.cancel(countdownTask)
			countdownTask = nil
		end
	end
end)