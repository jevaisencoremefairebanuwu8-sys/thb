-- MarkMakerPowerService.server.lua
--
-- The Mark Maker's power.
--
-- ACTIVE ABILITY: Mark
-- Hold F to aim (-20% speed while held). Release to summon a Mark (the
-- "Circle" VFX in Workspace) on the ground where you were aiming, up to
-- 30 studs away. The Mark lasts 1 second, during which you're slowed by
-- 80%. Any Survivor who walks into it loses a Health State and gains
-- the Marked status -- a Marked Survivor can't be Marked again.
-- 10 second cooldown between summons.
--
-- PASSIVE: Perfect Aim
-- Once you've Marked 3 distinct Survivors, press T to activate (one-time
-- per match):
--   - +10% speed for 10 seconds
--   - Every Survivor screams and is revealed (Highlight, visible through
--     walls) for 10 seconds
--   - Mark's cast range increases to 50 studs for those 10 seconds
--
-- NOTE: deliberately does not touch terror radius -- not built yet.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)
local ProgressBarService = require(ReplicatedStorage.Shared.ProgressBarService)
local KillerOverlayAnimationService = require(ReplicatedStorage.Shared.KillerOverlayAnimationService)

-- Adjust this path if it doesn't live next to this script in your actual
-- Rojo tree (same sibling-require pattern KillerAttackService uses).
local KillerAppearanceService = require(script.Parent.KillerAppearanceService)

--============================================================
-- TUNABLES
--============================================================
local MARK_CAST_RANGE = 30
local MARK_CAST_RANGE_BOOSTED = 50 -- during Perfect Aim
local MARK_DURATION = 1
local MARK_COOLDOWN = 10 -- starts the moment a Mark is actually summoned
local MARK_ANIM_NAME = "MarkMakerAbility" -- add this id to AnimationIds.lua: rbxassetid://81426287397486

-- NOTE: these two are for reference/consistency only -- the real speed
-- math lives in MovementStateService (0.8 and 0.2 there). Keep both in
-- sync if you change one.
local HOLD_SPEED_MULTIPLIER = 0.8 -- -20% while aiming
local MARK_SPEED_MULTIPLIER = 0.2 -- -80% for the 1s the Mark is active

local MARKS_NEEDED_FOR_PERFECT_AIM = 3
local PERFECT_AIM_SPEED_MULTIPLIER = 1.1 -- +10%
local PERFECT_AIM_DURATION = 10

local MARK_TRIGGER_RADIUS_FALLBACK = 6 -- used only if the Circle model has no measurable size

--============================================================
-- REMOTE
--============================================================
local abilityRemote = ReplicatedStorage:FindFirstChild("MarkMakerAbilityRequest")
if not abilityRemote then
	abilityRemote = Instance.new("RemoteEvent")
	abilityRemote.Name = "MarkMakerAbilityRequest"
	abilityRemote.Parent = ReplicatedStorage
end

print("MarkMakerPowerService: script starting")

--============================================================
-- STATE
--============================================================
local activeMarks = {} -- [markInstance] = { radius = number, hitSurvivors = {} }
local perfectAimExpiry = {} -- [killerPlayer] = tick() Perfect Aim's window ends
local lastMarkTime = {} -- [killerPlayer] = tick() a Mark was last summoned

--============================================================
-- HELPERS
--============================================================

local function isMarkMaker(player)
	return player:GetAttribute("IsKiller")
		and (player:GetAttribute("SelectedKiller") or ""):find("MarkMaker") ~= nil
end

local function getRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getCircleTemplate()
	local templates = ReplicatedStorage:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("Circle")
	if not template then
		warn("MarkMakerPowerService: no ReplicatedStorage.Templates.Circle found -- can't spawn a Mark. Move your Circle model from Workspace into ReplicatedStorage.Templates.")
	end
	return template
end

local function getMarkRadius(circleModel)
	local ok, size = pcall(function()
		if circleModel:IsA("Model") then
			local _, boundingSize = circleModel:GetBoundingBox()
			return boundingSize
		elseif circleModel:IsA("BasePart") then
			return circleModel.Size
		end
		return nil
	end)

	if ok and size then
		return math.max(size.X, size.Z) / 2
	end
	return MARK_TRIGGER_RADIUS_FALLBACK
end

local function isPerfectAimActive(killerPlayer)
	local expiry = perfectAimExpiry[killerPlayer]
	return expiry ~= nil and tick() < expiry
end

--============================================================
-- CAST PROGRESS BAR (mirrors ScarecrowPowerService's version)
--============================================================
-- Ticks ProgressBarService for as long as IsSummoningMark stays true, up
-- to `duration` seconds -- updates every Heartbeat for a smooth fill.

local function runMarkProgressBar(killerPlayer, actionLabel, duration)
	local startTime = tick()
	local connection

	connection = RunService.Heartbeat:Connect(function()
		if not killerPlayer.Parent then
			connection:Disconnect()
			return
		end
		if not killerPlayer:GetAttribute("IsSummoningMark") then
			connection:Disconnect()
			ProgressBarService.Hide(killerPlayer)
			return
		end

		-- GeneratorUI.client.lua does data.progress / 100 itself, so this
		-- needs to be on a 0-100 scale, not 0-1.
		local progress = math.clamp((tick() - startTime) / duration, 0, 1) * 100
		ProgressBarService.Update(killerPlayer, actionLabel, progress)

		if progress >= 100 then
			connection:Disconnect()
			ProgressBarService.Hide(killerPlayer)
		end
	end)
end

-- Forward raycast along where the killer is aiming, capped at castRange.
-- Falls back to a straight-down raycast at max range if nothing's hit
-- (e.g. aiming at open sky), same fallback style as Effigy placement.
--
-- IMPORTANT: without RaycastParams excluding the killer's own character
-- and overlay, Raycast hits your own body almost immediately (the ray
-- starts right next to it), which is why this was landing at your feet.
--
-- aimDirection (optional): the client's camera look vector, sent along
-- with the HoldEnd request, since root.CFrame.LookVector only reflects
-- body facing -- which commonly only updates while moving, not while
-- just looking around, causing "it's not aiming where my mouse is."
-- The ORIGIN stays root.Position regardless (server-authoritative), so
-- a client can only influence which way the ray points, never fake
-- being closer to a target to bypass the range limit.
local function computeMarkPosition(killerPlayer, root, castRange, aimDirection)
	local origin = root.Position + Vector3.new(0, 1, 0)

	local lookVector = root.CFrame.LookVector
	if typeof(aimDirection) == "Vector3" and aimDirection.Magnitude > 0.1 then
		lookVector = aimDirection.Unit
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterInstances = {}
	if killerPlayer.Character then
		table.insert(filterInstances, killerPlayer.Character)
	end
	local overlay = KillerAppearanceService.GetOverlay(killerPlayer)
	if overlay then
		table.insert(filterInstances, overlay)
	end
	raycastParams.FilterDescendantsInstances = filterInstances

	local forwardRay = Workspace:Raycast(origin, lookVector * castRange, raycastParams)
	if forwardRay then
		return forwardRay.Position
	end

	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude > 0 then
		flatLook = flatLook.Unit
	end
	local farPoint = root.Position + flatLook * castRange
	local downRay = Workspace:Raycast(farPoint + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), raycastParams)
	return downRay and downRay.Position or farPoint
end

local function getSurvivors()
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("IsKiller") then
			local state = PlayerStateService.GetState(player)
			if state == PlayerStateService.States.Healthy
				or state == PlayerStateService.States.Injured
				or state == PlayerStateService.States.Downed then
				table.insert(result, player)
			end
		end
	end
	return result
end

--============================================================
-- MARK EFFECT (health state loss + Marked status)
--============================================================

local function applyMarkEffect(killerPlayer, survivorPlayer)
	if survivorPlayer:GetAttribute("IsMarked") then
		return
	end

	survivorPlayer:SetAttribute("IsMarked", true)

	local state = PlayerStateService.GetState(survivorPlayer)
	if state == PlayerStateService.States.Healthy then
		PlayerStateService.SetState(survivorPlayer, PlayerStateService.States.Injured)
	elseif state == PlayerStateService.States.Injured then
		PlayerStateService.SetState(survivorPlayer, PlayerStateService.States.Downed)
	end

	local markedCount = (killerPlayer:GetAttribute("MarkedSurvivorCount") or 0) + 1
	killerPlayer:SetAttribute("MarkedSurvivorCount", markedCount)

	if markedCount >= MARKS_NEEDED_FOR_PERFECT_AIM then
		killerPlayer:SetAttribute("PerfectAimAvailable", true)
	end

	print(killerPlayer.Name .. " Marked " .. survivorPlayer.Name .. " (total Marked: " .. markedCount .. ")")
end

--============================================================
-- SUMMON MARK
--============================================================

local function summonMark(killerPlayer, aimDirection)
	local character = killerPlayer.Character
	local root = getRoot(character)
	if not root then
		return
	end

	local template = getCircleTemplate()
	if not template then
		return
	end

	lastMarkTime[killerPlayer] = tick()
	killerPlayer:SetAttribute("MarkAbilityReadyAt", tick() + MARK_COOLDOWN)

	local boosted = isPerfectAimActive(killerPlayer)
	local castRange = boosted and MARK_CAST_RANGE_BOOSTED or MARK_CAST_RANGE
	local markPosition = computeMarkPosition(killerPlayer, root, castRange, aimDirection)

	local circle = template:Clone()
	circle.Name = "MarkMakerCircle"
	if circle:IsA("Model") then
		circle:PivotTo(CFrame.new(markPosition))
	elseif circle:IsA("BasePart") then
		circle.CFrame = CFrame.new(markPosition)
		circle.Anchored = true
		circle.CanCollide = false
	end
	circle.Parent = Workspace

	local radius = getMarkRadius(circle)
	activeMarks[circle] = { radius = radius, hitSurvivors = {} }

	killerPlayer:SetAttribute("IsSummoningMark", true)
	runMarkProgressBar(killerPlayer, "MarkMakerAbility", MARK_DURATION)

	local overlay = KillerAppearanceService.GetOverlay(killerPlayer)
	KillerOverlayAnimationService.PlayOnce(overlay, MARK_ANIM_NAME, function() end)

	task.delay(MARK_DURATION, function()
		killerPlayer:SetAttribute("IsSummoningMark", false)
		activeMarks[circle] = nil
		if circle.Parent then
			circle:Destroy()
		end
	end)
end

--============================================================
-- PERFECT AIM
--============================================================

local function activatePerfectAim(killerPlayer)
	if not killerPlayer:GetAttribute("PerfectAimAvailable") then
		return
	end
	if killerPlayer:GetAttribute("PerfectAimUsed") then
		return
	end

	killerPlayer:SetAttribute("PerfectAimUsed", true)
	killerPlayer:SetAttribute("PerfectAimActive", true)
	perfectAimExpiry[killerPlayer] = tick() + PERFECT_AIM_DURATION

	for _, survivorPlayer in ipairs(getSurvivors()) do
		local character = survivorPlayer.Character
		local root = getRoot(character)
		if root and character then
			local sound = Instance.new("Sound")
			sound.Name = "MarkMakerScream"
			sound.SoundId = "" -- TODO: put your scream SFX id here
			sound.Volume = 1
			sound.Parent = root
			sound:Play()
			sound.Ended:Connect(function()
				sound:Destroy()
			end)

			local highlight = Instance.new("Highlight")
			highlight.Name = "MarkMakerReveal"
			highlight.FillTransparency = 1
			highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Parent = character

			task.delay(PERFECT_AIM_DURATION, function()
				if highlight.Parent then
					highlight:Destroy()
				end
			end)
		end
	end

	print(killerPlayer.Name .. " activated Perfect Aim")

	task.delay(PERFECT_AIM_DURATION, function()
		killerPlayer:SetAttribute("PerfectAimActive", false)
	end)
end

--============================================================
-- REMOTE HANDLING
--============================================================

abilityRemote.OnServerEvent:Connect(function(player, action, aimDirection)
	if not isMarkMaker(player) then
		return
	end
	if player:GetAttribute("IsCarrying") or player:GetAttribute("IsStunned") then
		return
	end

	if action == "HoldStart" then
		if player:GetAttribute("IsHoldingMarkAbility") or player:GetAttribute("IsSummoningMark") then
			return
		end
		local lastTime = lastMarkTime[player]
		if lastTime and tick() - lastTime < MARK_COOLDOWN then
			return
		end
		player:SetAttribute("IsHoldingMarkAbility", true)
	elseif action == "HoldEnd" then
		if not player:GetAttribute("IsHoldingMarkAbility") then
			return
		end
		player:SetAttribute("IsHoldingMarkAbility", false)
		summonMark(player, aimDirection)
	elseif action == "PerfectAim" then
		activatePerfectAim(player)
	end
end)

--============================================================
-- MAIN LOOP: check Survivors walking into active Marks
--============================================================

RunService.Heartbeat:Connect(function()
	for markInstance, data in pairs(activeMarks) do
		local markPosition
		if markInstance:IsA("Model") then
			markPosition = markInstance:GetPivot().Position
		elseif markInstance:IsA("BasePart") then
			markPosition = markInstance.Position
		end
		if not markPosition then
			continue
		end

		for _, survivorPlayer in ipairs(getSurvivors()) do
			if not data.hitSurvivors[survivorPlayer] and not survivorPlayer:GetAttribute("IsMarked") then
				local root = getRoot(survivorPlayer.Character)
				if root and (root.Position - markPosition).Magnitude <= data.radius then
					data.hitSurvivors[survivorPlayer] = true

					-- Find whichever Mark Maker is currently the killer to
					-- credit the Marked-count toward (there's only ever one
					-- killer per match).
					for _, possibleKiller in ipairs(Players:GetPlayers()) do
						if isMarkMaker(possibleKiller) then
							applyMarkEffect(possibleKiller, survivorPlayer)
							break
						end
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	perfectAimExpiry[player] = nil
	lastMarkTime[player] = nil
end)

print("MarkMakerPowerService loaded successfully.")