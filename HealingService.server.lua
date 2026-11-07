-- HealingService.server.lua
-- Handles both self-healing (must be crouched) and teammate-healing
-- for Injured survivors (or the TestDummy). Uses a custom E-hold system
-- (HealInteract remote) instead of ProximityPrompt.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)
local ProgressBarService = require(ReplicatedStorage.Shared.ProgressBarService)
local ActionAnimationService = require(ReplicatedStorage.Shared.ActionAnimationService)

local HEAL_RATE_PER_SECOND = 10
local SELF_HEAL_MULTIPLIER = 0.8
local MAX_HEAL_DISTANCE = 8

local activeHeals = {} -- [target] = { healers = {}, selfHealing = false }
local healerActiveTarget = {}

local selfHealRemote = ReplicatedStorage:FindFirstChild("SelfHealToggle")
if not selfHealRemote then
	selfHealRemote = Instance.new("RemoteEvent")
	selfHealRemote.Name = "SelfHealToggle"
	selfHealRemote.Parent = ReplicatedStorage
end

local cancelRemote = ReplicatedStorage:FindFirstChild("CancelTimedAction")
if not cancelRemote then
	cancelRemote = Instance.new("RemoteEvent")
	cancelRemote.Name = "CancelTimedAction"
	cancelRemote.Parent = ReplicatedStorage
end

local healInteractRemote = ReplicatedStorage:FindFirstChild("HealInteract")
if not healInteractRemote then
	healInteractRemote = Instance.new("RemoteEvent")
	healInteractRemote.Name = "HealInteract"
	healInteractRemote.Parent = ReplicatedStorage
end

local function getRootPart(target)
	if target:IsA("Player") then
		local character = target.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	else
		return target:FindFirstChild("HumanoidRootPart")
	end
end

local function getHealthState(target)
	if target:IsA("Player") then
		return PlayerStateService.GetState(target)
	else
		return target:GetAttribute("HealthState") or "Healthy"
	end
end

local function updateTargetAnimation(target)
	local data = activeHeals[target]
	if not data then
		ActionAnimationService.Stop(target)
		return
	end
	if data.selfHealing then
		ActionAnimationService.Play(target, "SelfHealing")
		return
	end
	local healerCount = 0
	for _ in pairs(data.healers) do
		healerCount += 1
	end
	if healerCount > 0 then
		ActionAnimationService.Play(target, "BeingHealed")
	else
		ActionAnimationService.Stop(target)
	end
end

local function ensureHealEntry(target)
	if not activeHeals[target] then
		activeHeals[target] = { healers = {}, selfHealing = false }
		target:SetAttribute("HealProgress", 0)
	end
	return activeHeals[target]
end

local function stopHealerHealing(healerPlayer)
	local target = healerActiveTarget[healerPlayer]
	if not target then
		return
	end
	local data = activeHeals[target]
	if data then
		data.healers[healerPlayer] = nil
	end
	ProgressBarService.Hide(healerPlayer)
	ActionAnimationService.Stop(healerPlayer)
	healerActiveTarget[healerPlayer] = nil
	updateTargetAnimation(target)
end

healInteractRemote.OnServerEvent:Connect(function(healerPlayer, target, action)
	if not target then
		return
	end
	if getHealthState(target) ~= PlayerStateService.States.Injured then
		return
	end

	if action == "start" then
		if healerActiveTarget[healerPlayer] then
			return
		end

		local healerCharacter = healerPlayer.Character
		local targetRoot = getRootPart(target)
		if not healerCharacter or not targetRoot then
			return
		end
		local healerRoot = healerCharacter:FindFirstChild("HumanoidRootPart")
		if not healerRoot then
			return
		end
		if (healerRoot.Position - targetRoot.Position).Magnitude > MAX_HEAL_DISTANCE then
			return
		end

		local lookAtPosition = Vector3.new(targetRoot.Position.X, healerRoot.Position.Y, targetRoot.Position.Z)
		healerCharacter:PivotTo(CFrame.new(healerRoot.Position, lookAtPosition))

		local data = ensureHealEntry(target)
		data.healers[healerPlayer] = true
		healerActiveTarget[healerPlayer] = target

		ActionAnimationService.Play(healerPlayer, "Healer")
		updateTargetAnimation(target)
	elseif action == "stop" then
		stopHealerHealing(healerPlayer)
	end
end)

local function onPlayerAdded(player)
	player:GetAttributeChangedSignal("IsCrouching"):Connect(function()
		if not player:GetAttribute("IsCrouching") then
			local data = activeHeals[player]
			if data and data.selfHealing then
				data.selfHealing = false
				ProgressBarService.Hide(player)
				updateTargetAnimation(player)
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		local data = activeHeals[player]
		if data then
			data.healers = {}
			data.selfHealing = false
		end
		if healerActiveTarget[player] then
			stopHealerHealing(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	activeHeals[player] = nil
	if healerActiveTarget[player] then
		stopHealerHealing(player)
	end
	healerActiveTarget[player] = nil
end)

selfHealRemote.OnServerEvent:Connect(function(player, action)
	if getHealthState(player) ~= PlayerStateService.States.Injured then
		return
	end
	if action == "start" then
		if not player:GetAttribute("IsCrouching") then
			return
		end
		local data = ensureHealEntry(player)
		data.selfHealing = true
		updateTargetAnimation(player)
	elseif action == "stop" then
		local data = activeHeals[player]
		if data then
			data.selfHealing = false
		end
		ProgressBarService.Hide(player)
		updateTargetAnimation(player)
	end
end)

cancelRemote.OnServerEvent:Connect(function(player)
	local data = activeHeals[player]
	if data and data.selfHealing then
		data.selfHealing = false
		ProgressBarService.Hide(player)
		updateTargetAnimation(player)
	end
	if healerActiveTarget[player] then
		stopHealerHealing(player)
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	for target, data in pairs(activeHeals) do
		local progress = target:GetAttribute("HealProgress") or 0

		local otherHealerCount = 0
		for _ in pairs(data.healers) do
			otherHealerCount += 1
		end

		local rate = 0
		if data.selfHealing then
			rate += HEAL_RATE_PER_SECOND * SELF_HEAL_MULTIPLIER
		end
		rate += otherHealerCount * HEAL_RATE_PER_SECOND

		if rate > 0 then
			progress = math.min(100, progress + rate * deltaTime)
			target:SetAttribute("HealProgress", progress)

			if data.selfHealing then
				ProgressBarService.Update(target, "Healing", progress)
			end
			for healer in pairs(data.healers) do
				ProgressBarService.Update(healer, "Healing", progress)
			end

			if progress >= 100 then
				for healer in pairs(data.healers) do
					ProgressBarService.Hide(healer)
					ActionAnimationService.Stop(healer)
					healerActiveTarget[healer] = nil
				end
				ProgressBarService.Hide(target)
				ActionAnimationService.Stop(target)
				activeHeals[target] = nil

				if target:IsA("Player") then
					PlayerStateService.SetState(target, PlayerStateService.States.Healthy)
				else
					target:SetAttribute("HealthState", "Healthy")
				end
			end
		end
	end
end)