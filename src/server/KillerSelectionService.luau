-- KillerSelectionService.lua (ModuleScript)
-- Gives the chosen killer 15 seconds to pick which killer model to use.
-- Always waits the FULL window, even if they pick early, so the match
-- starts (and they become the killer) only after the timer runs out.
-- Defaults to Scarecrow if they don't choose in time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SELECTION_TIME = 15
local DEFAULT_KILLER = "ScarecrowModel"

local selectionRemote = ReplicatedStorage:FindFirstChild("KillerSelectionChosen")
if not selectionRemote then
	selectionRemote = Instance.new("RemoteEvent")
	selectionRemote.Name = "KillerSelectionChosen"
	selectionRemote.Parent = ReplicatedStorage
end

local promptRemote = ReplicatedStorage:FindFirstChild("KillerSelectionPrompt")
if not promptRemote then
	promptRemote = Instance.new("RemoteEvent")
	promptRemote.Name = "KillerSelectionPrompt"
	promptRemote.Parent = ReplicatedStorage
end

local KillerSelectionService = {}

local pendingSelections = {} -- [player] = chosen killer template name or nil

selectionRemote.OnServerEvent:Connect(function(player, killerName)
	if player:GetAttribute("IsKiller") then
		pendingSelections[player] = killerName
	end
end)

-- Runs the 15-second window for the given killer player.
-- Yields (waits) for the whole SELECTION_TIME, whether or not they pick.
function KillerSelectionService.RunSelection(killerPlayer)
	pendingSelections[killerPlayer] = nil

	promptRemote:FireClient(killerPlayer, true, SELECTION_TIME)

	local elapsed = 0
	while elapsed < SELECTION_TIME do
		-- stop early only if the killer left the server
		if not killerPlayer.Parent then
			break
		end
		task.wait(0.25)
		elapsed += 0.25
	end

	promptRemote:FireClient(killerPlayer, false)

	local chosen = pendingSelections[killerPlayer] or DEFAULT_KILLER
	killerPlayer:SetAttribute("SelectedKiller", chosen)
	pendingSelections[killerPlayer] = nil

	print(killerPlayer.Name .. " will play as: " .. chosen)
end

Players.PlayerRemoving:Connect(function(player)
	pendingSelections[player] = nil
end)

return KillerSelectionService