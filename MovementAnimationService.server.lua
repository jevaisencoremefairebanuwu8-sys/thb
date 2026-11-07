-- MovementAnimationService.server.lua
-- Picks and plays the right movement animation based on health state,
-- crouch/walk toggles, and whether the character is actually moving.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)
local AnimationIds = require(ReplicatedStorage.Shared.AnimationIds)

-- loadedTracks[player] = { [animName] = AnimationTrack }
local loadedTracks = {}
local currentAnimName = {}

local function loadAnimations(player, humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local tracks = {}
	local movementAnimNames = {
		"IdleAnim", "WalkAnim", "RunAnim",
		"CrouchIdle", "CrouchWalk",
		"LimpIdle", "LimpWalk", "LimpRun",
		"CrawlIdle", "CrawlWalk",
	}

	for _, animName in ipairs(movementAnimNames) do
		local animId = AnimationIds[animName]

		if animId and animId ~= "" and not animId:find("PUT_ID_HERE") then
			local animation = Instance.new("Animation")
			animation.AnimationId = animId
			local success, result = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if success then
				result.Looped = true
				result.Priority = Enum.AnimationPriority.Movement
				tracks[animName] = result
			else
				warn("FAILED to load " .. animName .. ": " .. tostring(result))
			end
		end
	end

	loadedTracks[player] = tracks
	currentAnimName[player] = nil
end

-- Decides which animation key should be playing right now
local function determineAnimName(player, humanoid)
	local state = PlayerStateService.GetState(player)
	local isMoving = humanoid.MoveDirection.Magnitude > 0.05
	local isCrouching = player:GetAttribute("IsCrouching")

	if state == PlayerStateService.States.Downed then
		return isMoving and "CrawlWalk" or "CrawlIdle"
	elseif isCrouching then
		return isMoving and "CrouchWalk" or "CrouchIdle"
	elseif state == PlayerStateService.States.Injured then
		if not isMoving then
			return "LimpIdle"
		elseif player:GetAttribute("IsWalking") then
			return "LimpWalk"
		else
			return "LimpRun"
		end
	else
		if not isMoving then
			return "IdleAnim"
		elseif player:GetAttribute("IsWalking") then
			return "WalkAnim"
		else
			return "RunAnim"
		end
	end
end

local function updateAnimation(player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local tracks = loadedTracks[player]
	if not tracks then
		return
	end

	local desiredAnim = determineAnimName(player, humanoid)

	if desiredAnim == currentAnimName[player] then
		return -- already playing this one, don't restart it
	end

	-- Play the new one FIRST, then stop the old one - smoother crossfade
	local newTrack = tracks[desiredAnim]
	if newTrack then
		newTrack:Play(0.15)
	end

	local previousAnim = currentAnimName[player]
	if previousAnim and tracks[previousAnim] then
		tracks[previousAnim]:Stop(0.15)
	end

	currentAnimName[player] = desiredAnim
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")

	-- Disable Roblox's default Animate script so it doesn't fight with our custom animations
	local defaultAnimateScript = character:FindFirstChild("Animate")
	if defaultAnimateScript then
		defaultAnimateScript.Disabled = true
	end

	loadAnimations(player, humanoid)
end

local function onPlayerAdded(player)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	loadedTracks[player] = nil
	currentAnimName[player] = nil
end)

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		updateAnimation(player)
	end
end)