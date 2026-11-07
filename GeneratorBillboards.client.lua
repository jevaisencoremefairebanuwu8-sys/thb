-- GeneratorBillboards.client.lua
-- Clones the hand-built BillboardGui template from StarterGui onto
-- every generator, wired to show live progress through walls.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local generatorsFolder = Workspace:WaitForChild("Generators")

local template = playerGui:WaitForChild("GeneratorProgressBillboard")
print("Found template:", template)
template.Parent = nil

local function findMainPart(generatorModel)
	for _, descendant in ipairs(generatorModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function setupBillboard(generatorModel, mainPart)
	local billboard = template:Clone()
	billboard.Adornee = mainPart
	billboard.Parent = mainPart

	local track = billboard:WaitForChild("Track")
	local fill = track:WaitForChild("Fill")

	local function updateVisual()
		local progress = generatorModel:GetAttribute("Progress") or 0
		fill.Size = UDim2.new(progress / 100, 0, 1, 0)
		billboard.Enabled = not generatorModel:GetAttribute("Completed")
	end

	generatorModel:GetAttributeChangedSignal("Progress"):Connect(updateVisual)
	generatorModel:GetAttributeChangedSignal("Completed"):Connect(updateVisual)
	updateVisual()
end

for _, generatorModel in ipairs(generatorsFolder:GetChildren()) do
	if generatorModel:IsA("Model") then
		local mainPart = findMainPart(generatorModel)
		print("Setting up billboard for", generatorModel.Name, "mainPart:", mainPart)
		if mainPart then
			setupBillboard(generatorModel, mainPart)
		end
	end
end