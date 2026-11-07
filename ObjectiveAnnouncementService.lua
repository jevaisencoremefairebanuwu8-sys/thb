-- ObjectiveAnnouncementService.lua  (ModuleScript)
-- Require this from any server script (GeneratorService, FuseboxService,
-- StageManager, LobbyService, PlayerAdded handler, etc.) to show the
-- animated objective banner on clients.
--
-- Usage:
--   local ObjectiveAnnouncementService = require(path.to.ObjectiveAnnouncementService)
--   ObjectiveAnnouncementService.AnnounceAll("Repair the Generators!", "5 remaining")
--   ObjectiveAnnouncementService.AnnouncePlayer(player, "Repair the Generators!")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObjectiveAnnouncementService = {}

-- Get-or-create the Remotes folder + RemoteEvent so you don't have to touch
-- your Rojo project structure at all.
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local announceRemote = remotesFolder:FindFirstChild("ObjectiveAnnouncement")
if not announceRemote then
	announceRemote = Instance.new("RemoteEvent")
	announceRemote.Name = "ObjectiveAnnouncement"
	announceRemote.Parent = remotesFolder
end

-- Fire to every player currently in the server.
-- text: main line (e.g. "Repair the Generators!")
-- subtext: optional smaller line underneath (e.g. "5 generators remain")
function ObjectiveAnnouncementService.AnnounceAll(text: string, subtext: string?)
	announceRemote:FireAllClients(text, subtext)
end

-- Fire to a single player only. Handy for the "first objective on join" case,
-- since a player who joins mid-match shouldn't re-trigger the banner for
-- everyone else.
function ObjectiveAnnouncementService.AnnouncePlayer(player: Player, text: string, subtext: string?)
	announceRemote:FireClient(player, text, subtext)
end

return ObjectiveAnnouncementService