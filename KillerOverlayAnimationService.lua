-- KillerOverlayAnimationService.lua
-- Plays animations on a killer's overlay model (its own AnimationController),
-- not the player's Humanoid, since the overlay is a separate custom rig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationIds = require(ReplicatedStorage.Shared.AnimationIds)

print("=== AnimationIds contents as loaded by the server ===")
for key, value in pairs(AnimationIds) do
	print("  [" .. key .. "] =", value)
end
print("=== End AnimationIds dump ===")

local KillerOverlayAnimationService = {}

local activeTracks = {} -- [overlayModel] = currently playing track

function KillerOverlayAnimationService.Play(overlayModel, animName)
	print("KillerOverlayAnimationService.Play called with overlayModel:", overlayModel, "animName:", animName)
	if not overlayModel then
		print("  No overlayModel provided")
		return
	end
	local controller = overlayModel:FindFirstChildOfClass("AnimationController")
	print("  controller:", controller)
	if not controller then
		return
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	print("  animator:", animator)

	local animId = AnimationIds[animName]
	print("  animId:", animId)
	if not animId or animId == "" or animId:find("PUT_ID_HERE") then
		print("  Invalid animId, skipping")
		return
	end

	KillerOverlayAnimationService.Stop(overlayModel)

	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if success then
		track.Looped = true
		track:Play(0.15)
		activeTracks[overlayModel] = track
		print("  Playing successfully")
	else
		warn("Failed to load overlay animation: " .. animName .. " - " .. tostring(track))
	end
end

function KillerOverlayAnimationService.PlayOnce(overlayModel, animName, onFinished)
	if not overlayModel then
		if onFinished then onFinished() end
		return
	end
	local controller = overlayModel:FindFirstChildOfClass("AnimationController")
	if not controller then
		if onFinished then onFinished() end
		return
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	local animId = AnimationIds[animName]
	if not animId or animId == "" or animId:find("PUT_ID_HERE") then
		if onFinished then onFinished() end
		return
	end

	KillerOverlayAnimationService.Stop(overlayModel)

	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if success then
		track.Looped = false
		activeTracks[overlayModel] = track
		track:Play(0.1)
		track.Stopped:Connect(function()
			if activeTracks[overlayModel] == track then
				activeTracks[overlayModel] = nil
			end
			if onFinished then
				onFinished()
			end
		end)
	else
		warn("Failed to load overlay animation: " .. animName)
		if onFinished then onFinished() end
	end
end

function KillerOverlayAnimationService.Stop(overlayModel)
	local track = activeTracks[overlayModel]
	if track then
		track:Stop(0.15)
		activeTracks[overlayModel] = nil
	end
end

return KillerOverlayAnimationService