local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local zombiesFolder = workspace:WaitForChild("Zombies")
local humansFolder = workspace:WaitForChild("Humans")

local GraphModule = require(ReplicatedStorage:WaitForChild("Graph"))

local counterParts = {
	workspace.City:WaitForChild("Counter"),
	workspace.Farm:WaitForChild("Counter")
}

local graphParts = {
	workspace.City:WaitForChild("GraphFrame").SurfaceGui.GraphFrame,
	workspace.Farm:WaitForChild("GraphFrame").SurfaceGui.GraphFrame
}

local GraphHandlerCity = GraphModule.new(graphParts[1])
GraphHandlerCity.BaselineZero = true

local GraphHandlerFarm = GraphModule.new(graphParts[2])
GraphHandlerFarm.BaselineZero = true

local countData = {
	Zombies = {},
	Humans = {}
}

local counters = {}

for _, part in ipairs(counterParts) do
	local counterGui = part:WaitForChild("SurfaceGui")
	table.insert(counters, {
		ZombieLabel = counterGui:WaitForChild("ZombieCount"),
		HumanLabel = counterGui:WaitForChild("HumanCount")
	})
end

local function countAgents()
	local zombieCount, humanCount = 0, 0
	for _, zombie in ipairs(workspace.Zombies:GetChildren()) do
		local humanoid = zombie:FindFirstChild("Humanoid")
		if zombie:GetAttribute("Name") == "Zombie" and humanoid and humanoid.Health > 0 then 
			zombieCount += 1 
		end
	end

	for _, human in ipairs(workspace.Humans:GetChildren()) do
		local humanoid = human:FindFirstChild("Humanoid")
		if human:GetAttribute("Name") == "Human" and humanoid and humanoid.Health > 0 then 
			humanCount += 1 
		end
	end

	return zombieCount, humanCount
end

local function updateDisplay(t, isStarting)
	local zombieCount, humanCount = countAgents()

	-- Counters
	for _, counter in ipairs(counters) do
		counter.ZombieLabel.Text = "Zombies: " .. zombieCount
		counter.HumanLabel.Text = "Humans: " .. humanCount
	end

	-- Graphs
	local zombieTable = countData.Zombies
	local humanTable = countData.Humans
	
	zombieTable[t] = zombieCount
	humanTable[t] = humanCount
	
	GraphHandlerCity.Data = countData
	GraphHandlerFarm.Data = countData
end

local lastUpdate = 0
local totalTime = 1
RunService.Heartbeat:Connect(function()
	local currentTime = tick()
	if currentTime - lastUpdate >= 1 then
		totalTime += 1
		lastUpdate = currentTime
		updateDisplay(totalTime)
	end
end)

updateDisplay(totalTime)