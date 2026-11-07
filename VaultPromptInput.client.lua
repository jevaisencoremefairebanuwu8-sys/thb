-- VaultPromptInput.client.lua
-- Tracks the nearest vault in range and sends a vault request on E press.
--
-- Detection is based on distance to the NEARER of a vault's
-- StartPoint/EndPoint attachments (not the vault model's center) --
-- matches how VaultService.server.lua decides which point to run the
-- player to first. Also requires facing roughly toward that point
-- (mirrors the server's authoritative check) so a vault behind the
-- player never registers as available in the first place.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local palletsFolder = Workspace:WaitForChild("Pallets")

local player = Players.LocalPlayer
local mapModel = Workspace:WaitForChild("Map")
local vaultsFolder = mapModel:WaitForChild("Vaults")

local interactRemote = ReplicatedStorage:FindFirstChild("VaultInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "VaultInteract"
	interactRemote.Parent = ReplicatedStorage
end

local RANGE = 10
local VAULT_FACING_CONE_DEGREES = 120 -- keep in sync with VaultService.server.lua
local VAULT_FACING_DOT_THRESHOLD = math.cos(math.rad(VAULT_FACING_CONE_DEGREES / 2))
local currentTarget = nil

local function getMyRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- Returns the WorldPosition of whichever of vaultModel's StartPoint/
-- EndPoint is closer to `position`, and the distance to it. Returns
-- nil, math.huge if it's missing either attachment.
local function nearestPointInfo(vaultModel, position)
	local startPoint = vaultModel:FindFirstChild("StartPoint", true)
	local endPoint = vaultModel:FindFirstChild("EndPoint", true)
	if not startPoint or not endPoint then
		return nil, math.huge
	end
	local distToStart = (startPoint.WorldPosition - position).Magnitude
	local distToEnd = (endPoint.WorldPosition - position).Magnitude
	if distToStart <= distToEnd then
		return startPoint.WorldPosition, distToStart
	else
		return endPoint.WorldPosition, distToEnd
	end
end

-- True if targetPosition is roughly in front of root (within the front
-- 180-degree hemisphere of where it's facing), false if it's behind.
local function isFacingToward(root, targetPosition)
	local direction = targetPosition - root.Position
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude < 0.01 then
		return true
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

RunService.Heartbeat:Connect(function()
	local root = getMyRoot()
	if not root then
		return
	end
	local myPosition = root.Position

	local nearestVault, nearestDist = nil, RANGE

	local function considerVault(vaultModel)
		local pointPosition, dist = nearestPointInfo(vaultModel, myPosition)
		if pointPosition and dist <= nearestDist and isFacingToward(root, pointPosition) then
			nearestVault = vaultModel
			nearestDist = dist
		end
	end

	for _, vaultModel in ipairs(vaultsFolder:GetChildren()) do
		if vaultModel:IsA("Model") then
			considerVault(vaultModel)
		end
	end

	for _, palletModel in ipairs(palletsFolder:GetChildren()) do
		if palletModel:IsA("Model") and palletModel:GetAttribute("Dropped") and not palletModel:GetAttribute("Broken") then
			considerVault(palletModel)
		end
	end

	currentTarget = nearestVault
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.E and currentTarget then
		interactRemote:FireServer(currentTarget)
	end
end)