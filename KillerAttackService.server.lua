-- KillerAttackService.server.lua
-- Every attack is a lunge: holding click moves the killer forward
-- (steerable) until it either hits a target, the player releases,
-- or 0.7 seconds pass. Uses LinearVelocity so it plays nicely with
-- client-side movement prediction instead of snapping/rubberbanding.
--
-- Animation chain (per selected killer, e.g. "Scarecrow"):
--   <Killer>Lunge         -- loops while holding
--   <Killer>Swing         -- plays once the moment the lunge stops
--   <Killer>SuccessfulHit -- plays once after Swing, if it connected
--   <Killer>Miss          -- plays once after Swing, if it didn't

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationIds = require(ReplicatedStorage.Shared.AnimationIds)
local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)
local ActionAnimationService = require(ReplicatedStorage.Shared.ActionAnimationService)

local LUNGE_DURATION = 0.7
local LUNGE_SPEED = 28
local ATTACK_RANGE = 8
local ATTACK_ANGLE_DEGREES = 45
local ATTACK_COOLDOWN = 1.5

local dummyAnimTrack = nil

local remoteEvent = ReplicatedStorage:FindFirstChild("KillerAttackRequest")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "KillerAttackRequest"
	remoteEvent.Parent = ReplicatedStorage
end

print("KillerAttackService: script starting, remote is:", remoteEvent)

local activeAttacks = {} -- [killerPlayer] = { startTime = tick() }
local activeLungeForces = {} -- [killerPlayer] = LinearVelocity instance
local cooldowns = {} -- [killerPlayer] = tick() they can attack again

local KillerAppearanceService = require(script.Parent.KillerAppearanceService)
local KillerOverlayAnimationService = require(ReplicatedStorage.Shared.KillerOverlayAnimationService)

-- Builds an animation name like "ScarecrowLunge" based on the killer's
-- SelectedKiller attribute (e.g. "ScarecrowModel" -> "Scarecrow" + suffix)
local function getKillerAnimName(player, suffix)
	local selected = player:GetAttribute("SelectedKiller") or "ScarecrowModel"
	local baseName = selected:gsub("Model$", "")
	return baseName .. suffix
end

local function isInRangeAndAngle(killerPosition, killerLookVector, targetPosition)
	local offset = targetPosition - killerPosition
	local distance = offset.Magnitude
	if distance <= ATTACK_RANGE then
		local direction = offset.Unit
		local cosThreshold = math.cos(math.rad(ATTACK_ANGLE_DEGREES))
		local dot = killerLookVector:Dot(direction)
		return dot >= cosThreshold
	end
	return false
end

local function findTarget(killerPlayer)
	local killerCharacter = killerPlayer.Character
	if not killerCharacter then
		return nil
	end
	local killerRoot = killerCharacter:FindFirstChild("HumanoidRootPart")
	if not killerRoot then
		return nil
	end

	local killerPosition = killerRoot.Position
	local killerLookVector = killerRoot.CFrame.LookVector

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= killerPlayer and not otherPlayer:GetAttribute("IsKiller") then
			local state = PlayerStateService.GetState(otherPlayer)
			if state == PlayerStateService.States.Healthy or state == PlayerStateService.States.Injured then
				local otherCharacter = otherPlayer.Character
				if otherCharacter then
					local otherRoot = otherCharacter:FindFirstChild("HumanoidRootPart")
					if otherRoot and isInRangeAndAngle(killerPosition, killerLookVector, otherRoot.Position) then
						return { isPlayer = true, player = otherPlayer }
					end
				end
			end
		end
	end

	local dummy = Workspace:FindFirstChild("TestDummy")
	if dummy then
		local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")
		if dummyRoot and isInRangeAndAngle(killerPosition, killerLookVector, dummyRoot.Position) then
			return { isPlayer = false, dummy = dummy }
		end
	end

	return nil
end

local function playDummyAnimation(dummy, animName)
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animId = AnimationIds[animName]
	if not animId or animId == "" or animId:find("PUT_ID_HERE") then
		return
	end

	if dummyAnimTrack then
		dummyAnimTrack:Stop(0.1)
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animId

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success then
		track.Looped = true
		track:Play(0.1)
		dummyAnimTrack = track
	else
		warn("Failed to load dummy animation: " .. animName)
	end
end

local testDummy = Workspace:FindFirstChild("TestDummy")
if testDummy then
	testDummy:GetAttributeChangedSignal("HealthState"):Connect(function()
		local state = testDummy:GetAttribute("HealthState")
		if state == "Injured" then
			playDummyAnimation(testDummy, "LimpIdle")
		elseif state == "Downed" then
			playDummyAnimation(testDummy, "CrawlIdle")
		elseif state == "Healthy" then
			playDummyAnimation(testDummy, "IdleAnim")
		end
	end)
end

local function registerHit(killerPlayer, target)
	if target.isPlayer then
		local targetPlayer = target.player
		local state = PlayerStateService.GetState(targetPlayer)

		if state == PlayerStateService.States.Healthy then
			PlayerStateService.SetState(targetPlayer, PlayerStateService.States.Injured)
		elseif state == PlayerStateService.States.Injured then
			PlayerStateService.SetState(targetPlayer, PlayerStateService.States.Downed)
		end

		print(killerPlayer.Name .. " hit " .. targetPlayer.Name .. "!")
	else
		local dummy = target.dummy
		local currentState = dummy:GetAttribute("HealthState") or "Healthy"

		if currentState == "Healthy" then
			currentState = "Injured"
			playDummyAnimation(dummy, "LimpIdle")
		elseif currentState == "Injured" then
			currentState = "Downed"
			playDummyAnimation(dummy, "CrawlIdle")
		end

		dummy:SetAttribute("HealthState", currentState)
		print(killerPlayer.Name .. " hit the TestDummy! Dummy is now: " .. currentState)

		for _, part in ipairs(dummy:GetDescendants()) do
			if part:IsA("BasePart") then
				local flashColor = Color3.fromRGB(255, 0, 0)
				if currentState == "Downed" then
					flashColor = Color3.fromRGB(80, 0, 0)
				end
				local originalColor = part.Color
				part.Color = flashColor
				task.delay(0.3, function()
					part.Color = originalColor
				end)
			end
		end
	end
end

local function startLungeMovement(killerPlayer)
	local character = killerPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local attachment = root:FindFirstChild("LungeAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "LungeAttachment"
		attachment.Parent = root
	end

	-- Flatten to the horizontal plane so vertical camera/root pitch can
	-- never leak into this velocity -- MaxForce is unlimited below, so
	-- even a small Y component would slam the killer's vertical speed
	-- to LUNGE_SPEED instantly, which is what was triggering the ragdoll.
	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flatLook.Magnitude > 0 then
		flatLook = flatLook.Unit
	end
 
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "LungeVelocity"
	linearVelocity.Attachment0 = attachment
	-- PerAxis + zero Y force means this constraint never touches vertical
	-- velocity at all -- gravity/falling works exactly like normal the
	-- whole time you're lunging. (MaxForce alone applies to all 3 axes
	-- at once, which is what was locking your Y velocity to 0.)
	linearVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	linearVelocity.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	linearVelocity.VectorVelocity = flatLook * LUNGE_SPEED
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = root

	activeLungeForces[killerPlayer] = linearVelocity
end

local function updateLungeDirection(killerPlayer)
	local linearVelocity = activeLungeForces[killerPlayer]
	if not linearVelocity or not linearVelocity.Parent then
		return
	end

	local character = killerPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if flatLook.Magnitude > 0 then
			flatLook = flatLook.Unit
		end
		linearVelocity.VectorVelocity = flatLook * LUNGE_SPEED
	end
end

local function stopLungeMovement(killerPlayer)
	local linearVelocity = activeLungeForces[killerPlayer]
	if linearVelocity then
		linearVelocity:Destroy()
		activeLungeForces[killerPlayer] = nil
	end

	-- Kill any leftover momentum from the lunge so Swing starts at
	-- a clean stop instead of drifting forward
	local character = killerPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
	end
end

-- Called the moment the lunge stops, for ANY reason (hit, release, timeout).
-- Plays Swing, then SuccessfulHit or Miss depending on whether it connected.
local function endAttack(killerPlayer, wasHit)
	stopLungeMovement(killerPlayer)
	activeAttacks[killerPlayer] = nil

	killerPlayer:SetAttribute("IsSwinging", true)

	local overlay = KillerAppearanceService.GetOverlay(killerPlayer)
	local swingAnim = getKillerAnimName(killerPlayer, "Swing")
	local outcomeAnim = getKillerAnimName(killerPlayer, wasHit and "SuccessfulHit" or "Miss")

	KillerOverlayAnimationService.PlayOnce(overlay, swingAnim, function()
		killerPlayer:SetAttribute("IsSwinging", false)
		cooldowns[killerPlayer] = tick() + ATTACK_COOLDOWN
		killerPlayer:SetAttribute("IsRecoveringFromAttack", true)

		KillerOverlayAnimationService.PlayOnce(overlay, outcomeAnim, function()
			killerPlayer:SetAttribute("IsRecoveringFromAttack", false)
		end)
	end)
end

remoteEvent.OnServerEvent:Connect(function(player, action, holdDuration)
	print("KillerAttackService received:", action, "from", player.Name, "IsKiller:", player:GetAttribute("IsKiller"), "IsCarrying:", player:GetAttribute("IsCarrying"), "IsStunned:", player:GetAttribute("IsStunned"))

	if not player:GetAttribute("IsKiller") then
		return
	end
	if player:GetAttribute("IsCarrying") then
		return
	end
	if player:GetAttribute("IsStunned") then
		return
	end

	local cooldownEnd = cooldowns[player]
	if cooldownEnd and tick() < cooldownEnd then
		return
	end

	if action == "start" then
		if activeAttacks[player] then
			return
		end

		activeAttacks[player] = { startTime = tick() }
		startLungeMovement(player)

		local overlay = KillerAppearanceService.GetOverlay(player)
		KillerOverlayAnimationService.Play(overlay, getKillerAnimName(player, "Lunge"))
	elseif action == "end" then
		if not activeAttacks[player] then
			return
		end
		endAttack(player, false)
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	for killerPlayer, attackData in pairs(activeAttacks) do
		local elapsed = tick() - attackData.startTime

		updateLungeDirection(killerPlayer)

		local target = findTarget(killerPlayer)
		if target then
			registerHit(killerPlayer, target)
			endAttack(killerPlayer, true)
		elseif elapsed >= LUNGE_DURATION then
			print(killerPlayer.Name .. " swung and missed")
			endAttack(killerPlayer, false)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeAttacks[player] = nil
	cooldowns[player] = nil
	stopLungeMovement(player)
end)

print("KillerAttackService loaded successfully.")