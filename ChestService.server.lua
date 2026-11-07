-- ChestService.server.lua
-- Custom E-hold system (no ProximityPrompt, no floating label).
-- Fuse chests: hold E -> ChestStruggle loops the whole time -> at 100%,
-- chest fades out and player is instantly holding a fuse (no separate
-- open animation, no fuse spawned on the ground).
-- Item chests: same loop, but spawns a Flashlight/Toolbox on the ground.
--
-- SPAWN MODE (fuse chests only): fuse chests are cloned onto random points of
-- the active map's "FuseChestSpawns" folder at the start of every round
-- (SpawnFuseChests BindableFunction, called by LobbyService). Placed chest
-- models in that folder act as position markers: the first one becomes the
-- template (unless ServerStorage.FuseChestTemplate exists) and all of them
-- are removed at runtime.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ProgressBarService = require(ReplicatedStorage.Shared.ProgressBarService)
local ActionAnimationService = require(ReplicatedStorage.Shared.ActionAnimationService)
local FuseService = require(script.Parent.FuseService)

local SEARCH_RATE_PER_SECOND = 8
local MAX_INTERACT_DISTANCE = 8
local FADE_OUT_TIME = 0.6

-- 3 fuseboxes x 4 fuses = 12 fuses needed, and each fuse chest gives exactly 1.
-- Spawning a couple of spare chests keeps the stage completable if one is hard to reach.
local FUSE_CHEST_COUNT = 14
local SPAWNS_FOLDER_NAME = "FuseChestSpawns" -- searched for inside the active map (any depth)
local SPAWN_OFFSET = CFrame.new(0, 0, 0) -- nudge if chests float/sink relative to the spawn points

local chestsFolder = Workspace:WaitForChild("Chests")
local templatesFolder = ReplicatedStorage:WaitForChild("Templates")

local chestData = {} -- [chestModel] = { progress = 0, completed = false, searcher = nil }
local activeSearch = {} -- [player] = { chestModel, phase = "searching" }
local spawnPointCache = {} -- [spawnsFolder] = { CFrame, ... } (filled the first time a map is used)

-- Template: ServerStorage.FuseChestTemplate if it exists, otherwise the first
-- fuse chest hand-placed in Workspace.Chests gets copied into ServerStorage.
-- (If neither exists, the first chest marker in FuseChestSpawns is used later.)
local fuseChestTemplate = ServerStorage:FindFirstChild("FuseChestTemplate")
if not fuseChestTemplate then
	for _, child in ipairs(chestsFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("ChestType") == "Fuse" then
			fuseChestTemplate = child:Clone()
			fuseChestTemplate.Name = "FuseChestTemplate"
			fuseChestTemplate.Parent = ServerStorage
			break
		end
	end
end

local interactRemote = ReplicatedStorage:FindFirstChild("ChestInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "ChestInteract"
	interactRemote.Parent = ReplicatedStorage
end

local cancelRemote = ReplicatedStorage:FindFirstChild("CancelTimedAction")
if not cancelRemote then
	cancelRemote = Instance.new("RemoteEvent")
	cancelRemote.Name = "CancelTimedAction"
	cancelRemote.Parent = ReplicatedStorage
end

local function findMainPart(chestModel)
	for _, descendant in ipairs(chestModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function stopSearch(player)
	local search = activeSearch[player]
	if not search then
		return
	end

	local data = chestData[search.chestModel]
	if data and data.searcher == player then
		data.searcher = nil
	end

	ActionAnimationService.Stop(player)
	ProgressBarService.Hide(player)
	activeSearch[player] = nil
end

local function fadeOutChest(chestModel)
	for _, part in ipairs(chestModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			local tween = TweenService:Create(
				part,
				TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 1 }
			)
			tween:Play()
		end
	end

	task.delay(FADE_OUT_TIME, function()
		if chestModel and chestModel.Parent then
			chestModel:Destroy()
		end
	end)
end

local function giveFuseDirectly(player)
	if FuseService.IsHoldingFuse(player) then
		return -- already holding one
	end

	local template = templatesFolder:FindFirstChild("FuseTemplate")
	if not template then
		warn("No FuseTemplate found in ReplicatedStorage.Templates")
		return
	end

	local newFuse = template:Clone()
	newFuse.Parent = Workspace.Fuses
	FuseService.PickUp(player, newFuse)
	print(player.Name .. " received a fuse directly from a chest")
end

local function spawnItemReward(chestModel, spawnPosition)
	local itemName = (math.random(2) == 1) and "FlashlightTemplate" or "ToolboxTemplate"
	local template = templatesFolder:FindFirstChild(itemName)
	if not template then
		warn("No " .. itemName .. " found in ReplicatedStorage.Templates")
		return
	end

	local newItem = template:Clone()
	newItem.Parent = Workspace

	local templateCFrame = template:GetPivot()
	local rotationOnly = templateCFrame - templateCFrame.Position
	local finalCFrame = CFrame.new(spawnPosition) * rotationOnly

	if newItem:IsA("Model") then
		newItem:PivotTo(finalCFrame)
	elseif newItem:IsA("BasePart") then
		newItem.CFrame = finalCFrame
	end

	print(chestModel.Name .. " spawned a " .. itemName)
end

local function beginOpenPhase(player, chestModel)
	local search = activeSearch[player]
	if not search or search.chestModel ~= chestModel then
		return
	end

	local data = chestData[chestModel]
	if not data or data.completed then
		return
	end

	data.completed = true
	chestModel:SetAttribute("Completed", true)

	local chestType = chestModel:GetAttribute("ChestType")
	local mainPart = findMainPart(chestModel)
	local spawnPosition = mainPart and mainPart.Position or chestModel:GetPivot().Position

	ProgressBarService.Hide(player)
	ActionAnimationService.Stop(player)

	fadeOutChest(chestModel)

	if chestType == "Fuse" then
		giveFuseDirectly(player)
	elseif chestType == "Item" then
		spawnItemReward(chestModel, spawnPosition)
	else
		warn("Unknown or missing ChestType on " .. chestModel.Name .. ": " .. tostring(chestType))
	end

	activeSearch[player] = nil
end

local function setupChest(chestModel)
	chestData[chestModel] = { progress = 0, completed = false, searcher = nil }
	chestModel:SetAttribute("Completed", false)
end

-- === Spawning (fuse chests only) ===

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

-- Removes last round's fuse chests (item chests are left alone) and their data.
local function clearFuseChests()
	-- cancel anyone still searching a fuse chest
	for player, search in pairs(activeSearch) do
		if search.chestModel:GetAttribute("ChestType") == "Fuse" then
			stopSearch(player)
		end
	end

	for _, child in ipairs(chestsFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("ChestType") == "Fuse" then
			chestData[child] = nil
			child:Destroy()
		end
	end
end

-- Reads the spawn points of a FuseChestSpawns folder (cached after the first call).
-- Placed chest models are only position markers: the first one is kept as the
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
				if not fuseChestTemplate then
					fuseChestTemplate = child:Clone()
					fuseChestTemplate.Name = "FuseChestTemplate"
					fuseChestTemplate.Parent = ServerStorage
				end
				child:Destroy()
			end
		end
	end

	spawnPointCache[spawnsFolder] = points
	return points
end

-- Clones up to FUSE_CHEST_COUNT fuse chests onto random points of the given
-- map's FuseChestSpawns folder. Returns how many were spawned.
local function spawnFuseChests(mapFolder)
	clearFuseChests()

	local spawnsFolder = mapFolder and mapFolder:FindFirstChild(SPAWNS_FOLDER_NAME, true)
	if not spawnsFolder then
		warn("ChestService: no '" .. SPAWNS_FOLDER_NAME .. "' found inside " .. tostring(mapFolder and mapFolder:GetFullName()))
		return 0
	end

	local points = getSpawnPoints(spawnsFolder)

	if not fuseChestTemplate then
		warn("ChestService: no fuse chest template. Put a chest model in " .. spawnsFolder:GetFullName() .. " or a model named FuseChestTemplate in ServerStorage.")
		return 0
	end

	if #points < 12 then
		warn("ChestService: only " .. #points .. " fuse chest spawn point(s) in " .. spawnsFolder:GetFullName() .. ", but 12 fuses are needed (3 fuseboxes x 4 fuses) -- the Fuseboxes stage can NEVER be completed this round.")
	end

	local shuffled = table.clone(points)
	shuffle(shuffled)
	local count = math.min(FUSE_CHEST_COUNT, #shuffled)

	for i = 1, count do
		local chestModel = fuseChestTemplate:Clone()
		chestModel.Name = "FuseChest" .. i
		chestModel:SetAttribute("ChestType", "Fuse")
		chestModel:PivotTo(shuffled[i] * SPAWN_OFFSET)
		chestModel.Parent = chestsFolder
		setupChest(chestModel)
	end

	print("ChestService: spawned " .. count .. " fuse chest(s) on " .. mapFolder.Name .. " (" .. #points .. " spawn points available).")
	return count
end

local spawnFuseChestsFunction = Instance.new("BindableFunction")
spawnFuseChestsFunction.Name = "SpawnFuseChests"
spawnFuseChestsFunction.Parent = script
spawnFuseChestsFunction.OnInvoke = function(mapFolder)
	return spawnFuseChests(mapFolder)
end

-- === End spawning ===

interactRemote.OnServerEvent:Connect(function(player, chestModel, action)
	if not chestModel or not chestModel:IsDescendantOf(chestsFolder) then
		return
	end

	if player:GetAttribute("IsKiller") then
		return
	end

	local data = chestData[chestModel]
	if not data or data.completed then
		return
	end

	if action == "start" then
		if activeSearch[player] then
			return
		end

		if data.searcher and data.searcher ~= player then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local mainPart = findMainPart(chestModel)
		if not root or not mainPart then
			return
		end

		if (root.Position - mainPart.Position).Magnitude > MAX_INTERACT_DISTANCE then
			return
		end

		local snapFolder = chestModel:FindFirstChild("SnapPoints")
		local snap = snapFolder and snapFolder:FindFirstChild("Front")
		if snap and character then
			character:PivotTo(snap.WorldCFrame)
		end

		data.searcher = player
		activeSearch[player] = { chestModel = chestModel, phase = "searching" }

		ActionAnimationService.Play(player, "ChestStruggle")
	elseif action == "stop" then
		stopSearch(player)
	end
end)

cancelRemote.OnServerEvent:Connect(function(player)
	if activeSearch[player] then
		stopSearch(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if activeSearch[player] then
		stopSearch(player)
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	for player, search in pairs(activeSearch) do
		if search.phase == "searching" then
			local chestModel = search.chestModel
			local data = chestData[chestModel]

			data.progress = math.min(100, data.progress + SEARCH_RATE_PER_SECOND * deltaTime)
			ProgressBarService.Update(player, "Searching", data.progress)

			if data.progress >= 100 then
				beginOpenPhase(player, chestModel)
			end
		end
	end
end)

local totalChests = 0
for _, chestModel in ipairs(chestsFolder:GetChildren()) do
	if chestModel:IsA("Model") then
		if fuseChestTemplate and chestModel:GetAttribute("ChestType") == "Fuse" then
			-- Spawn mode: hand-placed fuse chests are removed at runtime (your Studio
			-- file is untouched); fresh ones are spawned each round.
			chestModel:Destroy()
		else
			setupChest(chestModel)
			totalChests += 1
		end
	end
end

if fuseChestTemplate then
	print("ChestService loaded (spawn mode for fuse chests). Tracking " .. totalChests .. " other chest(s).")
else
	print("ChestService loaded. Tracking " .. totalChests .. " chest(s); fuse chests will spawn from " .. SPAWNS_FOLDER_NAME .. " at round start.")
end