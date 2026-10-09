local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local spectateFunction = ReplicatedStorage:WaitForChild("Spectate") :: RemoteFunction
local humanFunction = ReplicatedStorage:WaitForChild("Human") :: RemoteFunction
local zombieFunction = ReplicatedStorage:WaitForChild("Zombie") :: RemoteFunction
local resetFunction = ReplicatedStorage:WaitForChild("Reset") :: RemoteFunction
local parameterChangeEvent = ReplicatedStorage:WaitForChild("ParameterChange") :: RemoteEvent
local cureClaimedBindableEvent = ReplicatedStorage:WaitForChild("CureClaimedEvent") :: BindableEvent

local zombieAgent = ReplicatedStorage:WaitForChild("ZombieAgent")
local humanAgent = ReplicatedStorage:WaitForChild("HumanAgent")

local spawnLocations = nil
local cureModels = nil

local HumanFeature = require(ServerStorage.Functionality:WaitForChild("HumanFeature"))
local ZombieFeature = require(ServerStorage.Functionality:WaitForChild("ZombieFeature"))

-- Starting # of bundles for zombies and humans
local parameters = {
	agentsPerPoint = 10,
	humanPick = 4
}

parameterChangeEvent.OnServerEvent:Connect(function(player, paramName, value)
	if parameters[paramName] ~= nil then
		parameters[paramName] = value
		print(`[Server] Updated parameter {paramName} to {value}`)
	end
end)

local function enableParticles(effect, enabled)
	for _, particle in pairs(effect:GetDescendants()) do
		if particle:IsA("ParticleEmitter") then
			particle.Enabled = enabled
		end
		if particle:IsA("Beam") then
			particle.Enabled = enabled
		end
		if particle:IsA("Trail") then
			particle.Enabled = enabled
		end
		if particle:IsA("PointLight") then
			particle.Enabled = enabled
		end
	end
end

local function emitParticles(effect)
	for _, particle in pairs(effect:GetDescendants()) do
		if particle:IsA("ParticleEmitter") then
			particle:Emit(particle:GetAttribute("EmitCount"))
		end
	end
end

local function setModelCollision(instance, enabled)
	for _, desc in ipairs(instance:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = enabled
		end
	end
end

local function setModelVisibility(instance, isVisible)
	for _, desc in ipairs(instance:GetDescendants()) do
		if desc:IsA("BasePart") then
			if desc.Name == "Meshes/Sphere (3)" then
				desc.Transparency = isVisible and 0.7 or 1
			else
				desc.Transparency = isVisible and 0 or 1
			end
		end
	end
end

local function shuffleArray(array)
	local shuffled = {}
	for i = 1, #array do
		shuffled[i] = array[i]
	end

	for i = #shuffled, 2, -1 do
		local j = math.random(i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	return shuffled
end

local function startSimulation(mapSelected)
	local shuffledSpawns = shuffleArray(spawnLocations)
	local shuffledCures  = shuffleArray(cureModels)
	local total = #shuffledSpawns

	-- Hide all cures initially
	for _, cure in ipairs(cureModels) do
		setModelVisibility(cure, false)
	end

	-- Randomly pick up to 10 cures to reveal
	local toReveal = math.min(10, #shuffledCures)
	for i = 1, toReveal do
		local cureModel = shuffledCures[i]

		setModelVisibility(cureModel, true)
		enableParticles(cureModel, true)
		setModelCollision(cureModel, true)

		cureModel:SetAttribute("Enabled", true)
		cureModel:SetAttribute("Claimed", false)
	end

	local numZombieSpawns = 8 - parameters.humanPick

	local zombieSpawns = {}
	for i = 1, numZombieSpawns do
		table.insert(zombieSpawns, shuffledSpawns[i])
	end

	local humanSpawns = {}
	for i = numZombieSpawns + 1, 8 do
		table.insert(humanSpawns, shuffledSpawns[i])
	end

	-- Spawn X zombie agents at each selected spawn point
	for _, spawnPoint in ipairs(zombieSpawns) do
		for i = 1, parameters.agentsPerPoint do
			local zombie = zombieAgent:Clone()
			zombie.Parent = workspace.Zombies

			local offset = CFrame.new(math.random(-15, 15), 2.5, math.random(-15, 15))

			if zombie.PrimaryPart then
				zombie:PivotTo(CFrame.new((spawnPoint.CFrame * offset).Position))
			elseif zombie:FindFirstChild("HumanoidRootPart") then
				zombie.HumanoidRootPart.CFrame = spawnPoint.CFrame * offset
			end
		end
	end

	-- Spawn X human agents at each selected spawn point
	for _, spawnPoint in ipairs(humanSpawns) do
		for i = 1, parameters.agentsPerPoint do
			local human = humanAgent:Clone()
			human.Parent = workspace.Humans

			local offset = CFrame.new(math.random(-15, 15), 2.5, math.random(-15, 15))

			if human.PrimaryPart then
				human:PivotTo(CFrame.new((spawnPoint.CFrame * offset).Position))
			elseif human:FindFirstChild("HumanoidRootPart") then
				human.HumanoidRootPart.CFrame = spawnPoint.CFrame * offset
			end
		end
	end
	
	return true
end

local function resetSimulation(player)
	local zombiesFolder = workspace:FindFirstChild("Zombies")
	if zombiesFolder then
		for _, zombie in ipairs(zombiesFolder:GetChildren()) do
			zombie:Destroy()
		end
	end

	local humansFolder = workspace:FindFirstChild("Humans")
	if humansFolder then
		for _, human in ipairs(humansFolder:GetChildren()) do
			human:Destroy()
		end
	end

	for _, cure in ipairs(cureModels) do
		setModelVisibility(cure, false)

		enableParticles(cure, false)

		setModelCollision(cure, false)

		cure:SetAttribute("Enabled", false)
		cure:SetAttribute("Claimed", false)

		local returnPotion = cure:FindFirstChild("ReturnPotion")
		if returnPotion then
			setModelVisibility(returnPotion, false)
			enableParticles(returnPotion, false)
			setModelCollision(returnPotion, false)
		end
	end
	
	HumanFeature.Cancel(player)
	ZombieFeature.Cancel(player)
	
	return true
end

cureClaimedBindableEvent.Event:Connect(function(cureModel, human)
	setModelVisibility(cureModel.ReturnPotion, false)
	enableParticles(cureModel.ReturnPotion, false)
	setModelCollision(cureModel.ReturnPotion, false)
	
	cureModel:SetAttribute("Claimed", true)
	
	task.delay(10, function()
		setModelVisibility(cureModel.ReturnPotion, true)
		enableParticles(cureModel.ReturnPotion, true)
		setModelCollision(cureModel.ReturnPotion, true)
		
		cureModel:SetAttribute("Claimed", false)
	end)
end)

spectateFunction.OnServerInvoke = function(player, mapSelected)
	spawnLocations = workspace:FindFirstChild(mapSelected).Spawns:GetChildren()
	cureModels = workspace:FindFirstChild(mapSelected).Cures:GetChildren()
	
	return startSimulation(mapSelected)
end

humanFunction.OnServerInvoke = function(player, mapSelected)
	spawnLocations = workspace:FindFirstChild(mapSelected).Spawns:GetChildren()
	cureModels = workspace:FindFirstChild(mapSelected).Cures:GetChildren()
	
	HumanFeature.Initialize(player)
	
	return startSimulation(mapSelected)
end

zombieFunction.OnServerInvoke = function(player, mapSelected)
	spawnLocations = workspace:FindFirstChild(mapSelected).Spawns:GetChildren()
	cureModels = workspace:FindFirstChild(mapSelected).Cures:GetChildren()
	
	ZombieFeature.Initialize(player)

	return startSimulation(mapSelected)
end

resetFunction.OnServerInvoke = function(player)
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	humanoid.Health = humanoid.MaxHealth
	
	return resetSimulation(player)
end

-- Simulation runs for data collection
local DATA_COLLECTION_ENABLED = false
local NUM_TRIALS = 30
local RUN_DURATION = 80
local SAMPLE_INTERVAL = 1
local MAX_ATTEMPTS = 3 -- # of retries if a trial has an error

local MAPS = {"Farm", "City"}
local SETTINGS = {
	{agentsPerPoint = 10, humanPick = 4},
	{agentsPerPoint = 15, humanPick = 4},
	{agentsPerPoint = 10, humanPick = 6},
	{agentsPerPoint = 15, humanPick = 6},
}

-- Death reset (ignored during data collection in case of player death)
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")

		local diedConnection
		diedConnection = humanoid.Died:Connect(function()
			if diedConnection then
				diedConnection:Disconnect()
				diedConnection = nil
			end

			if DATA_COLLECTION_ENABLED then return end
			resetSimulation(player)
		end)
	end)
end)

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

local function runTrial()
	local zombies, humans = {}, {}
	local t0 = os.clock()
	for k = 0, RUN_DURATION / SAMPLE_INTERVAL do
		task.wait(math.max(t0 + k * SAMPLE_INTERVAL - os.clock(), 0))
		
		local zombie, human = countAgents()
		table.insert(zombies, zombie)
		table.insert(humans, human)
	end
	
	return zombies, humans
end

if DATA_COLLECTION_ENABLED then
	task.spawn(function()
		local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
		task.wait(3) -- allow time for the map to load

		local totalRuns = #MAPS * #SETTINGS * NUM_TRIALS
		local done = 0

		for _, mapName in ipairs(MAPS) do
			local mapFolder = workspace:WaitForChild(mapName)
			spawnLocations = mapFolder.Spawns:GetChildren()
			cureModels = mapFolder.Cures:GetChildren()

			for _, setting in ipairs(SETTINGS) do
				parameters.agentsPerPoint = setting.agentsPerPoint
				parameters.humanPick = setting.humanPick
				local metadata = string.format("%s,%d,%d", mapName, setting.agentsPerPoint, setting.humanPick)

				for trial = 1, NUM_TRIALS do
					local zombies, humans

					for attempt = 1, MAX_ATTEMPTS do
						local success, dataZ, dataH = pcall(function()
							startSimulation(mapName)
							return runTrial()
						end)

						local s, r = pcall(resetSimulation, player)
						if not s then
							warn("Reset failed:", r) 
						end
						task.wait(5)

						if success then
							zombies, humans = dataZ, dataH
							break
						end
						warn(string.format("%s trial %d attempt %d failed: %s", metadata, trial, attempt, tostring(dataZ)))
					end

					if zombies then
						print(table.concat({
							"#BEGIN",
							string.format("%s,zombies,%d,%s", metadata, trial, table.concat(zombies, ",")),
							string.format("%s,humans,%d,%s", metadata, trial, table.concat(humans, ",")),
							"#END",
						}, "\n"))
					end

					done += 1
					print(string.format("Progress: %d/%d runs", done, totalRuns))
				end
			end
		end

		print("ALL SIMULATION RUNS COMPLETE!")
	end)
end