-- ScarecrowAbilityInput.client.lua
-- F = place a Scarecrow Effigy (active ability)
-- T = teleport to nearest Effigy (passive)
-- Only fires while this client's player is the killer with Scarecrow selected.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

local abilityRemote = ReplicatedStorage:WaitForChild("ScarecrowAbilityRequest")

local function isScarecrow()
	return localPlayer:GetAttribute("IsKiller")
		and (localPlayer:GetAttribute("SelectedKiller") or ""):find("Scarecrow") ~= nil
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not isScarecrow() then
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		abilityRemote:FireServer("PlaceEffigy")
	elseif input.KeyCode == Enum.KeyCode.T then
		abilityRemote:FireServer("Teleport")
	end
end)