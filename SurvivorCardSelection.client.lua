-- SurvivorCardSelection.client.lua
-- See CardSelectionSetup.lua (ReplicatedStorage.Shared) for the actual
-- logic -- this just points it at SurvivorsContainer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardSelectionSetup = require(ReplicatedStorage.Shared.CardSelectionSetup)

CardSelectionSetup.Init("SurvivorsContainer", "SurvivorCardSelection")