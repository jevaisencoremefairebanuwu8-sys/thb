-- ScarecrowPowerService.server.lua
--
-- The Scarecrow's power.
--
-- ACTIVE ABILITY: press F to channel "ScarecrowAbility" for 4 seconds
-- (killer locked in place via IsCastingAbility), then place a Scarecrow
-- Effigy (5s cooldown after it spawns, max 3 per 60s).
--
-- Any Survivor who stays within 40 studs of an Effigy for 15 continuous
-- seconds gets 1 Fear token; the Effigy is then destroyed.
--   1 token  -> all active Effigies get a red light
--   2 tokens -> Effigies within range of that Survivor start creeping
--               toward them
--   3 tokens -> that Survivor's field of vision shrinks (client fog)
--   4 tokens -> that Survivor screams and becomes Exposed
-- Fear tokens reset to 0 for everyone once a single objective is finished.
--
-- PASSIVE: teleport to the nearest Effigy (20s cooldown). Gains 5% speed
-- per Effigy within 20 studs (stacks up to 3), retained for 6s after
-- leaving range.
--
-- NOTE: deliberately does not touch terror radius -- not built yet.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)
local KillerOverlayAnimationService = require(ReplicatedStorage.Shared.KillerOverlayAnimationService)
local ProgressBarService = require(ReplicatedStorage.Shared.ProgressBarService)

-- Adjust these paths if they don't live next to this script in your
-- actual Rojo tree (same sibling-require pattern KillerAttackService uses).
local StageManager = require(script.Parent.StageManager)
local KillerAppearanceService = require(script.Parent.KillerAppearanceService)

--============================================================
-- TUNABLES
--============================================================
local CAST_DURATION = 4
local ABILITY_ANIM_NAME = "ScarecrowAbility" -- add this id to AnimationIds.lua

local PLACEMENT_COOLDOWN = 5
local MAX_PLACEMENTS_PER_WINDOW = 3
local PLACEMENT_WINDOW = 60

local FEAR_RADIUS = 40
local FEAR_TIME_REQUIRED = 15

local RED_LIGHT_THRESHOLD = 1
local CHASE_THRESHOLD = 2
local VISION_THRESHOLD = 3
local EXPOSED_THRESHOLD = 4

local CHASE_SPEED = 10 -- studs/sec an Effigy creeps toward its target
local REDUCED_VISION_FOG_END = 30

local PASSIVE_TELEPORT_COOLDOWN = 20
local PASSIVE_SPEED_RADIUS = 20
local PASSIVE_SPEED_STACK_DURATION = 6 -- seconds a stack lingers after leaving range
local PASSIVE_SPEED_MAX_STACKS = 3

local TICK_INTERVAL = 0.15 -- throttle for the proximity/chase/passive loop

--============================================================
-- REMOTES
--============================================================
local abilityRemote = ReplicatedStorage:FindFirstChild("ScarecrowAbilityRequest")
if not abilityRemote then
	abilityRemote = Instance.new("RemoteEvent")
	abilityRemote.Name = "ScarecrowAbilityRequest"
	abilityRemote.Parent = ReplicatedStorage
end

local fearEffectRemote = ReplicatedStorage:FindFirstChild("ScarecrowFearEffect")
if not fearEffectRemote then
	fearEffectRemote = Instance.new("RemoteEvent")
	fearEffectRemote.Name = "ScarecrowFearEffect"
	fearEffectRemote.Parent = ReplicatedStorage
end

print("ScarecrowPowerService: script starting")

--============================================================
-- EFFIGY TEMPLATE (same rig as the killer overlay)
--============================================================
local function getEffigyTemplate()
	local templates = ReplicatedStorage:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("ScarecrowModel")
	if not template then
		warn("ScarecrowPowerService: ReplicatedStorage.Templates.ScarecrowModel not found -- can't spawn an Effigy.")
	end
	return template
end

--============================================================
-- STATE
--============================================================
-- NOTE: the red cast-warning light is handled generically for ALL
-- killers in KillerAppearanceService (driven by IsCastingAbility),
-- not here -- see the KillerAppearanceService patch.
-- activeEffigies[effigy] = {
--   placedAt = tick(),
--   fearTimers = { [survivorPlayer] = accumulatedSeconds },
--   isChasing = false,
--   chaseTarget = nil,
--   hasRedLight = false,
-- }
local activeEffigies = {}

local placementTimestamps = {} -- [killerPlayer] = { tick(), tick(), ... }
local lastPlacementTime = {} -- [killerPlayer] = tick()
local lastTeleportTime = {} -- [killerPlayer] = tick()

local fearTokens = {} -- [survivorPlayer] = number
local exposedPlayers = {} -- [survivorPlayer] = true
local reducedVisionPlayers = {} -- [survivorPlayer] = true

local speedStackExpiry = {} -- [killerPlayer] = { [effigy] = expiryTick }

--============================================================
-- HELPERS
--============================================================

local function isScarecrow(player)
	return player:GetAttribute("IsKiller")
		and (player:GetAttribute("SelectedKiller") or ""):find("Scarecrow") ~= nil
end

local function getRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function pruneOldPlacements(player)
	local timestamps = placementTimestamps[player]
	if not timestamps then
		return
	end
	local now = tick()
	local kept = {}
	for _, t in ipairs(timestamps) do
		if now - t < PLACEMENT_WINDOW then
			table.insert(kept, t)
		end
	end
	placementTimestamps[player] = kept
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

local function getEffigyPosition(effigy)
	if effigy:IsA("BasePart") then
		return effigy.Position
	elseif effigy:IsA("Model") then
		return (effigy.PrimaryPart and effigy.PrimaryPart.Position) or effigy:GetPivot().Position
	end
	return nil
end

local function setEffigyPosition(effigy, position)
	if effigy:IsA("BasePart") then
		effigy.CFrame = CFrame.new(position, position + Vector3.new(0, 0, -1))
	elseif effigy:IsA("Model") then
		effigy:PivotTo(CFrame.new(position, position + Vector3.new(0, 0, -1)))
	end
end

--============================================================
-- FEAR TOKEN THRESHOLD EFFECTS
--============================================================

local function applyRedLightToAllEffigies()
	for effigy, data in pairs(activeEffigies) do
		if not data.hasRedLight then
			data.hasRedLight = true
			local light = Instance.new("PointLight")
			light.Name = "ScarecrowFearLight"
			light.Color = Color3.fromRGB(255, 0, 0)
			light.Range = 16
			light.Brightness = 2
			light.Parent = effigy:IsA("BasePart") and effigy or (effigy.PrimaryPart or effigy)
		end
	end
end

local function startChasingIfInRange(survivorPlayer)
	local character = survivorPlayer.Character
	local root = getRoot(character)
	if not root then
		return
	end
	for effigy, data in pairs(activeEffigies) do
		if not data.isChasing then
			local effigyPos = getEffigyPosition(effigy)
			if effigyPos and (effigyPos - root.Position).Magnitude <= FEAR_RADIUS then
				data.isChasing = true
				data.chaseTarget = survivorPlayer
			end
		end
	end
end

local function setReducedVision(survivorPlayer, enabled)
	if enabled and not reducedVisionPlayers[survivorPlayer] then
		reducedVisionPlayers[survivorPlayer] = true
		fearEffectRemote:FireClient(survivorPlayer, "VisionReduced", true, REDUCED_VISION_FOG_END)
	elseif not enabled and reducedVisionPlayers[survivorPlayer] then
		reducedVisionPlayers[survivorPlayer] = nil
		fearEffectRemote:FireClient(survivorPlayer, "VisionReduced", false)
	end
end

local function setExposed(survivorPlayer, enabled)
	if enabled and not exposedPlayers[survivorPlayer] then
		exposedPlayers[survivorPlayer] = true
		survivorPlayer:SetAttribute("IsExposed", true)
		fearEffectRemote:FireClient(survivorPlayer, "Scream")
	elseif not enabled and exposedPlayers[survivorPlayer] then
		exposedPlayers[survivorPlayer] = nil
		survivorPlayer:SetAttribute("IsExposed", false)
	end
end

local function evaluateThresholds(survivorPlayer)
	local tokens = fearTokens[survivorPlayer] or 0

	if tokens >= RED_LIGHT_THRESHOLD then
		applyRedLightToAllEffigies()
	end

	if tokens >= CHASE_THRESHOLD then
		startChasingIfInRange(survivorPlayer)
	end

	setReducedVision(survivorPlayer, tokens >= VISION_THRESHOLD)
	setExposed(survivorPlayer, tokens >= EXPOSED_THRESHOLD)
end

local function addFearToken(survivorPlayer)
	fearTokens[survivorPlayer] = (fearTokens[survivorPlayer] or 0) + 1
	print(survivorPlayer.Name .. " gained a Fear token, now at " .. fearTokens[survivorPlayer])
	evaluateThresholds(survivorPlayer)
end

local function resetAllFearTokens()
	print("ScarecrowPowerService: objective finished, resetting all Fear tokens")
	for _, player in ipairs(Players:GetPlayers()) do
		if fearTokens[player] and fearTokens[player] > 0 then
			fearTokens[player] = 0
			setReducedVision(player, false)
			setExposed(player, false)
		end
	end
end

-- Requires the small StageManager.lua patch (StageManager.ObjectiveCompleted
-- BindableEvent) described alongside this file.
if StageManager.ObjectiveCompleted then
	StageManager.ObjectiveCompleted.Event:Connect(resetAllFearTokens)
else
	warn("ScarecrowPowerService: StageManager.ObjectiveCompleted not found -- Fear tokens won't reset on objective completion until you add it.")
end

--============================================================
-- EFFIGY DESTRUCTION
--============================================================

local function destroyEffigy(effigy)
	activeEffigies[effigy] = nil
	if effigy and effigy.Parent then
		effigy:Destroy()
	end
end

--============================================================
-- CAST PROGRESS BAR
--============================================================
-- Ticks ProgressBarService for as long as IsCastingAbility stays true,
-- up to `duration` seconds. Generic by design -- any future power that
-- sets IsCastingAbility during its own cast gets a progress bar for
-- free just by calling this alongside it.

local function runCastProgressBar(killerPlayer, actionLabel, duration)
	local startTime = tick()
	local connection

	connection = RunService.Heartbeat:Connect(function()
		if not killerPlayer.Parent then
			connection:Disconnect()
			return
		end
		if not killerPlayer:GetAttribute("IsCastingAbility") then
			connection:Disconnect()
			ProgressBarService.Hide(killerPlayer)
			return
		end

		-- GeneratorUI.client.lua does data.progress / 100 itself, so
		-- this needs to be on a 0-100 scale, not 0-1.
		local progress = math.clamp((tick() - startTime) / duration, 0, 1) * 100
		ProgressBarService.Update(killerPlayer, actionLabel, progress)

		if progress >= 100 then
			connection:Disconnect()
			ProgressBarService.Hide(killerPlayer)
		end
	end)
end

--============================================================
-- SPAWNING (after the cast finishes)
--============================================================

local function spawnEffigyAt(cframe)
	local template = getEffigyTemplate()
	if not template then
		return nil
	end

	local effigy = template:Clone()
	effigy.Name = "ScarecrowEffigy"

	if effigy:IsA("Model") then
		if effigy.PrimaryPart then
			-- The raycast that produced `cframe` gives us the floor's
			-- surface, but PivotTo places the PrimaryPart (roughly hip
			-- height on a humanoid rig) AT that point, sinking the model
			-- into the floor. Measure how far the PrimaryPart sits above
			-- the model's actual feet (its bounding box's lowest point)
			-- while it's still in its default pose, then lift the
			-- placement by that amount so the feet land on the surface.
			local boundingCFrame, boundingSize = effigy:GetBoundingBox()
			local lowestY = boundingCFrame.Position.Y - (boundingSize.Y / 2)
			local footOffset = effigy.PrimaryPart.Position.Y - lowestY

			effigy:PivotTo(cframe + Vector3.new(0, footOffset, 0))
			for _, part in ipairs(effigy:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
				end
			end
			effigy.PrimaryPart.Anchored = true
		else
			effigy:PivotTo(cframe)
		end
		-- If your ScarecrowModel template has any AI/movement scripts on it
		-- (patrol logic, etc.), strip them from the clone here so the
		-- Effigy just stands still until it starts chasing at 2 tokens.
	elseif effigy:IsA("BasePart") then
		effigy.CFrame = cframe
		effigy.Anchored = true
	end

	effigy.Parent = Workspace
	return effigy
end

--============================================================
-- ABILITY CAST (4s stand-still, then spawn)
--============================================================

local function beginEffigyCast(killerPlayer)
	local character = killerPlayer.Character
	local root = getRoot(character)
	if not root then
		return
	end

	pruneOldPlacements(killerPlayer)
	local timestamps = placementTimestamps[killerPlayer] or {}

	local lastTime = lastPlacementTime[killerPlayer]
	if lastTime and tick() - lastTime < PLACEMENT_COOLDOWN then
		return
	end
	if #timestamps >= MAX_PLACEMENTS_PER_WINDOW then
		return
	end
	if killerPlayer:GetAttribute("IsCastingAbility") then
		return
	end

	-- Snapshot where the Effigy will land now, before the killer is locked
	-- in place, so it spawns where they were aiming when they pressed F.
	local desiredPosition = root.Position + root.CFrame.LookVector * 6
	local rayResult = Workspace:Raycast(desiredPosition + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0))
	local finalPosition = rayResult and rayResult.Position or desiredPosition
	local finalCFrame = CFrame.new(finalPosition, finalPosition + root.CFrame.LookVector)

	killerPlayer:SetAttribute("IsCastingAbility", true)

	local overlay = KillerAppearanceService.GetOverlay(killerPlayer)
	KillerOverlayAnimationService.PlayOnce(overlay, ABILITY_ANIM_NAME, function() end)
	runCastProgressBar(killerPlayer, "Placing an Effigy", CAST_DURATION)

	task.delay(CAST_DURATION, function()
		killerPlayer:SetAttribute("IsCastingAbility", false)

		-- Bail out quietly if the killer disconnected, died, or got
		-- stunned mid-cast -- no Effigy, no cooldown/charge consumed.
		if not killerPlayer.Parent then
			return
		end
		if killerPlayer:GetAttribute("IsStunned") then
			return
		end

		local effigy = spawnEffigyAt(finalCFrame)
		if not effigy then
			return
		end

		activeEffigies[effigy] = {
			placedAt = tick(),
			fearTimers = {},
			isChasing = false,
			chaseTarget = nil,
			hasRedLight = false,
		}

		lastPlacementTime[killerPlayer] = tick()
		table.insert(timestamps, tick())
		placementTimestamps[killerPlayer] = timestamps

		print(killerPlayer.Name .. " placed a Scarecrow Effigy at " .. tostring(finalPosition))
	end)
end

--============================================================
-- PASSIVE: TELEPORT (swap positions with an Effigy)
--============================================================

local function getOverlayParts(overlay)
	local parts = {}
	if overlay then
		for _, part in ipairs(overlay:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(parts, part)
			end
		end
	end
	return parts
end

local function fadeParts(parts, targetTransparency, duration)
	for _, part in ipairs(parts) do
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(duration), { Transparency = targetTransparency }):Play()
		end
	end
end

local function beginTeleportCast(killerPlayer)
	local lastTime = lastTeleportTime[killerPlayer]
	if lastTime and tick() - lastTime < PASSIVE_TELEPORT_COOLDOWN then
		return
	end
	if killerPlayer:GetAttribute("IsCastingAbility") then
		return
	end

	local character = killerPlayer.Character
	local root = getRoot(character)
	if not root then
		return
	end

	local nearestEffigy, nearestDistance = nil, math.huge
	for effigy in pairs(activeEffigies) do
		local effigyPos = getEffigyPosition(effigy)
		if effigyPos then
			local distance = (effigyPos - root.Position).Magnitude
			if distance < nearestDistance then
				nearestEffigy = effigy
				nearestDistance = distance
			end
		end
	end

	if not nearestEffigy then
		return
	end

	lastTeleportTime[killerPlayer] = tick()
	killerPlayer:SetAttribute("IsCastingAbility", true)

	local overlay = KillerAppearanceService.GetOverlay(killerPlayer)
	KillerOverlayAnimationService.PlayOnce(overlay, ABILITY_ANIM_NAME, function() end)
	runCastProgressBar(killerPlayer, "Teleport", CAST_DURATION)

	local parts = getOverlayParts(overlay)
	local fadeHalf = CAST_DURATION / 2

	-- Snapshot both sides of the swap before anything moves
	local killerStartCFrame = root.CFrame
	local effigyStartPosition = getEffigyPosition(nearestEffigy)

	fadeParts(parts, 1, fadeHalf) -- fade out

	task.delay(fadeHalf, function()
		if not killerPlayer.Parent then
			return
		end
		if killerPlayer:GetAttribute("IsStunned") then
			killerPlayer:SetAttribute("IsCastingAbility", false)
			fadeParts(parts, 0, 0.25)
			return
		end

		-- The Effigy might have procced a Fear token and been destroyed
		-- mid-cast -- if so, cancel the swap but still finish the fade
		-- back in so the killer isn't left invisible.
		if not activeEffigies[nearestEffigy] or not nearestEffigy.Parent then
			killerPlayer:SetAttribute("IsCastingAbility", false)
			fadeParts(parts, 0, fadeHalf)
			return
		end

		root.CFrame = CFrame.new(effigyStartPosition, effigyStartPosition + killerStartCFrame.LookVector)
		setEffigyPosition(nearestEffigy, killerStartCFrame.Position)

		fadeParts(parts, 0, fadeHalf) -- fade in

		task.delay(fadeHalf, function()
			killerPlayer:SetAttribute("IsCastingAbility", false)
			print(killerPlayer.Name .. " swapped positions with an Effigy")
		end)
	end)
end

--============================================================
-- REMOTE HANDLING
--============================================================

abilityRemote.OnServerEvent:Connect(function(player, action)
	if not isScarecrow(player) then
		return
	end
	if player:GetAttribute("IsCarrying") or player:GetAttribute("IsStunned") then
		return
	end

	if action == "PlaceEffigy" then
		beginEffigyCast(player)
	elseif action == "Teleport" then
		beginTeleportCast(player)
	end
end)

--============================================================
-- MAIN LOOP: fear proximity, chasing, passive speed stacks
--============================================================

local accumulated = 0
RunService.Heartbeat:Connect(function(deltaTime)
	accumulated += deltaTime
	if accumulated < TICK_INTERVAL then
		return
	end
	local dt = accumulated
	accumulated = 0

	local survivors = getSurvivors()

	-- Fear proximity accrual + chase movement
	for effigy, data in pairs(activeEffigies) do
		local effigyPos = getEffigyPosition(effigy)
		if not effigyPos then
			continue
		end

		for _, survivorPlayer in ipairs(survivors) do
			local root = getRoot(survivorPlayer.Character)
			if root then
				local distance = (effigyPos - root.Position).Magnitude
				if distance <= FEAR_RADIUS then
					data.fearTimers[survivorPlayer] = (data.fearTimers[survivorPlayer] or 0) + dt
					if data.fearTimers[survivorPlayer] >= FEAR_TIME_REQUIRED then
						addFearToken(survivorPlayer)
						destroyEffigy(effigy)
						break
					end
				else
					data.fearTimers[survivorPlayer] = 0
				end
			end
		end

		if activeEffigies[effigy] and data.isChasing and data.chaseTarget then
			local targetRoot = getRoot(data.chaseTarget.Character)
			if targetRoot then
				local direction = (targetRoot.Position - effigyPos)
				if direction.Magnitude > 3 then
					local step = direction.Unit * CHASE_SPEED * dt
					setEffigyPosition(effigy, effigyPos + step)
				end
			end
		end
	end

	-- Passive speed stacking (killer only)
	for _, player in ipairs(Players:GetPlayers()) do
		if isScarecrow(player) then
			local root = getRoot(player.Character)
			if root then
				local expiryMap = speedStackExpiry[player] or {}
				speedStackExpiry[player] = expiryMap

				for effigy in pairs(activeEffigies) do
					local effigyPos = getEffigyPosition(effigy)
					if effigyPos and (effigyPos - root.Position).Magnitude <= PASSIVE_SPEED_RADIUS then
						expiryMap[effigy] = tick() + PASSIVE_SPEED_STACK_DURATION
					end
				end

				local stackCount = 0
				local now = tick()
				for effigy, expiry in pairs(expiryMap) do
					if expiry > now and activeEffigies[effigy] then
						stackCount += 1
					else
						expiryMap[effigy] = nil
					end
				end
				stackCount = math.min(stackCount, PASSIVE_SPEED_MAX_STACKS)

				if player:GetAttribute("ScarecrowSpeedStacks") ~= stackCount then
					player:SetAttribute("ScarecrowSpeedStacks", stackCount)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	placementTimestamps[player] = nil
	lastPlacementTime[player] = nil
	lastTeleportTime[player] = nil
	fearTokens[player] = nil
	exposedPlayers[player] = nil
	reducedVisionPlayers[player] = nil
	speedStackExpiry[player] = nil
end)

print("ScarecrowPowerService loaded successfully.")