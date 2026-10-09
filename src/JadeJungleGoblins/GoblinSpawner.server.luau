--[[
	Spawns Jade Jungle goblins and runs their AI: wander around their spawn
	point, chase nearby players, slash them with the scimitar, ragdoll on death
	and respawn later. This is a Script with RunContext = Server, so it runs
	from ReplicatedStorage.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local GoblinBuilder = require(folder:WaitForChild("GoblinBuilder"))

local rng = Random.new()

local goblinFolder = Workspace:FindFirstChild("JadeGoblins") or Instance.new("Folder")
goblinFolder.Name = "JadeGoblins"
goblinFolder.Parent = Workspace

-- Ragdoll pieces collide with the world but not with each other.
local RAGDOLL_GROUP = "JadeGoblinRagdoll"
pcall(function()
	PhysicsService:RegisterCollisionGroup(RAGDOLL_GROUP)
	PhysicsService:CollisionGroupSetCollidable(RAGDOLL_GROUP, RAGDOLL_GROUP, false)
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function groundAt(position)
	local ignore = { goblinFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -200, 0), rayParams)
	return result and result.Position or position
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function findTarget(position, home)
	local best, bestRoot, bestDist = nil, nil, Config.AggroRange
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			local dist = (root.Position - position).Magnitude
			if dist < bestDist and (root.Position - home).Magnitude <= Config.LeashRange then
				best, bestRoot, bestDist = humanoid, root, dist
			end
		end
	end
	return best, bestRoot, bestDist
end

local function ragdoll(model)
	model:SetAttribute("Dead", true)
	CollectionService:RemoveTag(model, Config.Tag)
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") then
			if motor.Name == "Root" then
				motor:Destroy()
			else
				-- Point each socket's limit cone along the limb so the rest pose is inside it.
				local name = motor.Name
				local axis
				if name == "Waist" or name == "Neck" then
					axis = CFrame.Angles(0, 0, math.pi / 2)
				elseif name == "LeftEar" then
					axis = CFrame.Angles(0, math.pi, 0)
				elseif name == "RightEar" then
					axis = CFrame.identity
				else
					axis = CFrame.Angles(0, 0, -math.pi / 2)
				end
				local a0 = Instance.new("Attachment")
				a0.CFrame = motor.C0 * axis
				a0.Parent = motor.Part0
				local a1 = Instance.new("Attachment")
				a1.CFrame = motor.C1 * axis
				a1.Parent = motor.Part1
				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.LimitsEnabled = true
				socket.UpperAngle = 50
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = -30
				socket.TwistUpperAngle = 30
				socket.Parent = motor.Part1
				motor.Enabled = false
			end
		end
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.CollisionGroup = RAGDOLL_GROUP
			-- Body segments (the ones holding a joint) give the ragdoll weight and collision.
			if part:FindFirstChildOfClass("Motor6D") or part.Name == "LowerTorso" then
				part.CanCollide = true
				part.Massless = false
			end
		end
	end
	if root then
		root.Anchored = true
		root.CanCollide = false
	end

	local torso = model:FindFirstChild("UpperTorso")
	if torso and root then
		torso:ApplyImpulse((root.CFrame.LookVector * -6 + Vector3.new(0, 4, 0)) * torso.AssemblyMass)
	end
end

local function attack(model, root, targetHumanoid, targetRoot)
	model:SetAttribute("AttackStart", Workspace:GetServerTimeNow())
	-- Deal damage when the blade comes down, if the target is still in reach.
	task.delay(Config.AttackDuration * 0.5, function()
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not model.Parent or not humanoid or humanoid.Health <= 0 then
			return
		end
		if targetHumanoid.Health > 0 and (targetRoot.Position - root.Position).Magnitude <= Config.AttackRange + 2 then
			targetHumanoid:TakeDamage(Config.AttackDamage)
		end
	end)
end

local function runBrain(model, home)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	local lastAttack = 0
	local wanderGoal = nil
	local idleUntil = os.clock() + rng:NextNumber(0, 3)
	local stuckTime = 0
	local lastPos = root.Position

	while model.Parent and humanoid.Health > 0 do
		local dt = task.wait(Config.ThinkInterval)
		if not model.Parent or humanoid.Health <= 0 then
			break
		end
		local pos = root.Position
		local targetHumanoid, targetRoot, dist = findTarget(pos, home)

		if targetRoot then
			wanderGoal = nil
			humanoid.WalkSpeed = Config.ChaseSpeed
			if dist > Config.AttackRange then
				humanoid:MoveTo(targetRoot.Position)
			else
				humanoid:MoveTo(pos)
				local look = Vector3.new(targetRoot.Position.X, pos.Y, targetRoot.Position.Z)
				if (look - pos).Magnitude > 0.1 then
					root.CFrame = CFrame.lookAt(pos, look)
				end
				if os.clock() - lastAttack >= Config.AttackCooldown then
					lastAttack = os.clock()
					attack(model, root, targetHumanoid, targetRoot)
				end
			end
		else
			humanoid.WalkSpeed = Config.WanderSpeed
			if flat(pos - home).Magnitude > Config.WanderRadius * 1.5 then
				wanderGoal = home -- wandered or chased too far: head back
			end
			if wanderGoal then
				if flat(wanderGoal - pos).Magnitude < 2.5 then
					wanderGoal = nil
					idleUntil = os.clock() + rng:NextNumber(1.5, 5)
					humanoid:MoveTo(pos)
				else
					humanoid:MoveTo(wanderGoal)
				end
			elseif os.clock() >= idleUntil then
				local angle = rng:NextNumber(0, math.pi * 2)
				local radius = rng:NextNumber(4, Config.WanderRadius)
				wanderGoal = groundAt(home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
			end
		end

		-- Jump over roots and rocks; give up on a wander goal we can't reach.
		if humanoid.MoveDirection.Magnitude > 0.1 and flat(pos - lastPos).Magnitude < humanoid.WalkSpeed * dt * 0.25 then
			stuckTime += dt
			if stuckTime > 0.6 then
				humanoid.Jump = true
				stuckTime = 0
				if not targetRoot and wanderGoal ~= home then
					wanderGoal = nil
				end
			end
		else
			stuckTime = 0
		end
		lastPos = pos
	end
end

local function spawnGoblin(home)
	local model = GoblinBuilder.build({ scale = Config.Scale, random = rng })
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = Config.MaxHealth
	humanoid.Health = Config.MaxHealth
	humanoid.WalkSpeed = Config.WanderSpeed

	model:PivotTo(CFrame.new(groundAt(home)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = goblinFolder
	model.PrimaryPart:SetNetworkOwner(nil)

	for _, state in {
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Seated,
	} do
		humanoid:SetStateEnabled(state, false)
	end

	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth and health > 0 then
			model:SetAttribute("HurtStart", Workspace:GetServerTimeNow())
		end
		lastHealth = health
	end)

	CollectionService:AddTag(model, Config.Tag)
	task.spawn(runBrain, model, home)
	return model, humanoid
end

-- One "slot" per goblin: keep it alive, and respawn it after it dies.
local function runSlot(home)
	while true do
		local model, humanoid = spawnGoblin(home)
		humanoid.Died:Wait()
		ragdoll(model)
		task.delay(Config.CorpseTime, function()
			model:Destroy()
		end)
		task.wait(Config.RespawnTime)
	end
end

local function findSpawnPoints()
	local node = Workspace
	for _, name in Config.SpawnFolderPath do
		node = node and node:FindFirstChild(name)
	end
	local points = {}
	if node then
		for _, part in node:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(points, part.Position)
			end
		end
	end
	if #points == 0 then
		warn(`[JadeGoblins] No spawn Parts found in Workspace.{table.concat(Config.SpawnFolderPath, ".")}; spawning around FallbackCenter.`)
		for _ = 1, Config.FallbackCount do
			local angle = rng:NextNumber(0, math.pi * 2)
			local radius = rng:NextNumber(0, Config.FallbackRadius)
			table.insert(points, Config.FallbackCenter + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		end
	end
	return points
end

local total = 0
for _, home in findSpawnPoints() do
	for _ = 1, Config.GoblinsPerSpawn do
		if total >= Config.MaxGoblins then
			break
		end
		total += 1
		task.spawn(runSlot, home)
	end
end
