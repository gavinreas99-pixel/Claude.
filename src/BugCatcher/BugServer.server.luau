--[[
	Bug server: spawns bugs, moves them, hands out bug nets and decides what
	gets caught.

	Each bug is one invisible anchored Part in Workspace.Bugs, named after
	its bug Id. The server is the only one that moves it, so catches are
	checked against the real position. BugVisuals draws the actual bug
	on each player's screen and smooths its motion.

	Spawning:
	  Common bugs: any time.  Rare bugs: only at night.  Epic bugs: only in the rain.
	  Rare bugs leave when the sun comes up, and Epic bugs leave when the rain stops.

	Catching: a client only says "I swung". The server checks the swing rate,
	that the player is alive and holding the net, and which bugs are really
	inside the net's reach, so nobody can catch bugs from across the field.

	This is a Script with RunContext = Server, so it runs from ReplicatedStorage.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local BugData = require(folder:WaitForChild("BugData"))
local BugBuilder = require(folder:WaitForChild("BugBuilder"))
local Environment = require(folder:WaitForChild("Environment"))
local Collection = require(folder:WaitForChild("Collection"))
local NetBuilder = require(folder:WaitForChild("NetBuilder"))
local Util = require(folder:WaitForChild("Util"))
local create = Util.create

local remote = folder:FindFirstChild("BugRemote") or create("RemoteEvent", { Name = "BugRemote", Parent = folder })

Collection.notify = function(player, title, text)
	remote:FireClient(player, "Notice", title, text)
end

local oldFolder = Workspace:FindFirstChild("Bugs")
if oldFolder then
	oldFolder:Destroy()
end
local bugsFolder = create("Folder", { Name = "Bugs", Parent = Workspace })

local rng = Random.new()
local bugs = {} -- [anchor Part] = bug state
local counts = { Common = 0, Rare = 0, Epic = 0 }
local maxCounts = { Common = Config.MaxCommonBugs, Rare = Config.MaxRareBugs, Epic = Config.MaxEpicBugs }

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { Workspace.Terrain }

local function groundHeight(position)
	local result = Workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), groundParams)
	return result and result.Position.Y or 0
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function randomDirection()
	local angle = rng:NextNumber(0, math.pi * 2)
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function randomFieldPoint(radius)
	return randomDirection() * math.sqrt(rng:NextNumber()) * radius
end

local function playerPositions()
	local positions = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

local function pickWanderTarget(bug)
	local range = bug.flying and 30 or 16
	local target = flat(bug.position) + Vector3.new(rng:NextNumber(-range, range), 0, rng:NextNumber(-range, range))
	local limit = Config.FieldRadius * 0.92
	if target.Magnitude > limit then
		target = target.Unit * limit * rng:NextNumber(0.6, 1)
	end
	bug.target = target
end

local function spawnBug(info, positions)
	local point
	for _ = 1, 10 do
		local candidate = randomFieldPoint(Config.FieldRadius * 0.9)
		local clear = true
		for _, position in positions do
			if (flat(position) - candidate).Magnitude < Config.SpawnMinPlayerDistance then
				clear = false
				break
			end
		end
		if clear then
			point = candidate
			break
		end
	end
	if not point then
		return nil
	end

	local flying = info.Move == "Fly"
	local ground = groundHeight(point)
	local bug = {
		info = info,
		rarity = BugData.Rarities[info.Rarity],
		flying = flying,
		ground = ground,
		nextGroundCheck = 0,
		altitude = flying and rng:NextNumber(2.5, 4.8) or 0,
		lift = 0,
		phase = rng:NextNumber(0, math.pi * 2),
		heading = randomDirection(),
		speed = 0,
		pauseUntil = 0,
		fleeUntil = 0,
		fleeDirection = nil,
		leaveAt = nil,
		leaving = false,
		goneAt = 0,
	}
	bug.position = point + Vector3.new(0, ground + (flying and bug.altitude or BugBuilder.groundOffset(info)), 0)
	pickWanderTarget(bug)

	local anchor = create("Part", {
		Name = info.Id,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.one * 0.4,
		CFrame = CFrame.lookAt(bug.position, bug.position + bug.heading),
	})
	anchor:SetAttribute("BugId", info.Id)
	anchor.Parent = bugsFolder
	bug.part = anchor
	bugs[anchor] = bug
	counts[info.Rarity] += 1
	return bug
end

-- Removes a bug. `caught` tells clients to play the catch effect instead of a fade.
local function removeBug(bug, caught)
	if bugs[bug.part] ~= bug then
		return
	end
	bugs[bug.part] = nil
	counts[bug.info.Rarity] -= 1
	if caught then
		bug.part:SetAttribute("Caught", true)
	end
	-- A short delay makes sure clients see the Caught flag before the part goes.
	task.delay(0.15, function()
		bug.part:Destroy()
	end)
end

local function steer(current, desired, rate, dt)
	local blended = current:Lerp(desired, math.min(1, rate * dt))
	if blended.Magnitude < 1e-3 then
		return desired
	end
	return blended.Unit
end

local function updateBug(bug, now, dt, positions)
	local info, rarity = bug.info, bug.rarity
	local here = flat(bug.position)

	-- Run from the nearest player who gets too close.
	local nearest, nearestDistance = nil, math.huge
	for _, position in positions do
		local distance = (flat(position) - here).Magnitude
		if distance < nearestDistance then
			nearest, nearestDistance = position, distance
		end
	end
	if nearest and nearestDistance < rarity.FleeRadius and not bug.leaving then
		local away = here - flat(nearest)
		bug.fleeDirection = away.Magnitude > 0.01 and away.Unit or bug.heading
		bug.fleeUntil = now + 1.2
		bug.pauseUntil = 0
	end

	local fleeing = now < bug.fleeUntil
	local desired, targetSpeed, turnRate
	if bug.leaving then
		desired, targetSpeed, turnRate = bug.heading, info.Speed, 2
	elseif fleeing then
		-- Zig-zag a little so bugs feel alive and are fun to chase.
		local wobble = math.sin(now * 3 + bug.phase) * 0.5
		desired, targetSpeed, turnRate = CFrame.Angles(0, wobble, 0) * bug.fleeDirection, rarity.FleeSpeed, 7
	elseif now < bug.pauseUntil then
		desired, targetSpeed, turnRate = bug.heading, 0, 2
	else
		local toTarget = bug.target - here
		if toTarget.Magnitude < 1.5 then
			pickWanderTarget(bug)
			if rng:NextNumber() < (bug.flying and 0.35 or 0.6) then
				bug.pauseUntil = now + rng:NextNumber(0.6, bug.flying and 1.6 or 3)
			end
			toTarget = bug.target - here
		end
		desired = toTarget.Magnitude > 0.01 and toTarget.Unit or bug.heading
		targetSpeed, turnRate = info.Speed, 3
	end

	-- Never leave the meadow (unless flying away for good).
	if here.Magnitude > Config.FieldRadius and not bug.leaving then
		desired, turnRate = -here.Unit, 6
	end

	bug.heading = steer(bug.heading, desired, turnRate, dt)
	bug.speed += (targetSpeed - bug.speed) * math.min(1, dt * 4)
	here += bug.heading * bug.speed * dt

	if now >= bug.nextGroundCheck then
		bug.ground = groundHeight(here + Vector3.new(0, bug.position.Y, 0))
		bug.nextGroundCheck = now + 0.25
	end

	local y
	if bug.flying then
		bug.lift += ((fleeing and 1 or 0) - bug.lift) * math.min(1, dt * 2)
		if bug.leaving then
			bug.altitude += dt * 5
		end
		y = bug.ground + bug.altitude + bug.lift + math.sin(now * 0.9 + bug.phase) * 0.8
	else
		y = bug.ground + BugBuilder.groundOffset(info)
	end
	bug.position = Vector3.new(here.X, y, here.Z)
	return CFrame.lookAt(bug.position, bug.position + bug.heading)
end

-- Rare bugs leave at sunrise and Epic bugs leave when the rain stops, a few at a time.
local function updateLeaving(now, night, raining)
	for _, bug in bugs do
		local rarity = bug.info.Rarity
		local belongs = (rarity ~= "Rare" or night) and (rarity ~= "Epic" or raining)
		if bug.leaving then
			if now >= bug.goneAt then
				removeBug(bug, false)
			end
		elseif not belongs then
			bug.leaveAt = bug.leaveAt or now + rng:NextNumber(0, 12)
			if now >= bug.leaveAt then
				bug.leaving = true
				bug.goneAt = now + (bug.flying and 4 or 0)
			end
		else
			bug.leaveAt = nil
		end
	end
end

local function trySpawn(rarity, chance, positions)
	if counts[rarity] < maxCounts[rarity] and rng:NextNumber() < chance then
		local options = BugData.ByRarity[rarity]
		spawnBug(options[rng:NextInteger(1, #options)], positions)
	end
end

local function spawnTick()
	local positions = playerPositions()
	trySpawn("Common", 1, positions)
	if Environment.isNight() then
		trySpawn("Rare", 0.6, positions)
	end
	if Environment.isRaining() then
		trySpawn("Epic", 0.6, positions)
	end
end

-- ------------------------------------------------------------------ the net

local netTemplate = NetBuilder.build(Config)
netTemplate.Parent = StarterPack -- copied into each player's backpack when they spawn

local lastSwing = {} -- [player] = os.clock() of their last accepted swing

-- Catches every bug inside the net's reach: a cylinder just in front of the player.
local function swingNet(player, root)
	if not root.Parent then
		return
	end
	local look = flat(root.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		return
	end
	look = look.Unit
	local center = root.Position + look * Config.NetReach
	local netY = root.Position.Y - 1

	local caught = {}
	for _, bug in bugs do
		local sideways = (flat(bug.position) - flat(center)).Magnitude
		local inFront = flat(bug.position - root.Position):Dot(look) > -0.5
		if sideways <= Config.NetRadius and math.abs(bug.position.Y - netY) <= Config.NetHeight and inFront then
			table.insert(caught, bug)
		end
	end
	for _, bug in caught do
		removeBug(bug, true)
		local isNew, count = Collection.add(player, bug.info.Id)
		remote:FireClient(player, "Caught", bug.info.Id, isNew, count)
	end
end

remote.OnServerEvent:Connect(function(player, action)
	if action ~= "Swing" then
		return
	end
	local now = os.clock()
	if now - (lastSwing[player] or 0) < Config.SwingCooldown * 0.8 then
		return -- swinging faster than the net allows
	end
	local character = player.Character
	local tool = character and character:FindFirstChild(Config.NetName)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (tool and tool:IsA("Tool") and root and humanoid and humanoid.Health > 0) then
		return
	end
	lastSwing[player] = now

	-- Everyone else sees the swing; the swinger already animated it.
	for _, other in Players:GetPlayers() do
		if other ~= player then
			remote:FireClient(other, "Swing", player)
		end
	end
	-- Check when the net comes down, a moment into the swing.
	task.delay(0.18, swingNet, player, root)
end)

local function onPlayerAdded(player)
	Collection.setup(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and not backpack:FindFirstChild(Config.NetName) and not (player.Character and player.Character:FindFirstChild(Config.NetName)) then
		netTemplate:Clone().Parent = backpack
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	lastSwing[player] = nil
	Collection.release(player) -- saves their Bug Book
end)

-- ------------------------------------------------------------------ main loop

-- Fill the meadow with common bugs right away.
for _ = 1, Config.MaxCommonBugs do
	trySpawn("Common", 1, {})
end

local spawnTimer = 0
local leaveTimer = 0
RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
	local now = os.clock()

	spawnTimer -= dt
	if spawnTimer <= 0 then
		spawnTimer = Config.SpawnInterval
		spawnTick()
	end
	leaveTimer -= dt
	if leaveTimer <= 0 then
		leaveTimer = 0.5
		updateLeaving(now, Environment.isNight(), Environment.isRaining())
	end

	local positions = playerPositions()
	local parts, cframes = {}, {}
	for part, bug in bugs do
		table.insert(parts, part)
		table.insert(cframes, updateBug(bug, now, dt, positions))
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
