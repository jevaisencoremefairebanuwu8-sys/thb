-- VaultService.server.lua
-- Two-phase vault:
--   1. APPROACH: on E, if the player is within VAULT_DETECT_RANGE (10
--      studs) of the nearer of a vault's StartPoint/EndPoint, a scripted
--      CFrame lerp moves them to that exact point.
--   2. CROSS: once they arrive, the same technique slides them across
--      to the far point over vaultTime seconds (collision disabled on
--      the vault for the duration), playing FastVault. Killers always
--      get SlowVault instead (intentional -- survivors get pallet/
--      window mobility, killers don't).
--
-- Both phases use a direct CFrame lerp rather than Humanoid:MoveTo().
-- MoveTo() was tried first, but a server-issued MoveTo gets fought and
-- overridden by the player's own live movement input (they still have
-- authority over their own character) -- it only worked if the player
-- was standing completely still when pressing E. A direct CFrame lerp
-- fully overrides position every frame regardless of input, so it works
-- the same whether the player was moving or not. Trade-off: the
-- approach phase looks like a smooth glide rather than a true run
-- animation, since WalkSpeed is locked to 0 for the whole sequence.
--
-- Previously (before the two-phase redesign) this lerped straight from
-- wherever the player happened to be standing when they pressed E
-- directly to the far point, which caused a diagonal "warping" look.
-- Running to the exact near point first fixes that.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionAnimationService = require(ReplicatedStorage.Shared.ActionAnimationService)

print("VaultService: all requires loaded successfully")

local SURVIVOR_VAULT_TIME = 0.75
local KILLER_VAULT_TIME = 1
local VAULT_DETECT_RANGE = 10 -- distance to the NEARER of StartPoint/EndPoint
local APPROACH_SPEED = 17.2 -- studs/sec, used to time the approach lerp -- matches survivor run speed

local mapModel = Workspace:WaitForChild("Map")
local vaultsFolder = mapModel:WaitForChild("Vaults")
local palletsFolder = Workspace:WaitForChild("Pallets")

local interactRemote = ReplicatedStorage:FindFirstChild("VaultInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "VaultInteract"
	interactRemote.Parent = ReplicatedStorage
end

local vaultingPlayers = {} -- [player] = true, prevents double-vaulting mid-action

local VAULT_FACING_CONE_DEGREES = 120 -- total cone width; must be within +/- half of this from straight ahead
local VAULT_FACING_DOT_THRESHOLD = math.cos(math.rad(VAULT_FACING_CONE_DEGREES / 2))

local function isValidVaultTarget(vaultModel)
	return vaultModel:IsDescendantOf(vaultsFolder) or vaultModel:IsDescendantOf(palletsFolder)
end

-- True if targetPosition is roughly in front of root (within the front
-- 180-degree hemisphere of where it's facing), false if it's behind --
-- prevents vaulting something you're facing away from.
local function isFacingToward(root, targetPosition)
	local direction = targetPosition - root.Position
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude < 0.01 then
		return true -- practically on top of it, nothing meaningful to check
	end
	flatDirection = flatDirection.Unit

	local lookVector = root.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.01 then
		return true
	end
	flatLook = flatLook.Unit

	return flatLook:Dot(flatDirection) >= VAULT_FACING_DOT_THRESHOLD
end

-- Lerps `character`'s HumanoidRootPart from wherever it currently is to
-- targetPosition over `duration` seconds, then calls onComplete. Fully
-- overrides CFrame every frame -- doesn't rely on WalkSpeed/MoveTo, so
-- it can't be fought by the player's own live input.
local function lerpRootTo(character, targetPosition, duration, onComplete)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		if onComplete then
			onComplete()
		end
		return
	end

	local startPosition = root.Position

	-- Face the direction of travel, not whatever direction the
	-- character happened to be looking before the vault started. It's
	-- a straight-line lerp, so the direction is constant -- compute it
	-- once rather than every frame.
	local travelDirection = targetPosition - startPosition
	local flatDirection = Vector3.new(travelDirection.X, 0, travelDirection.Z)
	if flatDirection.Magnitude > 0.01 then
		flatDirection = flatDirection.Unit
	else
		flatDirection = root.CFrame.LookVector -- no horizontal movement, keep current facing
	end

	local startTime = tick()
	local startLookVector = root.CFrame.LookVector
	local ROTATION_TIME = math.min(duration * 0.5, 0.25) -- quick turn, not a full-duration one
	local connection

	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / duration, 1)
		local rotationAlpha = math.min(elapsed / ROTATION_TIME, 1)

		local currentRoot = character:FindFirstChild("HumanoidRootPart")
		if currentRoot and currentRoot.Parent then
			local currentPos = startPosition:Lerp(targetPosition, alpha)

			local currentLook = startLookVector:Lerp(flatDirection, rotationAlpha)
			if currentLook.Magnitude > 0.01 then
				currentLook = currentLook.Unit
			else
				currentLook = flatDirection
			end

			currentRoot.CFrame = CFrame.new(currentPos, currentPos + currentLook)
		end

		if alpha >= 1 then
			connection:Disconnect()
			if onComplete then
				onComplete()
			end
		end
	end)
end

interactRemote.OnServerEvent:Connect(function(player, vaultModel)
	if not vaultModel or not isValidVaultTarget(vaultModel) then
		return
	end
	if vaultingPlayers[player] then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	local startPoint = vaultModel:FindFirstChild("StartPoint", true)
	local endPoint = vaultModel:FindFirstChild("EndPoint", true)
	if not startPoint or not endPoint then
		warn(vaultModel.Name .. " is missing StartPoint/EndPoint attachments")
		return
	end

	local distToStart = (root.Position - startPoint.WorldPosition).Magnitude
	local distToEnd = (root.Position - endPoint.WorldPosition).Magnitude

	-- The nearer point is where they approach TO; the farther one is
	-- where they land after crossing.
	local nearPoint = (distToStart <= distToEnd) and startPoint or endPoint
	local farPoint = (distToStart <= distToEnd) and endPoint or startPoint
	local distToNear = math.min(distToStart, distToEnd)

	if distToNear > VAULT_DETECT_RANGE then
		return
	end
	if not isFacingToward(root, nearPoint.WorldPosition) then
		return
	end

	vaultingPlayers[player] = true

	-- Take network ownership of the root part for the WHOLE sequence.
	-- Without this, the player's client keeps predicting/simulating its
	-- own physics, and when the server's CFrame writes suddenly assert
	-- authority, the client has to snap-correct to the server's (lagged)
	-- view of where the player was -- that's the "teleports me backward"
	-- glitch. Taking ownership makes the server fully authoritative, so
	-- there's nothing left to reconcile against.
	local ok = pcall(function()
		root:SetNetworkOwner(nil)
	end)
	if not ok then
		vaultingPlayers[player] = nil
		return
	end

	local function restoreNetworkOwnership(char)
		local currentRoot = char and char:FindFirstChild("HumanoidRootPart")
		if currentRoot and currentRoot.Parent then
			pcall(function()
				currentRoot:SetNetworkOwnershipAuto()
			end)
		end
	end

	-- Lock WalkSpeed for the WHOLE sequence (both phases) so the
	-- player's own input can never fight either lerp.
	local originalWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0

	local approachDuration = math.max(distToNear / APPROACH_SPEED, 0.05)

	local function crossPhase()
		-- Re-validate everything is still around after the approach --
		-- the player could have disconnected, died, or gotten downed.
		local currentCharacter = player.Character
		local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
		local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
		if not currentRoot or not currentHumanoid or not vaultModel.Parent then
			restoreNetworkOwnership(currentCharacter)
			vaultingPlayers[player] = nil
			return
		end

		local isKiller = player:GetAttribute("IsKiller")
		local vaultTime, animName
		if isKiller then
			vaultTime = KILLER_VAULT_TIME
			animName = "SlowVault"
		else
			vaultTime = SURVIVOR_VAULT_TIME
			animName = "FastVault"
		end

		ActionAnimationService.PlayOnce(player, animName, function() end)

		-- Disable collision on the vault itself for the duration of the
		-- crossing, so the player doesn't bump into it.
		local vaultOriginalCanCollide = {}
		for _, part in ipairs(vaultModel:GetDescendants()) do
			if part:IsA("BasePart") then
				vaultOriginalCanCollide[part] = part.CanCollide
				part.CanCollide = false
			end
		end

		lerpRootTo(currentCharacter, farPoint.WorldPosition, vaultTime, function()
			local finalHumanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
			if finalHumanoid and finalHumanoid.Parent then
				finalHumanoid.WalkSpeed = originalWalkSpeed
			end

			for part, wasCollidable in pairs(vaultOriginalCanCollide) do
				if part and part.Parent then
					part.CanCollide = wasCollidable
				end
			end

			restoreNetworkOwnership(currentCharacter)
			vaultingPlayers[player] = nil
		end)
	end

	-- PHASE 1: approach the near point, then PHASE 2: cross
	lerpRootTo(character, nearPoint.WorldPosition, approachDuration, crossPhase)
end)

Players.PlayerRemoving:Connect(function(player)
	vaultingPlayers[player] = nil
end)

print("VaultService loaded. Tracking " .. #vaultsFolder:GetChildren() .. " vault(s).")