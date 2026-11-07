-- GeneratorService.server.lua
-- Custom E-hold system (GeneratorInteract remote) instead of ProximityPrompt.
-- Snaps the player to the nearest side, plays Main/Side generator animation.
--
-- SPAWN MODE: generators are cloned from a template onto random points of the
-- active map's "GeneratorSpawns" folder at the start of every round (see the
-- SpawnGenerators BindableFunction, called by LobbyService).
-- The spawn points can be invisible parts, attachments, or placed generator
-- models: placed models are used as position markers, the first one becomes the
-- template (unless ServerStorage.GeneratorTemplate exists), and they are all
-- removed at runtime so they don't act as unusable decoys.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ProgressBarService = require(ReplicatedStorage.Shared.ProgressBarService)
local ActionAnimationService = require(ReplicatedStorage.Shared.ActionAnimationService)
local StageManager = require(script.Parent.StageManager)

local REPAIR_RATE_PER_SECOND = 5
local REGRESS_RATE_PER_SECOND = 0.75 -- how fast an unattended generator loses progress; tune to taste
local MAX_PROGRESS = 100
local MAX_INTERACT_DISTANCE = 7

local REQUIRED_GENERATOR_COUNT = 3
local SPAWNS_FOLDER_NAME = "GeneratorSpawns" -- searched for inside the active map (any depth)
local SPAWN_OFFSET = CFrame.new(0, 0, 0) -- nudge if generators float/sink relative to the spawn points

local generatorsFolder = Workspace:WaitForChild("Generators")

local generatorData = {}
local activeGeneratorForPlayer = {}
local spawnPointCache = {} -- [spawnsFolder] = { CFrame, ... } (filled the first time a map is used)

-- Template: ServerStorage.GeneratorTemplate if it exists, otherwise the first
-- generator hand-placed in Workspace.Generators gets copied into ServerStorage.
-- (If neither exists, the first generator marker in GeneratorSpawns is used later.)
local generatorTemplate = ServerStorage:FindFirstChild("GeneratorTemplate")
if not generatorTemplate then
	for _, child in ipairs(generatorsFolder:GetChildren()) do
		if child:IsA("Model") then
			generatorTemplate = child:Clone()
			generatorTemplate.Name = "GeneratorTemplate"
			generatorTemplate.Parent = ServerStorage
			break
		end
	end
end

local interactRemote = ReplicatedStorage:FindFirstChild("GeneratorInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "GeneratorInteract"
	interactRemote.Parent = ReplicatedStorage
end

local function findMainPart(generatorModel)
	if generatorModel.PrimaryPart then
		return generatorModel.PrimaryPart
	end
	for _, descendant in ipairs(generatorModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function findNearestSnap(generatorModel, player)
	local snapFolder = generatorModel:FindFirstChild("SnapPoints")
	if not snapFolder then
		return nil
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local nearest, nearestDist = nil, math.huge
	for _, attachment in ipairs(snapFolder:GetChildren()) do
		if attachment:IsA("Attachment") then
			local dist = (attachment.WorldPosition - root.Position).Magnitude
			if dist < nearestDist then
				nearest = attachment
				nearestDist = dist
			end
		end
	end
	return nearest
end

local function getAnimNameForSnap(attachmentName)
	if attachmentName == "Front" or attachmentName == "Back" then
		return "MainGenerator"
	elseif attachmentName == "Left" or attachmentName == "Right" then
		return "SideGenerator"
	end
	return nil
end

local function stopRepairing(generatorModel, player)
	local data = generatorData[generatorModel]
	if data then
		data.repairingPlayers[player] = nil
	end

	ProgressBarService.Hide(player)
	ActionAnimationService.Stop(player)

	if activeGeneratorForPlayer[player] == generatorModel then
		activeGeneratorForPlayer[player] = nil
	end
end

local function setupGenerator(generatorModel)
	generatorData[generatorModel] = {
		progress = 0,
		repairingPlayers = {},
		botRepairers = {}, -- [botId] = true -- bots tracked separately, no PlayerGui/animation calls
		completed = false,
	}
	generatorModel:SetAttribute("Completed", false)
	generatorModel:SetAttribute("Progress", 0)
end

-- === Spawning ===

local function getSpawnCFrame(spawnInstance)
	if spawnInstance:IsA("BasePart") then
		return spawnInstance.CFrame
	elseif spawnInstance:IsA("Attachment") then
		return spawnInstance.WorldCFrame
	elseif spawnInstance:IsA("Model") then
		return spawnInstance:GetPivot()
	end
	return nil
end

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Removes last round's generators and all their tracking data.
local function clearGenerators()
	for generatorModel, data in pairs(generatorData) do
		for player in pairs(data.repairingPlayers) do
			stopRepairing(generatorModel, player)
		end
	end

	for generatorModel in pairs(generatorData) do
		generatorData[generatorModel] = nil
	end
	for player in pairs(activeGeneratorForPlayer) do
		activeGeneratorForPlayer[player] = nil
	end

	for _, child in ipairs(generatorsFolder:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
end

-- Reads the spawn points of a GeneratorSpawns folder (cached after the first call).
-- Placed generator models are only position markers: the first one is kept as the
-- template (if there's none yet), and all of them are removed so there are no decoys.
local function getSpawnPoints(spawnsFolder)
	local cached = spawnPointCache[spawnsFolder]
	if cached then
		return cached
	end

	local points = {}
	for _, child in ipairs(spawnsFolder:GetChildren()) do
		local cf = getSpawnCFrame(child)
		if cf then
			table.insert(points, cf)

			if child:IsA("Model") then
				if not generatorTemplate then
					generatorTemplate = child:Clone()
					generatorTemplate.Name = "GeneratorTemplate"
					generatorTemplate.Parent = ServerStorage
				end
				child:Destroy()
			end
		end
	end

	spawnPointCache[spawnsFolder] = points
	return points
end

-- Clones REQUIRED_GENERATOR_COUNT generators onto random points of the given
-- map's GeneratorSpawns folder. Returns how many were spawned.
local function spawnGenerators(mapFolder)
	clearGenerators()

	local spawnsFolder = mapFolder and mapFolder:FindFirstChild(SPAWNS_FOLDER_NAME, true)
	if not spawnsFolder then
		warn("GeneratorService: no '" .. SPAWNS_FOLDER_NAME .. "' found inside " .. tostring(mapFolder and mapFolder:GetFullName()))
		return 0
	end

	local points = getSpawnPoints(spawnsFolder)

	if not generatorTemplate then
		warn("GeneratorService: no generator template. Put a generator model in " .. spawnsFolder:GetFullName() .. " or a model named GeneratorTemplate in ServerStorage.")
		return 0
	end

	if #points < REQUIRED_GENERATOR_COUNT then
		warn("GeneratorService: only " .. #points .. " spawn point(s) in " .. spawnsFolder:GetFullName() .. ", but " .. REQUIRED_GENERATOR_COUNT .. " generators are required -- the Generators stage can NEVER be completed this round.")
	end

	-- shuffle a copy so the cached list keeps its order (it doesn't matter, but stays clean)
	local shuffled = table.clone(points)
	shuffle(shuffled)
	local count = math.min(REQUIRED_GENERATOR_COUNT, #shuffled)

	for i = 1, count do
		local generatorModel = generatorTemplate:Clone()
		generatorModel.Name = "Generator" .. i
		generatorModel:PivotTo(shuffled[i] * SPAWN_OFFSET)
		generatorModel.Parent = generatorsFolder
		setupGenerator(generatorModel)
	end

	print("GeneratorService: spawned " .. count .. " generator(s) on " .. mapFolder.Name .. " (" .. #points .. " spawn points available).")
	return count
end

local spawnGeneratorsFunction = Instance.new("BindableFunction")
spawnGeneratorsFunction.Name = "SpawnGenerators"
spawnGeneratorsFunction.Parent = script
spawnGeneratorsFunction.OnInvoke = function(mapFolder)
	return spawnGenerators(mapFolder)
end

-- === End spawning ===

interactRemote.OnServerEvent:Connect(function(player, generatorModel, action)
	if not generatorModel or not generatorModel:IsDescendantOf(generatorsFolder) then
		return
	end

	if player:GetAttribute("IsKiller") then
		return
	end

	local data = generatorData[generatorModel]
	if not data or data.completed then
		return
	end

	if not StageManager.IsStageActive("Generators") then
		return
	end

	if action == "start" then
		if activeGeneratorForPlayer[player] then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local mainPart = findMainPart(generatorModel)
		if not root or not mainPart then
			return
		end

		if (root.Position - mainPart.Position).Magnitude > MAX_INTERACT_DISTANCE then
			return
		end

		local snap = findNearestSnap(generatorModel, player)
		if snap and character then
			character:PivotTo(snap.WorldCFrame)

			local animName = getAnimNameForSnap(snap.Name)
			if animName then
				ActionAnimationService.Play(player, animName)
			end
		end

		data.repairingPlayers[player] = true
		activeGeneratorForPlayer[player] = generatorModel
	elseif action == "stop" then
		stopRepairing(generatorModel, player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for generatorModel, data in pairs(generatorData) do
		data.repairingPlayers[player] = nil
	end
	activeGeneratorForPlayer[player] = nil
end)

-- === Bot support ===
-- Purely additive: bots aren't real Players, so they can't call the
-- interactRemote above at all (that requires an actual client firing
-- FireServer). This BindableFunction is a parallel entry point bots call
-- directly (same server, no remote needed). None of the logic above is
-- touched -- real players are completely unaffected by this.

local botRepairAction = Instance.new("BindableFunction")
botRepairAction.Name = "BotRepairAction"
botRepairAction.Parent = script

botRepairAction.OnInvoke = function(action, botId, generatorModel, botCharacter)
	local data = generatorData[generatorModel]
	if not data or data.completed then
		return false
	end

	if not StageManager.IsStageActive("Generators") then
		return false
	end

	if action == "start" then
		local root = botCharacter and botCharacter:FindFirstChild("HumanoidRootPart")
		local mainPart = findMainPart(generatorModel)
		if not root or not mainPart then
			return false
		end

		if (root.Position - mainPart.Position).Magnitude > MAX_INTERACT_DISTANCE then
			return false
		end

		data.botRepairers[botId] = true
		return true
	elseif action == "stop" then
		data.botRepairers[botId] = nil
		return true
	end

	return false
end

-- Exposes the SAME internal findMainPart() real players' interactRemote
-- handler already uses successfully every round. Bots call this instead
-- of guessing at PrimaryPart/GetPivot/SnapPoints independently -- those
-- three separate guesses all kept landing on the wrong position, while
-- this exact function is proven correct by real player use.
local getMainPartPosition = Instance.new("BindableFunction")
getMainPartPosition.Name = "GetMainPartPosition"
getMainPartPosition.Parent = script

getMainPartPosition.OnInvoke = function(generatorModel)
	local mainPart = findMainPart(generatorModel)
	if mainPart then
		return mainPart.Position
	end
	return nil
end

-- === End bot support ===

RunService.Heartbeat:Connect(function(deltaTime)
	for generatorModel, data in pairs(generatorData) do
		if not data.completed then
			local repairerCount = 0
			for _ in pairs(data.repairingPlayers) do
				repairerCount += 1
			end
			for _ in pairs(data.botRepairers) do
				repairerCount += 1
			end

			if repairerCount > 0 then
				data.progress = math.min(MAX_PROGRESS, data.progress + (REPAIR_RATE_PER_SECOND * repairerCount * deltaTime))
				generatorModel:SetAttribute("Progress", data.progress)

				for player in pairs(data.repairingPlayers) do
					ProgressBarService.Update(player, "Repairing", data.progress)
				end

				if data.progress >= MAX_PROGRESS then
					data.completed = true
					generatorModel:SetAttribute("Completed", true)

					local mainPart = findMainPart(generatorModel)
					if mainPart then
						mainPart.Color = Color3.fromRGB(0, 255, 0)
					end

					for player in pairs(data.repairingPlayers) do
						stopRepairing(generatorModel, player)
					end
					data.botRepairers = {}

					print(generatorModel.Name .. " has been repaired!")
					StageManager.NotifyObjectiveCompleted("Generators")
				end
			elseif data.progress > 0 then
				data.progress = math.max(0, data.progress - (REGRESS_RATE_PER_SECOND * deltaTime))
				generatorModel:SetAttribute("Progress", data.progress)
			end
		end
	end
end)

if generatorTemplate then
	-- Spawn mode: hand-placed generators in Workspace.Generators are removed at
	-- runtime (your Studio file is untouched); fresh ones are spawned each round.
	for _, child in ipairs(generatorsFolder:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	print("GeneratorService loaded (spawn mode). " .. REQUIRED_GENERATOR_COUNT .. " required per round.")
else
	-- No template yet. Either generators are placed in Workspace.Generators (old
	-- behavior), or the template will be taken from GeneratorSpawns at round start.
	local totalGenerators = 0
	for _, generatorModel in ipairs(generatorsFolder:GetChildren()) do
		if generatorModel:IsA("Model") then
			setupGenerator(generatorModel)
			totalGenerators += 1
		end
	end

	if totalGenerators == 0 then
		print("GeneratorService loaded. No generators placed; waiting for LobbyService to spawn them from " .. SPAWNS_FOLDER_NAME .. " at round start.")
	else
		print("GeneratorService loaded (static mode). Tracking " .. totalGenerators .. " generator(s).")
	end
end

StageManager.SetRequiredCount("Generators", REQUIRED_GENERATOR_COUNT)