-- ScarecrowFearEffectsClient.client.lua
-- Handles the client-facing Fear token effects fired by ScarecrowPowerService
-- at the specific Survivor who crossed a threshold:
--   9 tokens  -> vision shrinks (local fog)
--   12 tokens -> scream sound plays

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local localPlayer = Players.LocalPlayer

local fearEffectRemote = ReplicatedStorage:WaitForChild("ScarecrowFearEffect")

local originalFogEnd = Lighting.FogEnd
local originalFogStart = Lighting.FogStart

local function setReducedVision(enabled, fogEnd)
	if enabled then
		Lighting.FogStart = 0
		Lighting.FogEnd = fogEnd or 30
	else
		Lighting.FogStart = originalFogStart
		Lighting.FogEnd = originalFogEnd
	end
end

local function playScream()
	local sound = Instance.new("Sound")
	sound.Name = "ScarecrowScream"
	sound.SoundId = "" -- TODO: put your scream SFX id here
	sound.Volume = 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

fearEffectRemote.OnClientEvent:Connect(function(effectType, ...)
	if effectType == "VisionReduced" then
		local enabled, fogEnd = ...
		setReducedVision(enabled, fogEnd)
	elseif effectType == "Scream" then
		playScream()
	end
end)