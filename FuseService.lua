-- FuseService.lua
-- Tracks whether each player is currently holding a fuse (no colors).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FuseService = {}

local playerHeldFuse = {}

local remoteEvent = ReplicatedStorage:FindFirstChild("FuseHeldUpdate")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "FuseHeldUpdate"
	remoteEvent.Parent = ReplicatedStorage
end

function FuseService.IsHoldingFuse(player)
	return playerHeldFuse[player] ~= nil
end

function FuseService.PickUp(player, fuseModel)
	if playerHeldFuse[player] then
		return false
	end
	playerHeldFuse[player] = fuseModel
	fuseModel.Parent = nil
	remoteEvent:FireClient(player, true)
	return true
end

function FuseService.ClearHeldFuse(player)
	playerHeldFuse[player] = nil
	remoteEvent:FireClient(player, false)
end

function FuseService.GetHeldFuseModel(player)
	return playerHeldFuse[player]
end

function FuseService.Drop(player)
	local fuseModel = playerHeldFuse[player]
	if not fuseModel then
		return
	end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end

	local dropPosition = character.HumanoidRootPart.Position + Vector3.new(0, -2, 0)
	fuseModel.Parent = game.Workspace.Fuses

	if fuseModel:IsA("Model") then
		fuseModel:PivotTo(CFrame.new(dropPosition))
	elseif fuseModel:IsA("BasePart") then
		fuseModel.CFrame = CFrame.new(dropPosition)
	end

	playerHeldFuse[player] = nil
	remoteEvent:FireClient(player, false)
end

Players.PlayerRemoving:Connect(function(player)
	playerHeldFuse[player] = nil
end)

return FuseService