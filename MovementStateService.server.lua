-- MovementStateService.server.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)


local RUN_WALKSPEED = 16
local WALK_WALKSPEED = RUN_WALKSPEED * 0.5    -- 8
local CROUCH_WALKSPEED = RUN_WALKSPEED * 0.3  -- temp test, same as run speed
local CRAWL_WALKSPEED = RUN_WALKSPEED * 0.15  -- 2.4
local ATTACK_RECOVERY_WALKSPEED = RUN_WALKSPEED * 0.4 -- moving slowly during post-attack recovery

-- Per-killer base speed, keyed by the exact SelectedKiller attribute value.
local KILLER_BASE_SPEEDS = {
	ScarecrowModel = RUN_WALKSPEED * 1.15,  -- 18.4
	TheMarkMakerModel = 17.5,
}
local DEFAULT_KILLER_WALKSPEED = RUN_WALKSPEED * 1.15 -- fallback if SelectedKiller is unrecognized

local walkRemote = ReplicatedStorage:FindFirstChild("WalkToggle")
if not walkRemote then
	walkRemote = Instance.new("RemoteEvent")
	walkRemote.Name = "WalkToggle"
	walkRemote.Parent = ReplicatedStorage
end

local crouchRemote = ReplicatedStorage:FindFirstChild("CrouchToggle")
if not crouchRemote then
	crouchRemote = Instance.new("RemoteEvent")
	crouchRemote.Name = "CrouchToggle"
	crouchRemote.Parent = ReplicatedStorage
end

local function applySpeed(player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if player:GetAttribute("IsStunned") then
		humanoid.WalkSpeed = 0
		return
	end

	if player:GetAttribute("IsCastingAbility") then
		humanoid.WalkSpeed = 0
		return
	end

	if player:GetAttribute("IsRecoveringFromAttack") then
		humanoid.WalkSpeed = ATTACK_RECOVERY_WALKSPEED
		return
	end

	if player:GetAttribute("IsKiller") then
		local selectedKiller = player:GetAttribute("SelectedKiller") or "ScarecrowModel"
		local speed = KILLER_BASE_SPEEDS[selectedKiller] or DEFAULT_KILLER_WALKSPEED

		-- Scarecrow: passive speed stacks (+5% per stack, up to 3)
		local scarecrowStacks = player:GetAttribute("ScarecrowSpeedStacks") or 0
		speed = speed * (1 + 0.05 * scarecrowStacks)

		-- Mark Maker: -20% while aiming, -50% while a Mark is active
		if player:GetAttribute("IsHoldingMarkAbility") then
			speed = speed * 0.8
		end
		if player:GetAttribute("IsSummoningMark") then
			speed = speed * 0.2
		end

		-- Mark Maker: Perfect Aim's +10% speed window
		if player:GetAttribute("PerfectAimActive") then
			speed = speed * 1.1
		end

		humanoid.WalkSpeed = speed
	elseif PlayerStateService.GetState(player) == PlayerStateService.States.Downed then
		humanoid.WalkSpeed = CRAWL_WALKSPEED
	else
		local speed
		if player:GetAttribute("IsCrouching") then
			speed = CROUCH_WALKSPEED
		elseif player:GetAttribute("IsWalking") then
			speed = WALK_WALKSPEED
		else
			speed = RUN_WALKSPEED
		end

		-- Any Survivor who was just Injured gets a 3s 50% speed boost
		-- (see InjuryHasteService.server.lua), regardless of which
		-- killer/ability caused the injury.
		if player:GetAttribute("IsHasted") then
			speed = speed * 1.5
		end

		humanoid.WalkSpeed = speed
	end
end

local function onPlayerAdded(player)
	player:SetAttribute("IsWalking", false)
	player:SetAttribute("IsCrouching", false)

	player:GetAttributeChangedSignal("HealthState"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsKiller"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsWalking"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsStunned"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsCrouching"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsRecoveringFromAttack"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsSwinging"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsCastingAbility"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("ScarecrowSpeedStacks"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("SelectedKiller"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsHoldingMarkAbility"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsSummoningMark"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("PerfectAimActive"):Connect(function()
		applySpeed(player)
	end)
	player:GetAttributeChangedSignal("IsHasted"):Connect(function()
		applySpeed(player)
	end)
	player.CharacterAdded:Connect(function()
		player:SetAttribute("IsCrouching", false)
		task.wait(0.5)
		applySpeed(player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

walkRemote.OnServerEvent:Connect(function(player, isWalking)
	if player:GetAttribute("IsKiller") then
		return
	end
	if PlayerStateService.GetState(player) == PlayerStateService.States.Downed then
		return
	end
	player:SetAttribute("IsWalking", isWalking)
end)

crouchRemote.OnServerEvent:Connect(function(player, isCrouching)
	if player:GetAttribute("IsKiller") then
		return
	end
	if PlayerStateService.GetState(player) == PlayerStateService.States.Downed then
		return
	end
	player:SetAttribute("IsCrouching", isCrouching)
end)

-- TEMP DEBUG: watch WalkSpeed and MoveDirection live
game:GetService("RunService").Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local moveDir = humanoid.MoveDirection
			if moveDir.Magnitude > 0 or player:GetAttribute("IsCrouching") then
			end
		end
	end
end)