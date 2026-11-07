-- CabinService.lua (ModuleScript)
-- Replaces the old Blood Circle hooking system. Whenever a survivor (or
-- the TestDummy) becomes Downed, a Cabin spawns nearby and they're
-- teleported inside -- fully automatic, no killer action required
-- (see CabinTrapService.server.lua, which is what actually calls
-- CabinService.TrapDowned whenever HealthState becomes Downed).
--
-- A teammate holds E on the Cabin's door to rescue them (same
-- hold+progress mechanic the old hook rescue used). If not rescued
-- within CABIN_TIMEOUT seconds, they die.
--
-- Each survivor has HOOK_LIVES total (3) "hook" states/lives, tracked
-- via a HookCount attribute. Being rescued costs one. On the 3rd
-- trapping, they die immediately and permanently -- no door, no rescue
-- window at all.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)
local ProgressBarService = require(ReplicatedStorage.Shared.ProgressBarService)

local CabinService = {}

local CABIN_TIMEOUT = 30
local RESCUE_RATE_PER_SECOND = 20 -- same pace as the old hook rescue (5s solo)
local MAX_RESCUE_DISTANCE = 8
local HOOK_LIVES = 3
local SPAWN_SEARCH_RADIUS = 15 -- studs around the downed survivor to place the cabin
local RESCUE_FADE_DELAY = 1.5 -- seconds after rescue before fading visible, leaves room for a "getting saved" animation
local RESCUE_FADE_DURATION = 0.5

local cabinsFolder = Workspace:FindFirstChild("Cabins")
if not cabinsFolder then
	cabinsFolder = Instance.new("Folder")
	cabinsFolder.Name = "Cabins"
	cabinsFolder.Parent = Workspace
end

local cabinTemplate = ReplicatedStorage:WaitForChild("Templates"):WaitForChild("Cabin")

local trappedData = {} -- [target] = { cabinModel, phaseStartTime, rescuers = {} }
local rescuerActiveTarget = {}

local cabinRescueRemote = ReplicatedStorage:FindFirstChild("CabinRescueInteract")
if not cabinRescueRemote then
	cabinRescueRemote = Instance.new("RemoteEvent")
	cabinRescueRemote.Name = "CabinRescueInteract"
	cabinRescueRemote.Parent = ReplicatedStorage
end

local function getRootPart(target)
	if target:IsA("Player") then
		local character = target.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	else
		return target:FindFirstChild("HumanoidRootPart")
	end
end

local function getCharacterModel(target)
	if target:IsA("Player") then
		return target.Character
	else
		return target
	end
end

local function setTargetState(target, stateName)
	if target:IsA("Player") then
		PlayerStateService.SetState(target, stateName)
	else
		target:SetAttribute("HealthState", stateName)
	end
end

local function getHookCount(target)
	return target:GetAttribute("HookCount") or 0
end

-- Finds a spawn position for the Cabin near the downed survivor,
-- raycasting down to the ground. Simple default -- if you'd rather
-- Cabins spawn at fixed pre-placed spots around the map, add a
-- "CabinSpawnPoints" folder and swap this out for a nearest-point search.
local function findCabinSpawnPosition(nearPosition)
	local offset = Vector3.new(
		math.random(-SPAWN_SEARCH_RADIUS, SPAWN_SEARCH_RADIUS),
		0,
		math.random(-SPAWN_SEARCH_RADIUS, SPAWN_SEARCH_RADIUS)
	)
	local searchPoint = nearPosition + offset
	local rayResult = Workspace:Raycast(searchPoint + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0))
	return rayResult and rayResult.Position or nearPosition
end

-- Sets every BasePart/Decal on the character to `transparency`, storing
-- each part's original value into `originalTransparencyOut` (if given)
-- so it can be restored later instead of assuming everything was 0.
local function setCharacterTransparency(characterModel, transparency, originalTransparencyOut)
	for _, part in ipairs(characterModel:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			if originalTransparencyOut then
				originalTransparencyOut[part] = part.Transparency
			end
			part.Transparency = transparency
		end
	end
end

-- Tweens every tracked part back to its stored original transparency.
local function fadeCharacterVisible(characterModel, originalTransparency)
	if not originalTransparency then
		return
	end
	for part, originalValue in pairs(originalTransparency) do
		if part and part.Parent then
			TweenService:Create(part, TweenInfo.new(RESCUE_FADE_DURATION), { Transparency = originalValue }):Play()
		end
	end
end

local function destroyCabin(cabinModel)
	if cabinModel and cabinModel.Parent then
		cabinModel:Destroy()
	end
end

local function killTarget(target)
	local data = trappedData[target]
	if not data then
		return
	end
	print(target.Name .. " died, not rescued from the cabin in time.")
	setTargetState(target, PlayerStateService.States.Dead)
	destroyCabin(data.cabinModel)
	trappedData[target] = nil
end

local function rescueTarget(target)
	local data = trappedData[target]
	if not data then
		return
	end

	local characterModel = getCharacterModel(target)
	if characterModel then
		local rootPart = characterModel:FindFirstChild("HumanoidRootPart")
		if rootPart then
			rootPart.Anchored = false
		end
		for _, part in ipairs(characterModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
	end

	for rescuer in pairs(data.rescuers) do
		ProgressBarService.Hide(rescuer)
		rescuerActiveTarget[rescuer] = nil
	end
	ProgressBarService.Hide(target)

	local originalTransparency = data.originalTransparency
	destroyCabin(data.cabinModel)
	trappedData[target] = nil
	target:SetAttribute("CabinRescueProgress", 0)

	local hookCount = getHookCount(target) + 1
	target:SetAttribute("HookCount", hookCount)

	-- Stay invisible for a beat (room for a "getting saved" animation),
	-- then fade back in rather than popping visible instantly.
	task.delay(RESCUE_FADE_DELAY, function()
		if characterModel and characterModel.Parent then
			fadeCharacterVisible(characterModel, originalTransparency)
		end
	end)

	setTargetState(target, PlayerStateService.States.Injured)
	print(target.Name .. " was rescued from the cabin (hook " .. hookCount .. "/" .. HOOK_LIVES .. ")")
end

-- Called whenever a survivor (or the TestDummy) becomes Downed. Spawns
-- a Cabin near them and teleports them inside.
function CabinService.TrapDowned(target)
	if trappedData[target] then
		return
	end

	local characterModel = getCharacterModel(target)
	local rootPart = characterModel and characterModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local hookCount = getHookCount(target)
	if hookCount >= HOOK_LIVES then
		-- Already used all 3 hooks -- this trapping is fatal, no cabin,
		-- no rescue window at all. "100% dead no matter what."
		print(target.Name .. " has used all " .. HOOK_LIVES .. " hooks -- no rescue this time.")
		setTargetState(target, PlayerStateService.States.Dead)
		return
	end

	local spawnPosition = findCabinSpawnPosition(rootPart.Position)
	local cabinModel = cabinTemplate:Clone()
	cabinModel.Name = "Cabin_" .. target.Name

	-- The raycast in findCabinSpawnPosition gives us the floor's surface,
	-- but PivotTo places the model's pivot AT that point -- if the pivot
	-- isn't already at the model's base, this sinks it into the floor.
	-- Measure how far the pivot sits above the model's actual lowest
	-- point (in its default pose) and lift the placement by that amount.
	local boundingCFrame, boundingSize = cabinModel:GetBoundingBox()
	local lowestY = boundingCFrame.Position.Y - (boundingSize.Y / 2)
	local pivotY = cabinModel:GetPivot().Position.Y
	local groundOffset = pivotY - lowestY

	cabinModel:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, groundOffset, 0)))
	cabinModel:SetAttribute("TrappedPlayerName", target.Name)
	cabinModel.Parent = cabinsFolder

	local teleportPoint = cabinModel:FindFirstChild("TeleportPoint", true)
	if not teleportPoint then
		warn("CabinService: Cabin template has no TeleportPoint attachment -- destroying and aborting trap.")
		cabinModel:Destroy()
		return
	end

	rootPart.Anchored = true
	rootPart.CFrame = teleportPoint.WorldCFrame
	for _, part in ipairs(characterModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end

	local originalTransparency = {}
	setCharacterTransparency(characterModel, 1, originalTransparency)

	trappedData[target] = {
		cabinModel = cabinModel,
		phaseStartTime = tick(),
		rescuers = {},
		originalTransparency = originalTransparency,
	}

	setTargetState(target, PlayerStateService.States.Hooked)
	target:SetAttribute("CabinRescueProgress", 0)

	print(target.Name .. " was trapped in a Cabin (hook " .. (hookCount + 1) .. "/" .. HOOK_LIVES .. ")")
end

cabinRescueRemote.OnServerEvent:Connect(function(rescuerPlayer, target, action)
	if not target then
		return
	end
	local data = trappedData[target]
	if not data then
		return
	end

	if action == "start" then
		if rescuerActiveTarget[rescuerPlayer] then
			return
		end

		local rescuerCharacter = rescuerPlayer.Character
		local rescuerRoot = rescuerCharacter and rescuerCharacter:FindFirstChild("HumanoidRootPart")
		if not rescuerRoot then
			return
		end

		-- Distance checked against the CABIN's door, not the target's
		-- position -- they're enclosed inside, so the door is the actual
		-- interaction point.
		local door = data.cabinModel:FindFirstChild("Door", true)
		local doorPosition = door and (door:IsA("BasePart") and door.Position or door.WorldPosition)
		if not doorPosition then
			return
		end
		if (rescuerRoot.Position - doorPosition).Magnitude > MAX_RESCUE_DISTANCE then
			return
		end

		data.rescuers[rescuerPlayer] = true
		rescuerActiveTarget[rescuerPlayer] = target
	elseif action == "stop" then
		local activeTarget = rescuerActiveTarget[rescuerPlayer]
		if activeTarget then
			local activeData = trappedData[activeTarget]
			if activeData then
				activeData.rescuers[rescuerPlayer] = nil
			end
			ProgressBarService.Hide(rescuerPlayer)
			rescuerActiveTarget[rescuerPlayer] = nil
		end
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	for target, data in pairs(trappedData) do
		local elapsed = tick() - data.phaseStartTime
		if elapsed >= CABIN_TIMEOUT then
			killTarget(target)
		end
	end

	for target, data in pairs(trappedData) do
		local rescuerCount = 0
		for _ in pairs(data.rescuers) do
			rescuerCount += 1
		end
		if rescuerCount > 0 then
			local progress = target:GetAttribute("CabinRescueProgress") or 0
			progress = math.min(100, progress + RESCUE_RATE_PER_SECOND * rescuerCount * deltaTime)
			target:SetAttribute("CabinRescueProgress", progress)
			for rescuer in pairs(data.rescuers) do
				ProgressBarService.Update(rescuer, "OpeningDoor", progress)
			end
			if progress >= 100 then
				rescueTarget(target)
			end
		end
	end
end)

return CabinService