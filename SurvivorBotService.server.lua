-- SurvivorBotService.server.lua
-- TEST TOOL: spawns simple survivor bots that pathfind to generators,
-- repair them via GeneratorService's bot bridge, and flee if the killer
-- gets close. First increment -- fuseboxes/chests/pallets/vaults follow
-- once this is confirmed working.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PathfindingService = game:GetService("PathfindingService")

local StageManager = require(ServerScriptService.Server.StageManager)

local FLEE_DISTANCE = 20
local FLEE_MOVE_DISTANCE = 15
local MAX_BOTS_PER_REQUEST = 4

local generatorsFolder = Workspace:WaitForChild("Generators")
local fuseBoxesFolder = Workspace:WaitForChild("FuseBoxes")
local fusesFolder = Workspace:WaitForChild("Fuses")

local generatorScript = ServerScriptService.Server:WaitForChild("GeneratorService")
local botRepairAction = generatorScript:WaitForChild("BotRepairAction")
local getMainPartPosition = generatorScript:WaitForChild("GetMainPartPosition")

local fuseboxScript = ServerScriptService.Server:WaitForChild("FuseboxService")
local botOpenDoor = fuseboxScript:WaitForChild("BotOpenDoor")
local botInsertFuse = fuseboxScript:WaitForChild("BotInsertFuse")
local isFuseboxFull = fuseboxScript:WaitForChild("IsFuseboxFull")

local fusePickupScript = ServerScriptService.Server:WaitForChild("FusePickup")
local botPickupFuse = fusePickupScript:WaitForChild("BotPickupFuse")
local getFusePosition = fusePickupScript:WaitForChild("GetFusePosition")

local lobbyFolder = Workspace:WaitForChild("Lobby")
local tunnelExitModel = lobbyFolder:WaitForChild("TunnelExitModel")
local tunnelExit = tunnelExitModel:WaitForChild("TunnelExit")

local templatesFolder = ReplicatedStorage:FindFirstChild("Templates")
local botTemplate = templatesFolder and templatesFolder:FindFirstChild("TestDummy")

local spawnBotsRemote = ReplicatedStorage:FindFirstChild("SpawnSurvivorBots")
if not spawnBotsRemote then
	spawnBotsRemote = Instance.new("RemoteEvent")
	spawnBotsRemote.Name = "SpawnSurvivorBots"
	spawnBotsRemote.Parent = ReplicatedStorage
end

local botCounter = 0

local function findKillerCharacter()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("IsKiller") and player.Character then
			return player.Character
		end
	end
	return nil
end

-- Uses GeneratorService's own proven-correct internal lookup (the exact
-- same one real players' repair distance-check uses every round) instead
-- of guessing independently.
local function getGeneratorTargetPosition(generatorModel)
	return getMainPartPosition:Invoke(generatorModel)
end

local function findNearestIncompleteGenerator(fromPosition)
	local nearest, nearestDist = nil, math.huge
	for _, generatorModel in ipairs(generatorsFolder:GetChildren()) do
		if generatorModel:IsA("Model") and not generatorModel:GetAttribute("Completed") then
			local targetPosition = getGeneratorTargetPosition(generatorModel)
			if targetPosition then
				local dist = (targetPosition - fromPosition).Magnitude
				if dist < nearestDist then
					nearest = generatorModel
					nearestDist = dist
				end
			end
		end
	end
	return nearest
end

-- botHeldFuse[botId] = the fuse instance a bot is currently carrying, or
-- nil. Tracked entirely here rather than in FuseService, since that's
-- keyed by real Player and fires a client remote bots can't receive.
local botHeldFuse = {}

local function findNearestAvailableFusebox(fromPosition)
	local nearest, nearestDist = nil, math.huge
	for _, fuseboxModel in ipairs(fuseBoxesFolder:GetChildren()) do
		if fuseboxModel:IsA("Model") and not isFuseboxFull:Invoke(fuseboxModel) then
			local doorPart = fuseboxModel:FindFirstChild("FuseboxDoor")
			local referencePoint = doorPart and doorPart.Position or fuseboxModel:GetPivot().Position
			local dist = (referencePoint - fromPosition).Magnitude
			if dist < nearestDist then
				nearest = fuseboxModel
				nearestDist = dist
			end
		end
	end
	return nearest
end

local function findNearestAvailableFuse(fromPosition)
	local nearest, nearestDist = nil, math.huge
	for _, fuseInstance in ipairs(fusesFolder:GetChildren()) do
		local position = getFusePosition:Invoke(fuseInstance)
		if position then
			local dist = (position - fromPosition).Magnitude
			if dist < nearestDist then
				nearest = fuseInstance
				nearestDist = dist
			end
		end
	end
	return nearest
end

-- Fallback movement: walk straight at the target. If stuck against
-- something, slide along it (like a hand tracing a wall) instead of a
-- random nudge each time -- picks one side and commits to it so it
-- actually clears the obstacle instead of jittering in place, and
-- presses slightly forward each slide so it can round a corner.
local function moveDirect(humanoid, rootPart, targetPosition, shouldAbort, stopDistance)
	local maxConsecutiveStuck = 8 -- give up only after this many BACK-TO-BACK failed attempts
	local maxTotalAttempts = 120 -- generous absolute safety net (~2-3 min), not a normal-case limit
	local consecutiveStuck = 0
	local sidestepDirection = nil -- persists across stuck attempts until progress resumes

	for _ = 1, maxTotalAttempts do
		if shouldAbort() then
			return false
		end

		local currentDistance = (rootPart.Position - targetPosition).Magnitude
		if currentDistance <= stopDistance then
			return true
		end

		humanoid:MoveTo(targetPosition)
		local startPosition = rootPart.Position
		task.wait(1)

		if shouldAbort() then
			return false
		end

		local moved = (rootPart.Position - startPosition).Magnitude
		if moved >= 2 then
			consecutiveStuck = 0
			sidestepDirection = nil -- making progress again, forget the old dodge
		else
			consecutiveStuck += 1
			if consecutiveStuck > maxConsecutiveStuck then
				return false -- genuinely stuck for too long, give up
			end

			local towardTarget = targetPosition - rootPart.Position
			towardTarget = Vector3.new(towardTarget.X, 0, towardTarget.Z)
			towardTarget = towardTarget.Magnitude > 0.1 and towardTarget.Unit or Vector3.new(1, 0, 0)
			local perpendicular = Vector3.new(-towardTarget.Z, 0, towardTarget.X)

			if not sidestepDirection then
				sidestepDirection = (math.random() < 0.5) and perpendicular or -perpendicular
			end

			local slideTarget = rootPart.Position + sidestepDirection * 8 + towardTarget * 4
			humanoid:MoveTo(slideTarget)
			task.wait(0.75)
		end
	end

	return false
end

-- Tries a real computed path first (properly routes around obstacles,
-- through doorways, etc., instead of walking straight at them). Falls
-- back to moveDirect if pathfinding fails for any reason -- this map has
-- shown NoPath even for reachable targets before, so PathfindingService
-- alone isn't reliable enough here, but it's a real improvement when it
-- does succeed.
local function moveTo(humanoid, rootPart, targetPosition, shouldAbort, stopDistance)
	stopDistance = stopDistance or 4
	print("SurvivorBotService: moveTo called, current pos =", rootPart.Position, "target =", targetPosition, "distance =", (rootPart.Position - targetPosition).Magnitude)

	if (rootPart.Position - targetPosition).Magnitude <= stopDistance then
		print("SurvivorBotService: already within stopDistance, returning true immediately")
		return true
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = 1.5,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4,
	})

	local computed = pcall(function()
		path:ComputeAsync(rootPart.Position, targetPosition)
	end)

	if computed and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		for _, waypoint in ipairs(waypoints) do
			if shouldAbort() then
				return false
			end
			if (waypoint.Position - rootPart.Position).Magnitude <= stopDistance then
				return true -- already close enough, no need to reach the exact final waypoint
			end
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			humanoid:MoveTo(waypoint.Position)
			local reached = humanoid.MoveToFinished:Wait()
			if not reached and (waypoint.Position - rootPart.Position).Magnitude > stopDistance then
				-- Got stuck partway along an otherwise-valid path -- drop to
				-- direct movement for the remainder rather than failing outright.
				return moveDirect(humanoid, rootPart, targetPosition, shouldAbort, stopDistance)
			end
		end
		return true
	end

	-- Pathfinding failed outright (NoPath, timeout, etc.) -- fall back.
	return moveDirect(humanoid, rootPart, targetPosition, shouldAbort, stopDistance)
end

local function fleeFromKiller(humanoid, rootPart)
	local killer = findKillerCharacter()
	if not killer then
		return
	end
	local killerRoot = killer:FindFirstChild("HumanoidRootPart")
	if not killerRoot then
		return
	end

	local away = rootPart.Position - killerRoot.Position
	if away.Magnitude < 1 then
		away = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
	end
	away = away.Unit

	humanoid:MoveTo(rootPart.Position + away * FLEE_MOVE_DISTANCE)
end

local function seekAndRepairGenerator(botModel, botId, humanoid, rootPart, shouldFleeFn)
	local generator = findNearestIncompleteGenerator(rootPart.Position)
	if not generator then
		local totalGenerators = 0
		local completedCount = 0
		for _, g in ipairs(generatorsFolder:GetChildren()) do
			if g:IsA("Model") then
				totalGenerators += 1
				if g:GetAttribute("Completed") then
					completedCount += 1
				end
			end
		end
		print("SurvivorBotService: " .. botId .. " found no incomplete generator. Generators folder has " .. totalGenerators .. " total, " .. completedCount .. " marked Completed.")
		task.wait(2)
		return
	end

	local targetPosition = getGeneratorTargetPosition(generator)
	if not targetPosition then
		task.wait(2)
		return
	end

	local reached = moveTo(humanoid, rootPart, targetPosition, shouldFleeFn, 8)
	if reached and not shouldFleeFn() then
		local started = botRepairAction:Invoke("start", botId, generator, botModel)
		if started then
			while generator.Parent and not generator:GetAttribute("Completed") and not shouldFleeFn() and botModel.Parent do
				task.wait(0.5)
			end
			botRepairAction:Invoke("stop", botId, generator)
		end
	end
end

-- Each call advances by one step: walk to+open the door, OR walk to+pick
-- up a fuse, OR walk to+insert a held fuse. Which step runs depends on
-- current state, so repeated calls from the main loop naturally progress
-- through the whole sequence over successive iterations.
local function seekAndPowerFusebox(botModel, botId, humanoid, rootPart, shouldFleeFn)
	local fusebox = findNearestAvailableFusebox(rootPart.Position)
	if not fusebox then
		task.wait(2)
		return
	end

	if not fusebox:GetAttribute("Opened") then
		local doorPart = fusebox:FindFirstChild("FuseboxDoor")
		if not doorPart then
			task.wait(2)
			return
		end
		local reached = moveTo(humanoid, rootPart, doorPart.Position, shouldFleeFn, 6)
		if reached and not shouldFleeFn() then
			botOpenDoor:Invoke(fusebox)
		end
		return
	end

	if not botHeldFuse[botId] then
		local fuseInstance = findNearestAvailableFuse(rootPart.Position)
		if not fuseInstance then
			task.wait(2)
			return
		end
		local fusePosition = getFusePosition:Invoke(fuseInstance)
		if not fusePosition then
			task.wait(2)
			return
		end
		local reached = moveTo(humanoid, rootPart, fusePosition, shouldFleeFn, 5)
		if reached and not shouldFleeFn() then
			if botPickupFuse:Invoke(fuseInstance, botModel) then
				botHeldFuse[botId] = fuseInstance
			end
		end
		return
	end

	local interior = fusebox:FindFirstChild("Interior")
	if not interior then
		task.wait(2)
		return
	end
	local reached = moveTo(humanoid, rootPart, interior.Position, shouldFleeFn, 6)
	if reached and not shouldFleeFn() then
		if botInsertFuse:Invoke(fusebox, botModel, botHeldFuse[botId]) then
			botHeldFuse[botId] = nil
		end
	end
end

local function botBrain(botModel, botId, humanoid, rootPart)
	local shouldFlee = false
	local function shouldFleeFn()
		return shouldFlee
	end

	-- Background watcher: continuously checks killer distance so the
	-- main loop below can be interrupted mid-path or mid-action.
	task.spawn(function()
		while botModel.Parent do
			local killer = findKillerCharacter()
			if killer then
				local killerRoot = killer:FindFirstChild("HumanoidRootPart")
				shouldFlee = killerRoot and (killerRoot.Position - rootPart.Position).Magnitude < FLEE_DISTANCE
			else
				shouldFlee = false
			end
			task.wait(0.5)
		end
	end)

	while botModel.Parent do
		if shouldFlee then
			fleeFromKiller(humanoid, rootPart)
			task.wait(1)
		else
			local currentStage = StageManager.GetCurrentStage()
			print("SurvivorBotService: " .. botId .. " current stage =", currentStage)
			if currentStage == "Generators" then
				seekAndRepairGenerator(botModel, botId, humanoid, rootPart, shouldFleeFn)
			elseif currentStage == "Fuseboxes" then
				seekAndPowerFusebox(botModel, botId, humanoid, rootPart, shouldFleeFn)
			else
				task.wait(2) -- no active stage right now
			end
		end
	end

	botHeldFuse[botId] = nil
end

-- Raycasts straight down to find the real floor at a jittered spot near
-- TunnelExit, rather than blindly offsetting from TunnelExit's own CFrame
-- (which can land inside nearby geometry -- low ceilings, roof beams,
-- etc. -- and cause a violent ragdoll separation on spawn).
local function findSafeSpawnPosition()
	local jitterX = math.random(-5, 5)
	local jitterZ = math.random(-5, 5)
	local basePosition = tunnelExit.Position + Vector3.new(jitterX, 0, jitterZ)
	local rayOrigin = basePosition + Vector3.new(0, 50, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	local result = Workspace:Raycast(rayOrigin, Vector3.new(0, -100, 0), raycastParams)
	if result then
		return result.Position + Vector3.new(0, 3, 0)
	end

	-- Fallback if the raycast somehow hits nothing (open sky, etc.)
	return tunnelExit.Position + Vector3.new(0, 3, 0)
end

local function spawnBot()
	if not botTemplate then
		warn("SurvivorBotService: no template found at ReplicatedStorage.Templates.TestDummy -- cannot spawn bot.")
		return
	end

	botCounter += 1
	local botId = "Bot_" .. botCounter

	local botModel = botTemplate:Clone()
	botModel.Name = botId
	botModel:PivotTo(CFrame.new(findSafeSpawnPosition()))
	botModel.Parent = Workspace

	local humanoid = botModel:WaitForChild("Humanoid")
	local rootPart = botModel:WaitForChild("HumanoidRootPart")

	task.spawn(function()
		botBrain(botModel, botId, humanoid, rootPart)
	end)

	print("SurvivorBotService: spawned " .. botId)
end

spawnBotsRemote.OnServerEvent:Connect(function(player, count)
	count = math.clamp(count or 1, 1, MAX_BOTS_PER_REQUEST)
	for _ = 1, count do
		spawnBot()
	end
end)

if not botTemplate then
	warn("SurvivorBotService: ReplicatedStorage.Templates.TestDummy not found -- update the path in this script if your dummy lives elsewhere.")
end

print("SurvivorBotService loaded.")