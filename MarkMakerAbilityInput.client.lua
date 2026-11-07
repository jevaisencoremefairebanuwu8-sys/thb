-- MarkMakerAbilityInput.client.lua
-- Hold F = aim the Mark ability (shows a live landing preview)
-- Release F = place the Mark
-- T = activate Perfect Aim (once unlocked)
-- Only active while this client's player is the killer with Mark Maker selected.
--
-- Aiming uses the CAMERA's look direction, not the character's body
-- facing (root.CFrame.LookVector) -- body facing commonly only updates
-- while moving, which is why aiming felt inaccurate while standing
-- still. The direction is sent to the server on release so the actual
-- placement matches what you saw in the preview; the server still uses
-- your own position as the ray's origin, so this can't be used to
-- place Marks farther than your real range.
--
-- MarkAbilityReadyAt (set by the server, replicated automatically) is
-- checked before starting a hold at all -- without this, the preview
-- would show even while the ability is on cooldown, since the server
-- silently ignores a HoldStart it receives during cooldown but the
-- client had no way to know that in advance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local abilityRemote = ReplicatedStorage:WaitForChild("MarkMakerAbilityRequest")

-- Keep these in sync with MarkMakerPowerService.server.lua's
-- MARK_CAST_RANGE / MARK_CAST_RANGE_BOOSTED.
local MARK_CAST_RANGE = 30
local MARK_CAST_RANGE_BOOSTED = 50

local IN_RANGE_COLOR = Color3.fromRGB(173, 216, 230) -- light blue/white
local OUT_OF_RANGE_COLOR = Color3.fromRGB(255, 60, 60)
local PREVIEW_TRANSPARENCY = 0.5

local isHolding = false
local previewInstance = nil
local lastAimDirection = Vector3.new(0, 0, -1)

local function isMarkMaker()
	return localPlayer:GetAttribute("IsKiller")
		and (localPlayer:GetAttribute("SelectedKiller") or ""):find("MarkMaker") ~= nil
end

local function isOnCooldown()
	local readyAt = localPlayer:GetAttribute("MarkAbilityReadyAt")
	return readyAt ~= nil and tick() < readyAt
end

local function getCastRange()
	if localPlayer:GetAttribute("PerfectAimActive") then
		return MARK_CAST_RANGE_BOOSTED
	end
	return MARK_CAST_RANGE
end

local function getCircleTemplate()
	local templates = ReplicatedStorage:FindFirstChild("Templates")
	return templates and templates:FindFirstChild("Circle")
end

local function setPreviewColor(color)
	if not previewInstance then
		return
	end
	for _, part in ipairs(previewInstance:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Color = color
			part.Transparency = PREVIEW_TRANSPARENCY
		end
	end
end

local function createPreview()
	local template = getCircleTemplate()
	if not template then
		warn("MarkMakerAbilityInput: no ReplicatedStorage.Templates.Circle found, can't preview the Mark.")
		return
	end

	previewInstance = template:Clone()
	previewInstance.Name = "MarkMakerAimPreview"
	for _, part in ipairs(previewInstance:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	previewInstance.Parent = Workspace
end

local function destroyPreview()
	if previewInstance then
		previewInstance:Destroy()
		previewInstance = nil
	end
end

local function buildRaycastParams(character)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterInstances = { character }
	local overlay = character:FindFirstChild("KillerOverlay")
	if overlay then
		table.insert(filterInstances, overlay)
	end
	if previewInstance then
		table.insert(filterInstances, previewInstance)
	end
	raycastParams.FilterDescendantsInstances = filterInstances
	return raycastParams
end

-- Mirrors the server's computeMarkPosition exactly (same origin formula,
-- same clamped/fallback logic), but using the camera's look direction
-- instead of root.CFrame.LookVector for accuracy, and additionally
-- checks a much longer ray to know whether your TRUE aim point is
-- within range or being clamped short.
local function updatePreview()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not previewInstance then
		return
	end

	local castRange = getCastRange()
	local origin = root.Position + Vector3.new(0, 1, 0)
	local lookVector = camera.CFrame.LookVector
	lastAimDirection = lookVector

	local raycastParams = buildRaycastParams(character)

	local longRay = Workspace:Raycast(origin, lookVector * (castRange * 4), raycastParams)
	local trueDistance = longRay and (longRay.Position - origin).Magnitude or math.huge
	local inRange = trueDistance <= castRange

	local clampedPosition
	local cappedRay = Workspace:Raycast(origin, lookVector * castRange, raycastParams)
	if cappedRay then
		clampedPosition = cappedRay.Position
	else
		local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
		if flatLook.Magnitude > 0 then
			flatLook = flatLook.Unit
		end
		local farPoint = root.Position + flatLook * castRange
		local downRay = Workspace:Raycast(farPoint + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), raycastParams)
		clampedPosition = downRay and downRay.Position or farPoint
	end

	if previewInstance:IsA("Model") then
		previewInstance:PivotTo(CFrame.new(clampedPosition))
	elseif previewInstance:IsA("BasePart") then
		previewInstance.CFrame = CFrame.new(clampedPosition)
	end

	setPreviewColor(inRange and IN_RANGE_COLOR or OUT_OF_RANGE_COLOR)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not isMarkMaker() then
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		if isOnCooldown() then
			return
		end
		isHolding = true
		abilityRemote:FireServer("HoldStart")
		createPreview()
	elseif input.KeyCode == Enum.KeyCode.T then
		abilityRemote:FireServer("PerfectAim")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F then
		if isHolding then
			abilityRemote:FireServer("HoldEnd", lastAimDirection)
		end
		isHolding = false
		destroyPreview()
	end
end)

RunService.Heartbeat:Connect(function()
	if isHolding and isMarkMaker() then
		updatePreview()
	elseif previewInstance then
		-- Stopped being Mark Maker, lost the killer role, or cooldown
		-- started mid-hold somehow -- clear the preview either way.
		isHolding = false
		destroyPreview()
	end
end)