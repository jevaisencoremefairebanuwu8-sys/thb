-- GateService.lua (ModuleScript)
-- Slides the tunnel gates open (10 studs left/right) over ~5 seconds
-- when the round starts, and closes them again after 2 minutes.
-- Also opens permanently (no auto-close) once all objectives are done,
-- via GateService.OpenGatesForEscape().

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local GATE_OPEN_DISTANCE = 10
local GATE_MOVE_TIME = 5
local GATE_STAY_OPEN_TIME = 10

local lobbyFolder = Workspace:WaitForChild("Lobby")

local leftGates = { lobbyFolder:WaitForChild("LeftGate1"), lobbyFolder:WaitForChild("LeftGate2") }
local rightGates = { lobbyFolder:WaitForChild("RightGate1"), lobbyFolder:WaitForChild("RightGate2") }

-- Store each gate's true closed position ONCE at load time. All movement
-- below always targets (home + offset), never "current position + offset" --
-- this makes Open/Close/OpenForEscape safe to call in any order or
-- combination without the gates drifting or double-offsetting.
local gateHomes = {}
for _, gate in ipairs(leftGates) do
	gateHomes[gate] = gate:GetPivot()
end
for _, gate in ipairs(rightGates) do
	gateHomes[gate] = gate:GetPivot()
end

local GateService = {}
local escapeModeActive = false

local function moveGateModel(gateModel, offset, duration)
	local homeCFrame = gateHomes[gateModel]
	local targetCFrame = homeCFrame + offset
	local startCFrame = gateModel:GetPivot()

	local startTime = tick()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / duration, 1)
		gateModel:PivotTo(startCFrame:Lerp(targetCFrame, alpha))
		if alpha >= 1 then
			connection:Disconnect()
		end
	end)
end

local function openAllGates()
	for _, gate in ipairs(leftGates) do
		moveGateModel(gate, Vector3.new(GATE_OPEN_DISTANCE, 0, 0), GATE_MOVE_TIME)
	end
	for _, gate in ipairs(rightGates) do
		moveGateModel(gate, Vector3.new(-GATE_OPEN_DISTANCE, 0, 0), GATE_MOVE_TIME)
	end
end

function GateService.OpenGates()
	openAllGates()
	print("Gates opening")

	task.delay(GATE_STAY_OPEN_TIME, function()
		if escapeModeActive then
			-- All objectives finished while the entrance-open window was
			-- still running -- leave the gates open for escape instead
			-- of auto-closing on top of that.
			return
		end
		GateService.CloseGates()
	end)
end

-- Called when StageManager reports every objective is complete. Opens the
-- gates (safe even if they're already open from GateService.OpenGates())
-- and does NOT schedule an auto-close -- they stay open for the rest of
-- the round.
function GateService.OpenGatesForEscape()
	if escapeModeActive then
		return
	end
	escapeModeActive = true
	openAllGates()
	print("Escape gates opening -- all objectives complete!")
end

function GateService.CloseGates()
	escapeModeActive = false
	for _, gate in ipairs(leftGates) do
		moveGateModel(gate, Vector3.new(0, 0, 0), GATE_MOVE_TIME)
	end
	for _, gate in ipairs(rightGates) do
		moveGateModel(gate, Vector3.new(0, 0, 0), GATE_MOVE_TIME)
	end
	print("Gates closing")
end

-- Instantly snaps gates back to their closed home position with no tween,
-- and clears escape mode. Call at the very start of a new round so a
-- round that ended with the escape gates left open (nobody made it out
-- before the match timer expired) doesn't leak into the next round.
function GateService.ResetForNewRound()
	escapeModeActive = false
	for gateModel, homeCFrame in pairs(gateHomes) do
		gateModel:PivotTo(homeCFrame)
	end
end

return GateService