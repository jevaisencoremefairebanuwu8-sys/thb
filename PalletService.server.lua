-- PalletService.server.lua
-- Survivors press E to instantly drop a standing pallet (rotates down on
-- its hinge), playing the PalletDrop animation. If the killer is too
-- close when it drops, they get stunned. Killer holds E on a dropped
-- pallet to break it (takes BREAK_DURATION).

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressBarService = require(ReplicatedStorage.Shared.ProgressBarService)
local ActionAnimationService = require(ReplicatedStorage.Shared.ActionAnimationService)

print("PalletService: all requires loaded successfully")

local PALLET_FALL_ANGLE = 85
local PALLET_FALL_TIME = 0.35
local STUN_RANGE = 8
local STUN_DURATION = 3
local BREAK_DURATION = 2
local MAX_INTERACT_DISTANCE = 8

local palletsFolder = Workspace:WaitForChild("Pallets")

local palletData = {} -- [palletModel] = { dropped = false, broken = false }
local activeBreaks = {} -- [killerPlayer] = { palletModel, progress }

local interactRemote = ReplicatedStorage:FindFirstChild("PalletInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "PalletInteract"
	interactRemote.Parent = ReplicatedStorage
end

local cancelRemote = ReplicatedStorage:FindFirstChild("CancelTimedAction")
if not cancelRemote then
	cancelRemote = Instance.new("RemoteEvent")
	cancelRemote.Name = "CancelTimedAction"
	cancelRemote.Parent = ReplicatedStorage
end

local function findMainPart(palletModel)
	for _, descendant in ipairs(palletModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function dropPalletVisual(palletModel)
	local mainPart = findMainPart(palletModel)
	if not mainPart then
		return
	end
	local hinge = mainPart:FindFirstChild("PalletHinge")
	if not hinge then
		warn(palletModel.Name .. " has no PalletHinge attachment")
		return
	end

	local hingeCFrame0 = hinge.WorldCFrame
	local offset = hingeCFrame0:ToObjectSpace(mainPart.CFrame)

	local fallAngle = PALLET_FALL_ANGLE
	if palletModel:GetAttribute("FlipFall") then
		fallAngle = -fallAngle
	end

	local startTime = tick()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / PALLET_FALL_TIME, 1)
		local currentAngle = fallAngle * alpha

		mainPart.CFrame = hingeCFrame0 * CFrame.Angles(math.rad(currentAngle), 0, 0) * offset

		if alpha >= 1 then
			connection:Disconnect()
		end
	end)
end

local function stunKillerIfNearby(palletModel)
	local mainPart = findMainPart(palletModel)
	if not mainPart then
		return
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer:GetAttribute("IsKiller") then
			local character = otherPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local distance = (root.Position - mainPart.Position).Magnitude
				if distance <= STUN_RANGE then
					otherPlayer:SetAttribute("IsStunned", true)
					print(otherPlayer.Name .. " was stunned by a pallet!")
					task.delay(STUN_DURATION, function()
						otherPlayer:SetAttribute("IsStunned", false)
					end)
				end
			end
		end
	end
end

local function setupPallet(palletModel)
	palletData[palletModel] = { dropped = false, broken = false }
	palletModel:SetAttribute("Dropped", false)
	palletModel:SetAttribute("Broken", false)
end

local function stopBreaking(killerPlayer)
	local breakInfo = activeBreaks[killerPlayer]
	if not breakInfo then
		return
	end
	ProgressBarService.Hide(killerPlayer)
	activeBreaks[killerPlayer] = nil
end

interactRemote.OnServerEvent:Connect(function(player, palletModel, action)
	if not palletModel or not palletModel:IsDescendantOf(palletsFolder) then
		return
	end
	local data = palletData[palletModel]
	if not data or data.broken then
		return
	end

	local isKiller = player:GetAttribute("IsKiller")

	if not isKiller then
		if data.dropped then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local mainPart = findMainPart(palletModel)
		if not root or not mainPart then
			return
		end
		if (root.Position - mainPart.Position).Magnitude > MAX_INTERACT_DISTANCE then
			return
		end

		data.dropped = true
		palletModel:SetAttribute("Dropped", true)
		dropPalletVisual(palletModel)
		stunKillerIfNearby(palletModel)
		ActionAnimationService.PlayOnce(player, "PalletDrop", function() end)
		print(player.Name .. " dropped " .. palletModel.Name)
	else
		if not data.dropped then
			return
		end
		if player:GetAttribute("IsCarrying") then
			return
		end

		if action == "start" then
			if activeBreaks[player] then
				return
			end

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local mainPart = findMainPart(palletModel)
			if not root or not mainPart then
				return
			end
			if (root.Position - mainPart.Position).Magnitude > MAX_INTERACT_DISTANCE then
				return
			end

			activeBreaks[player] = { palletModel = palletModel, progress = 0 }
		elseif action == "stop" then
			stopBreaking(player)
		end
	end
end)

cancelRemote.OnServerEvent:Connect(function(player)
	if activeBreaks[player] then
		stopBreaking(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if activeBreaks[player] then
		stopBreaking(player)
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	for killerPlayer, breakInfo in pairs(activeBreaks) do
		breakInfo.progress = math.min(100, breakInfo.progress + (100 / BREAK_DURATION) * deltaTime)
		ProgressBarService.Update(killerPlayer, "Breaking", breakInfo.progress)

		if breakInfo.progress >= 100 then
			local palletModel = breakInfo.palletModel
			local data = palletData[palletModel]
			if data then
				data.broken = true
				palletModel:SetAttribute("Broken", true)
			end
			ProgressBarService.Hide(killerPlayer)
			activeBreaks[killerPlayer] = nil
			print(killerPlayer.Name .. " broke " .. palletModel.Name)

			local mainPart = findMainPart(palletModel)
			if mainPart then
				mainPart.Transparency = 0.7
				mainPart.CanCollide = false
			end
		end
	end
end)

local totalPallets = 0
for _, palletModel in ipairs(palletsFolder:GetChildren()) do
	if palletModel:IsA("Model") then
		setupPallet(palletModel)
		totalPallets += 1
	end
end

print("PalletService loaded. Tracking " .. totalPallets .. " pallet(s).")