-- StageManager.lua
-- Controls which objective stage is currently active, and unlocks
-- the next stage once the current one's requirement is met.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StageManager = {}

local STAGE_NAMES = { "Generators", "Fuseboxes" } -- add "FuelCanisters" later

local remoteEvent = ReplicatedStorage:FindFirstChild("StageUpdate")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "StageUpdate"
	remoteEvent.Parent = ReplicatedStorage
end

local remoteFunction = ReplicatedStorage:FindFirstChild("GetStageInfo")
if not remoteFunction then
	remoteFunction = Instance.new("RemoteFunction")
	remoteFunction.Name = "GetStageInfo"
	remoteFunction.Parent = ReplicatedStorage
end

local function shuffle(list)
	local result = table.clone(list)
	for i = #result, 2, -1 do
		local j = math.random(i)
		result[i], result[j] = result[j], result[i]
	end
	return result
end

local stageOrder = shuffle(STAGE_NAMES)
local currentStageIndex = 1

local requiredCounts = {}
local completedCounts = {}
for _, stageName in ipairs(STAGE_NAMES) do
	requiredCounts[stageName] = 0
	completedCounts[stageName] = 0
end

StageManager.StageChanged = Instance.new("BindableEvent")
StageManager.ObjectiveCompleted = Instance.new("BindableEvent")

function StageManager.GetCurrentStage()
	return stageOrder[currentStageIndex]
end

function StageManager.IsStageActive(stageName)
	return StageManager.GetCurrentStage() == stageName
end

local function broadcastUpdate()
	local stageName = StageManager.GetCurrentStage()
	if stageName then
		remoteEvent:FireAllClients(stageName, completedCounts[stageName], requiredCounts[stageName], currentStageIndex)
	else
		remoteEvent:FireAllClients(nil, 0, 0, currentStageIndex)
	end
end

function StageManager.SetRequiredCount(stageName, count)
	requiredCounts[stageName] = count
	if StageManager.IsStageActive(stageName) then
		broadcastUpdate()
	end
end

function StageManager.NotifyObjectiveCompleted(stageName)
	if not StageManager.IsStageActive(stageName) then
		return
	end
	completedCounts[stageName] += 1
	StageManager.ObjectiveCompleted:Fire(stageName)
	print(stageName .. " progress: " .. completedCounts[stageName] .. "/" .. requiredCounts[stageName])
	broadcastUpdate()

	if completedCounts[stageName] >= requiredCounts[stageName] then
		currentStageIndex += 1
		if currentStageIndex <= #stageOrder then
			local nextStage = stageOrder[currentStageIndex]
			print("Stage cleared! Now active: " .. nextStage)
			StageManager.StageChanged:Fire(nextStage)
			broadcastUpdate()
		else
			print("All stages complete! (exit gates would open here)")
			StageManager.StageChanged:Fire(nil)
			broadcastUpdate()
		end
	end
end

-- DEBUG/TESTING ONLY: instantly completes every remaining stage, firing
-- the exact same StageChanged(nil) signal as real completion would --
-- so it exercises the real escape-gate/escape-detection path, not a
-- separate shortcut that could behave differently. Bound to a test
-- keybind via DebugCompleteObjectivesInput/Service. Remove before shipping.
function StageManager.ForceCompleteAllStages()
	if currentStageIndex > #stageOrder then
		return -- already all complete
	end

	for _, stageName in ipairs(STAGE_NAMES) do
		completedCounts[stageName] = requiredCounts[stageName]
	end

	currentStageIndex = #stageOrder + 1
	print("StageManager: DEBUG - all stages force-completed.")
	StageManager.StageChanged:Fire(nil)
	broadcastUpdate()
end

function StageManager.ResetRound()
	stageOrder = shuffle(STAGE_NAMES)
	currentStageIndex = 1
	for _, stageName in ipairs(STAGE_NAMES) do
		completedCounts[stageName] = 0
	end
	print("Stage order this round: " .. table.concat(stageOrder, " -> "))
	StageManager.StageChanged:Fire(StageManager.GetCurrentStage())
	broadcastUpdate()
end

remoteFunction.OnServerInvoke = function(player)
	local stageName = StageManager.GetCurrentStage()
	if stageName then
		return stageName, completedCounts[stageName], requiredCounts[stageName]
	else
		return nil, 0, 0
	end
end

print("Stage order this match: " .. table.concat(stageOrder, " -> "))

task.defer(function()
	StageManager.StageChanged:Fire(StageManager.GetCurrentStage())
	broadcastUpdate()
end)

return StageManager