-- ActionAnimationService.lua
-- Shared helper for playing/stopping "Action" priority animations
-- (things layered on top of movement, like repairing/healing).
-- Works for both real Players and non-Player targets (e.g. TestDummy).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationIds = require(ReplicatedStorage.Shared.AnimationIds)

local ActionAnimationService = {}

local activeTracks = {} -- [target] = currently playing track

local function getCharacterModel(target)
	if target:IsA("Player") then
		return target.Character
	else
		return target -- already a character-like Model (e.g. TestDummy)
	end
end

function ActionAnimationService.Play(target, animName)
	local character = getCharacterModel(target)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
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

	ActionAnimationService.Stop(target)

	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if success then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.15)
		activeTracks[target] = track
	else
		warn("Failed to load action animation: " .. animName)
	end
end

function ActionAnimationService.PlayOnce(target, animName, onFinished)
	local character = getCharacterModel(target)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		if onFinished then onFinished() end
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animId = AnimationIds[animName]
	if not animId or animId == "" or animId:find("PUT_ID_HERE") then
		if onFinished then onFinished() end
		return
	end

	ActionAnimationService.Stop(target)

	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if success then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		activeTracks[target] = track
		track:Play(0.1)
		track.Stopped:Connect(function()
			if activeTracks[target] == track then
				activeTracks[target] = nil
			end
			if onFinished then
				onFinished()
			end
		end)
	else
		warn("Failed to load action animation: " .. animName)
		if onFinished then onFinished() end
	end
end

function ActionAnimationService.Stop(target)
	local track = activeTracks[target]
	if track then
		track:Stop(0.15)
		activeTracks[target] = nil
	end
end

return ActionAnimationService