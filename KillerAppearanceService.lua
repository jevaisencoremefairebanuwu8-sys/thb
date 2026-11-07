-- KillerAppearanceService.lua (ModuleScript)
-- Hides the default character and welds the selected killer model on
-- top whenever a player is the Killer. Uses whichever template name is
-- stored in the player's "SelectedKiller" attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_KILLER = "ScarecrowModel"

local templatesFolder = ReplicatedStorage:WaitForChild("Templates")

local KillerAppearanceService = {}

local activeOverlays = {} -- [player] = the cloned killer model currently attached

function KillerAppearanceService.GetOverlay(player)
	return activeOverlays[player]
end

local function setDefaultCharacterVisible(character, visible)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = visible and 0 or 1
		elseif part:IsA("Decal") then
			part.Transparency = visible and 0 or 1
		end
	end
end

local function addRedLight(clone)
	local root = clone.PrimaryPart
	if not root then
		return
	end
	local light = Instance.new("SpotLight")
	light.Name = "KillerRedLight"
	light.Color = Color3.fromRGB(255, 0, 0)
	light.Range = 15
	light.Angle = 45
	light.Brightness = 28
	light.Face = Enum.NormalId.Front
	light.Enabled = true
	light.Parent = root
end

local function applyScarecrow(player)
	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	if activeOverlays[player] then
		return
	end

	local selectedKiller = player:GetAttribute("SelectedKiller") or DEFAULT_KILLER
	local killerTemplate = templatesFolder:FindFirstChild(selectedKiller)
	if not killerTemplate then
		warn("No template found for: " .. selectedKiller)
		return
	end

	setDefaultCharacterVisible(character, false)

	local clone = killerTemplate:Clone()
	clone.Name = "KillerOverlay"

	if not clone.PrimaryPart then
		warn(selectedKiller .. " has no PrimaryPart set!")
		return
	end

	clone:PivotTo(root.CFrame)
	clone.Parent = character

	-- Make sure nothing in the overlay is anchored before welding it,
	-- otherwise the weld can lock the real character in place too
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = clone.PrimaryPart
	weld.Parent = clone.PrimaryPart

	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless = true
		end
	end

	addRedLight(clone)

	activeOverlays[player] = clone
end

local function removeScarecrow(player)
	local overlay = activeOverlays[player]
	if overlay then
		overlay:Destroy()
		activeOverlays[player] = nil
	end

	local character = player.Character
	if character then
		setDefaultCharacterVisible(character, true)
	end
end

local function onPlayerAdded(player)
	player:GetAttributeChangedSignal("IsKiller"):Connect(function()
		if player:GetAttribute("IsKiller") then
			applyScarecrow(player)
		else
			removeScarecrow(player)
		end
	end)

	player:GetAttributeChangedSignal("SelectedKiller"):Connect(function()
		if player:GetAttribute("IsKiller") then
			removeScarecrow(player)
			applyScarecrow(player)
		end
	end)

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		activeOverlays[player] = nil
		if player:GetAttribute("IsKiller") then
			applyScarecrow(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	activeOverlays[player] = nil
end)

return KillerAppearanceService