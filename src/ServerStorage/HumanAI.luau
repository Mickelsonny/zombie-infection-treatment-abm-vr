local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local cureClaimedBindableEvent = ReplicatedStorage:WaitForChild("CureClaimedEvent")

local HumanoidList = require(ServerStorage.HumanoidList)
local AIUtilities = require(ServerStorage.AIUtilities)

local HumanAI = {}

function updateDisplay(display, state)
	local thread = coroutine.create(function()
		while true do
			task.wait()
			if state then
				display.Text = state.Name
			end
		end
	end)
	
	coroutine.resume(thread)
end

HumanAI.new = function(model)	
	local human = {}	

	local configTable = model.Configurations
	local configs = {}
	
	local function loadConfig(configName, defaultValue)
		if configTable:FindFirstChild(configName) then
			configs[configName] = configTable:FindFirstChild(configName).Value
		else
			configs[configName] = defaultValue
		end
	end

	loadConfig("DetectionRange", 50)
	loadConfig("FieldOfView", 180)
	loadConfig("FleeDistance", 30)
	loadConfig("ChanceOfBoredom", 0.7)
	loadConfig("BoredomDuration", 10)
	loadConfig("PanicDuration", 10)
	loadConfig("CureDetectionRange", 50)
	loadConfig("CureClaimDistance", 10)

	local StateMachine = require(ServerStorage.StateMachine).new()
	local PathLib = require(ServerStorage.PathfindingLibrary).new()
	local ThreatTarget = nil
	local FleeDirection = nil
	local CureTarget = nil
	local ZombieTarget = nil
	local cureUsesRemaining = 0
	local lastBored = os.time()	
	local lastPanicked = os.time()

	-- Cure tracking attributes
	if not model:GetAttribute("ObtainedCure") then
		model:SetAttribute("ObtainedCure", false)
	end
	
	if not model:GetAttribute("CureUsesRemaining") then
		model:SetAttribute("CureUsesRemaining", 0)
	end

	-- Function to find available cures
	local function findAvailableCure()
		local cures = {}
		
		-- Get all cures from both maps
		for _, cure in ipairs(workspace.City:WaitForChild("Cures"):GetChildren()) do
			table.insert(cures, cure)
		end

		for _, cure in ipairs(workspace.Farm:WaitForChild("Cures"):GetChildren()) do
			table.insert(cures, cure)
		end
		
		local availableCures = {}

		for _, cure in pairs(cures) do
			if cure:GetAttribute("Enabled") == true and cure:GetAttribute("Claimed") ~= true then
				local distance = (model.HumanoidRootPart.Position - cure:GetPivot().Position).Magnitude
				if distance <= configs["CureDetectionRange"] then
					table.insert(availableCures, {cure = cure, distance = distance})
					
					-- Alternative FOV check
					--[[local directionToCure = (cure:GetPivot().Position - model.HumanoidRootPart.Position).Unit
					local lookDirection = model.HumanoidRootPart.CFrame.LookVector
					local angle = math.acos(math.clamp(directionToCure:Dot(lookDirection), -1, 1))

					if math.deg(angle) <= configs["FieldOfView"] / 2 then
						table.insert(availableCures, {cure = cure, distance = distance})
					end]]
				end
			end
		end

		-- Return closest available cure
		if #availableCures > 0 then
			table.sort(availableCures, function(a, b) return a.distance < b.distance end)
			return availableCures[1].cure
		end

		return nil
	end

	-- Function to find closest zombie to hunt
	local function findZombieToHunt()
		if not model:GetAttribute("ObtainedCure") then return nil end

		local humanoids = HumanoidList:GetCurrent()
		local zombies = {}

		for _, object in pairs(humanoids) do
			if object and object.Parent and object.Parent:FindFirstChild("HumanoidRootPart") and object.Health > 0 and object.WalkSpeed > 0 then
				if object.Parent:GetAttribute("Name") == "Zombie" then
					local torso = object.Parent:FindFirstChild("HumanoidRootPart")
					if torso then
						local distance = (model.HumanoidRootPart.Position - torso.Position).magnitude
						if distance <= configs["DetectionRange"] then
							table.insert(zombies, {zombie = object.Parent, distance = distance})
						end
					end
				end
			end
		end

		-- Return closest zombie
		if #zombies > 0 then
			table.sort(zombies, function(a, b) return a.distance < b.distance end)
			return zombies[1].zombie
		end

		return nil
	end

	-- Function to handle zombie conversion
	local function setupZombieConversion()
		if not model:GetAttribute("ObtainedCure") or cureUsesRemaining <= 0 then return end

		local debounce = false
		local debounceTime = 1 -- Time to wait before allowing another cure to go into effect

		local connection
		connection = model.Torso.Touched:Connect(function(hit)
			if debounce then return end
			debounce = true

			local hitModel = hit.Parent
			if hitModel and hitModel:GetAttribute("Name") == "Zombie" and hitModel:FindFirstChild("Humanoid") and cureUsesRemaining > 0 then
				-- Track cure uses remaining
				cureUsesRemaining -= 1
				model:SetAttribute("CureUsesRemaining", cureUsesRemaining)

				-- Store zombie position and destroy it
				local zombiePosition = hitModel:FindFirstChild("HumanoidRootPart") and hitModel.HumanoidRootPart.Position

				-- Killing zombie (Indirectly spawning a human)
				hitModel.Humanoid.Health = 0

				-- Clear zombie target if it was the current target
				if ZombieTarget == hitModel then
					ZombieTarget = nil
				end

				if cureUsesRemaining <= 0 then
					model:SetAttribute("ObtainedCure", false)

					local highlight = model:FindFirstChildOfClass("Highlight")
					if highlight then highlight:Destroy() end

					for _, particleEmitter in pairs(model:GetDescendants()) do
						if particleEmitter:IsA("ParticleEmitter") and particleEmitter.Name == "CureAura" then
							particleEmitter:Destroy()
						end
					end

					connection:Disconnect()
				end
			end

			-- Release debounce after a short delay
			task.delay(debounceTime, function()
				debounce = false
			end)
		end)
	end

	-- IdleState: Human stays still, looking around for threats
	local IdleState = StateMachine.NewState()
	IdleState.Name = "Idle"
	IdleState.Action = function()
		-- Rotate (Looking around)
		if math.random() < 0.3 then
			local randomAngle = math.random() * math.pi * 2
			local lookDirection = Vector3.new(math.sin(randomAngle), 0, math.cos(randomAngle))

			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				local currentPos = root.Position
				local goalCFrame = CFrame.lookAt(currentPos, currentPos + lookDirection)

				local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0)

				local tween = TweenService:Create(root, tweenInfo, {CFrame = goalCFrame})
				tween:Play()
			end
		end
	end
	IdleState.Init = function()
		lastBored = os.time()
	end	

	-- WanderState: Human walks around casually, on alert for threats
	local WanderState = StateMachine.NewState()
	WanderState.Name = "Wander"
	local lastmoved = os.time()
	local wanderTarget = nil
	WanderState.Action = function()
		-- Move to random spot nearby at walking speed
		if model then
			local now = os.time()
			if now - lastmoved > 3 then
				lastmoved = now
				
				local xoff = math.random(10, 20)
				if math.random() > .5 then
					xoff = xoff * -1
				end
				
				local zoff = math.random(10, 20)
				if math.random() > .5 then
					zoff = zoff * -1
				end

				local testTarget = AIUtilities:FindCloseEmptySpace(model)
				if not testTarget then
					wanderTarget = Vector3.new(model.HumanoidRootPart.Position.X + xoff, model.HumanoidRootPart.Position.Y, model.HumanoidRootPart.Position.Z + zoff)
				else
					wanderTarget = testTarget
				end
			end
			
			if wanderTarget then
				-- Walk slowly when wandering
				model.Humanoid.WalkSpeed = 8
				PathLib:MoveToTarget(model, wanderTarget)
			end
		end
	end
	WanderState.Init = function()
		lastBored = os.time()
	end
	
	-- SeekCureState: Human actively seeks out available cures
	local SeekCureState = StateMachine.NewState()
	SeekCureState.Name = "SeekCure"
	local lastCureAttempt = 0
	local cureAttemptTimeout = 10
	local lastSearchMove = 0
	local searchTarget = nil

	SeekCureState.Action = function()
		if CureTarget and CureTarget.Parent then
			-- Check if cure is still available for claiming
			local cureStillAvailable = CureTarget:GetAttribute("Enabled") == true and CureTarget:GetAttribute("Claimed") ~= true

			-- Move towards the cure regardless of availability (claiming if it's available)
			model.Humanoid.WalkSpeed = 10

			-- Attempt movement
			PathLib:MoveToTarget(model, CureTarget:GetPivot().Position)

			-- Check if we're close enough to potentially claim the cure
			local distance = (model.HumanoidRootPart.Position - CureTarget:GetPivot().Position).Magnitude
			if not model:GetAttribute("ObtainedCure") and distance <= configs["CureClaimDistance"] then
				
				-- Only try to claim if cure is available
				if cureStillAvailable then
					-- Immediately mark as claimed
					CureTarget:SetAttribute("Claimed", true)

					-- Claim the cure
					model:SetAttribute("ObtainedCure", true)
					
					-- Manage cure uses
					cureUsesRemaining = 5
					model:SetAttribute("CureUsesRemaining", 5)

					-- Show that they have the cure with visual effects
					local highlight = Instance.new("Highlight")
					highlight.FillTransparency = 0.7
					highlight.FillColor = Color3.fromRGB(255, 170, 255)
					highlight.OutlineColor = Color3.fromRGB(255, 100, 130)
					highlight.Parent = model

					for _, part in pairs(model:GetChildren()) do
						if part:IsA("BasePart") then
							local cureAura = ReplicatedStorage.CureAura:Clone()
							cureAura.Parent = part
							cureAura.Enabled = true
						end
					end

					-- Fire the bindable event
					cureClaimedBindableEvent:Fire(CureTarget, model)

					-- Setup zombie conversion
					setupZombieConversion()

					-- Clear cure target
					CureTarget = nil
					lastCureAttempt = 0
				else
					-- Cure is no longer available (claimed by someone else / disabled)
					-- Clear the target so we can look for a new one
					CureTarget = nil
					lastCureAttempt = 0
				end
			else
				-- If we've been trying for too long, give up
				if lastCureAttempt == 0 then
					lastCureAttempt = os.time()
				elseif os.time() - lastCureAttempt > cureAttemptTimeout then
					CureTarget = nil
					lastCureAttempt = 0
				end
			end
		else
			-- No cure target - actively search for one
			
			-- Try to find a new cure
			local cure = findAvailableCure()
			if cure then
				CureTarget = cure
			else
				-- No cures available - wander around to search
				local now = os.time()
				if now - lastSearchMove > 2 then -- Move every 2 seconds while searching
					lastSearchMove = now

					-- Pick a random direction to search
					local searchAngle = math.random() * math.pi * 2
					local searchDistance = math.random(10, 20)
					
					searchTarget = model.HumanoidRootPart.Position + Vector3.new(
						math.sin(searchAngle) * searchDistance,
						0,
						math.cos(searchAngle) * searchDistance
					)
				end

				if searchTarget then
					model.Humanoid.WalkSpeed = 8
					PathLib:MoveToTarget(model, searchTarget)
				end
			end
		end
	end
	SeekCureState.Init = function()
		lastCureAttempt = 0
		lastSearchMove = 0
		searchTarget = nil
	end

	-- HuntZombieState: Humans with a cure seek out zombies to convert
	local HuntZombieState = StateMachine.NewState()
	HuntZombieState.Name = "HuntZombie"
	HuntZombieState.Action = function()
		if ZombieTarget and ZombieTarget.Parent and ZombieTarget:FindFirstChild("HumanoidRootPart") then
			-- Move towards the zombie at slightly faster walking speed
			model.Humanoid.WalkSpeed = 14
			PathLib:MoveToTarget(model, ZombieTarget.HumanoidRootPart.Position)
		else
			-- Zombie target is gone, clear it
			ZombieTarget = nil
		end
	end
	HuntZombieState.Init = function() end

	-- FleeState: Human has spotted a zombie, running away
	local FleeState = StateMachine.NewState()
	FleeState.Name = "Flee"
	FleeState.Action = function()
		if ThreatTarget then
			-- Calculate direction away from the threat
			local awayDirection = (model.HumanoidRootPart.Position - ThreatTarget.HumanoidRootPart.Position).Unit
			local fleeTarget = model.HumanoidRootPart.Position + (awayDirection * configs["FleeDistance"])

			-- Run fast when fleeing
			model.Humanoid.WalkSpeed = 16
			PathLib:MoveToTarget(model, fleeTarget)
		end
	end
	FleeState.Init = function()
		lastPanicked = os.time()
	end

	-- PanicState: Human continues to flee even after losing sight of threat
	local PanicState = StateMachine.NewState()
	PanicState.Name = "Panic"
	local panicTarget = nil
	PanicState.Action = function()
		-- Continue running in the same general direction
		if not panicTarget then
			if ThreatTarget then
				local awayDirection = (model.HumanoidRootPart.Position - ThreatTarget.HumanoidRootPart.Position).Unit
				panicTarget = model.HumanoidRootPart.Position + (awayDirection * configs["FleeDistance"])
			else
				-- If there's no specific threat, just run in a random direction
				local randomDirection = Vector3.new(math.random(-1, 1), 0, math.random(-1, 1)).Unit
				panicTarget = model.HumanoidRootPart.Position + (randomDirection * configs["FleeDistance"] / 2)
			end
		end

		model.Humanoid.WalkSpeed = 12
		
		if panicTarget then
			PathLib:MoveToTarget(model, panicTarget)
		end
	end
	PanicState.Init = function()
		lastPanicked = os.time()
		panicTarget = nil
	end

	-- CanSeeThreat: Determines if a zombie is visible (applies when NOT having cure).
	local CanSeeThreat = StateMachine.NewCondition()
	CanSeeThreat.Name = "CanSeeThreat"
	CanSeeThreat.Evaluate = function()
		-- If human has a cure, don't flee from zombies
		if model:GetAttribute("ObtainedCure") then return false end

		if model then
			local humanoids = HumanoidList:GetCurrent()	
			local zombies = {}
			local nonZombies = {}

			-- Separate zombies from other humanoids
			for _, object in pairs(humanoids) do
				if object and object.Parent and object.Parent:FindFirstChild("HumanoidRootPart") and object.Health > 0 and object.WalkSpeed > 0 then				
					local torso = object.Parent:FindFirstChild("HumanoidRootPart")
					if torso then
						local distance = (model.HumanoidRootPart.Position - torso.Position).magnitude
						if distance <= configs["DetectionRange"] then
							if object.Parent:GetAttribute("Name") == "Zombie" then
								table.insert(zombies, object.Parent)
							else
								table.insert(nonZombies, object.Parent)
							end
						end	
					end	
				end
			end	

			-- Look for the closest visible zombie threat
			local threat = AIUtilities:GetClosestVisibleTarget(model, zombies, nonZombies, configs["FieldOfView"])
			if threat then
				ThreatTarget = threat
				return true
			end
		end
		
		ThreatTarget = nil
		return false
	end
	CanSeeThreat.TransitionState = FleeState

	-- CanSeeCure: Determines if an available cure is visible.
	local CanSeeCure = StateMachine.NewCondition()
	CanSeeCure.Name = "CanSeeCure"
	CanSeeCure.Evaluate = function()
		-- Don't seek cures if already have one
		if model:GetAttribute("ObtainedCure") then return false end

		local cure = findAvailableCure()
		if cure then
			-- Only switch targets if human doesn't have one OR if the new one is significantly closer
			if not CureTarget then
				CureTarget = cure
				return true
			else
				local currentDistance = (model.HumanoidRootPart.Position - CureTarget:GetPivot().Position).Magnitude
				local newDistance = (model.HumanoidRootPart.Position - cure:GetPivot().Position).Magnitude

				if newDistance < currentDistance - 10 then
					CureTarget = cure
					return true
				end
			end
		else
			CureTarget = nil
		end

		return CureTarget ~= nil
	end
	CanSeeCure.TransitionState = SeekCureState

	-- CanSeeZombie: Determines if a zombie is visible for hunting (only when having a cure).
	local CanSeeZombie = StateMachine.NewCondition()
	CanSeeZombie.Name = "CanSeeZombie"
	CanSeeZombie.Evaluate = function()
		if not model:GetAttribute("ObtainedCure") then return false end

		local zombie = findZombieToHunt()
		if zombie then
			ZombieTarget = zombie
			return true
		end

		ZombieTarget = nil
		return false
	end
	CanSeeZombie.TransitionState = HuntZombieState

	-- CureTargetGone: Check if cure target is no longer available.
	local CureTargetGone = StateMachine.NewCondition()
	CureTargetGone.Name = "CureTargetGone"
	CureTargetGone.Evaluate = function()
		if not CureTarget or not CureTarget.Parent then
			return true
		end

		-- Check if cure was claimed by someone else
		if CureTarget:GetAttribute("Claimed") == true then
			return true
		end

		-- Check if cure is not enabled
		if CureTarget:GetAttribute("Enabled") ~= true then
			return true
		end

		-- If cure is too far away, abandon it
		local distance = (model.HumanoidRootPart.Position - CureTarget:GetPivot().Position).Magnitude
		if distance > configs["CureDetectionRange"] * 2 then
			return true
		end

		return false
	end
	CureTargetGone.TransitionState = IdleState

	-- ZombieTargetGone: Check if zombie target is no longer available.
	local ZombieTargetGone = StateMachine.NewCondition()
	ZombieTargetGone.Name = "ZombieTargetGone"
	ZombieTargetGone.Evaluate = function()
		-- Check zombie existence
		if not ZombieTarget or not ZombieTarget.Parent or not ZombieTarget:FindFirstChild("HumanoidRootPart") then
			return true
		end

		-- Check if zombie is too far away
		local distance = (model.HumanoidRootPart.Position - ZombieTarget.HumanoidRootPart.Position).Magnitude
		if distance > configs["DetectionRange"] * 1.5 then
			return true
		end

		-- Check if zombie is dead
		if ZombieTarget:FindFirstChild("Humanoid") and ZombieTarget.Humanoid.Health <= 0 then
			return true
		end

		return false
	end
	ZombieTargetGone.TransitionState = IdleState

	-- ThreatGone: Check if we can no longer see the threat.
	local ThreatGone = StateMachine.NewCondition()
	ThreatGone.Name = "ThreatGone"
	ThreatGone.Evaluate = function()
		if not ThreatTarget then
			return true
		end

		-- Ensure both have HumanoidRootParts
		if not (model:FindFirstChild("HumanoidRootPart")) or not (ThreatTarget:FindFirstChild("HumanoidRootPart")) then
			ThreatTarget = nil
			return true
		end

		-- Check if threat is too far away
		local distance = (model.HumanoidRootPart.Position - ThreatTarget.HumanoidRootPart.Position).Magnitude
		if distance > configs["DetectionRange"] * 1.5 then
			ThreatTarget = nil
			return true
		end

		return false
	end
	ThreatGone.TransitionState = PanicState

	-- CalmDown: Used to transition from panic back to normal behavior.
	local CalmDown = StateMachine.NewCondition()
	CalmDown.Name = "CalmDown"
	CalmDown.Evaluate = function()
		local now = os.time()
		if now - lastPanicked > configs["PanicDuration"] then
			return true
		end
		
		return false
	end
	CalmDown.TransitionState = IdleState

	-- GotBored: Provide random state change between Idle and Wander.
	local GotBored = StateMachine.NewCondition()
	GotBored.Name = "GotBored"
	GotBored.Evaluate = function()
		local now = os.time()
		if now - lastBored > configs["BoredomDuration"] then
			local random = math.random()
			if random < configs["ChanceOfBoredom"] then
				lastBored = now
				
				if GotBored.TransitionState == WanderState then
					GotBored.TransitionState = IdleState
				else
					GotBored.TransitionState = WanderState
				end
				
				return true
			end
		end
		
		return false
	end
	GotBored.TransitionState = IdleState

	-- Priority Matrix
	table.insert(IdleState.Conditions, CanSeeCure)
	table.insert(IdleState.Conditions, CanSeeThreat)
	table.insert(IdleState.Conditions, CanSeeZombie)
	table.insert(IdleState.Conditions, GotBored)

	table.insert(WanderState.Conditions, CanSeeCure)
	table.insert(WanderState.Conditions, CanSeeThreat)
	table.insert(WanderState.Conditions, CanSeeZombie)
	table.insert(WanderState.Conditions, GotBored)
	
	table.insert(FleeState.Conditions, CanSeeCure)
	table.insert(FleeState.Conditions, ThreatGone)

	table.insert(SeekCureState.Conditions, CanSeeThreat)
	table.insert(SeekCureState.Conditions, CureTargetGone)

	table.insert(HuntZombieState.Conditions, ZombieTargetGone)

	table.insert(PanicState.Conditions, CanSeeThreat)
	table.insert(PanicState.Conditions, CanSeeCure)
	table.insert(PanicState.Conditions, CalmDown)

	local thread = coroutine.create(function()
		while true do
			task.wait()
			
			local humanoids = HumanoidList:GetCurrent()
			local localHumans = {}
			for _, humanoid in pairs(humanoids) do
				if humanoid and humanoid ~= model.Humanoid and humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart") then
					-- Repel from other humans, not zombies!
					if humanoid.Parent:GetAttribute("Name") == "Human" then
						local torso = humanoid.Parent:FindFirstChild("HumanoidRootPart")
						local distance = (model.HumanoidRootPart.Position - torso.Position).magnitude
						if distance <= 3 then
							table.insert(localHumans, torso.Position)
						end
					end
				end
			end
			
			local repulsionDirection = AIUtilities:GetRepulsionVector(model.HumanoidRootPart.Position, localHumans)
			model.HumanoidRootPart.RepulsionForce.force = repulsionDirection

			if StateMachine.CurrentState and model.Configurations.Debug.Value then
				model.BillboardGui.TextLabel.Visible = true
				local displayText = StateMachine.CurrentState.Name
				
				if model:GetAttribute("ObtainedCure") then
					displayText = displayText .. " " .. cureUsesRemaining
				end
				
				model.BillboardGui.TextLabel.Text = displayText
			end
			
			if not model.Configurations.Debug.Value then
				model.BillboardGui.TextLabel.Visible = false
			end
		end
	end)
	
	coroutine.resume(thread)

	StateMachine.SwitchState(IdleState)

	human.Stop = function()
		StateMachine.SwitchState(nil)
	end	

	return human
end

return HumanAI