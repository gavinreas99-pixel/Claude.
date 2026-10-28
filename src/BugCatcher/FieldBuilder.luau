--[[
	FieldBuilder

	Builds the meadow: a flat grass field (Terrain) ringed by rolling hills,
	with patches of darker grass, flowers, bushes, rocks and trees. Ground
	level inside the field is y = 0. Everything is generated from Config.Seed,
	so every server gets the same layout.

	Usage (server):
		FieldBuilder.build(Config)
]]

local Workspace = game:GetService("Workspace")

local Util = require(script.Parent:WaitForChild("Util"))
local create, decor, ellipsoid, upright = Util.create, Util.decor, Util.ellipsoid, Util.upright

local FieldBuilder = {}

local FLOWERS = {
	{ name = "Daisy", petal = Color3.fromRGB(250, 250, 244), center = Color3.fromRGB(250, 200, 40), height = { 1.1, 1.7 }, size = 1 },
	{ name = "Poppy", petal = Color3.fromRGB(222, 46, 38), center = Color3.fromRGB(40, 30, 30), height = { 1.4, 2.1 }, size = 1.05 },
	{ name = "Bluebell", petal = Color3.fromRGB(96, 110, 228), center = Color3.fromRGB(246, 226, 120), height = { 1, 1.5 }, size = 0.85 },
	{ name = "Cosmos", petal = Color3.fromRGB(246, 128, 186), center = Color3.fromRGB(250, 214, 70), height = { 1.5, 2.3 }, size = 1.1 },
	{ name = "Buttercup", petal = Color3.fromRGB(255, 214, 40), center = Color3.fromRGB(226, 160, 20), height = { 0.9, 1.4 }, size = 0.8 },
	{ name = "Sunflower", petal = Color3.fromRGB(255, 196, 22), center = Color3.fromRGB(92, 56, 26), height = { 3.6, 4.6 }, size = 2.1 },
}

local STEM_COLOR = Color3.fromRGB(70, 130, 50)

-- A random point inside a ring around the origin, spread evenly over its area.
local function randomPoint(rng, minRadius, maxRadius)
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(rng:NextNumber((minRadius / maxRadius) ^ 2, 1)) * maxRadius
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

-- The terrain height under a point (the field itself is flat at 0; hills aren't).
local function groundAt(point)
	groundParams.FilterDescendantsInstances = { Workspace.Terrain }
	local result = Workspace:Raycast(Vector3.new(point.X, 200, point.Z), Vector3.new(0, -400, 0), groundParams)
	return Vector3.new(point.X, result and result.Position.Y or 0, point.Z)
end

local function buildTerrain(config, rng)
	local terrain = Workspace.Terrain
	local radius = config.FieldRadius

	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(96, 148, 60))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(76, 126, 50))

	-- The ground: a 16-stud thick slab whose top sits exactly on y = 0 (voxels are 4 studs).
	local size = (radius + 180) * 2
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(size, 16, size), Enum.Material.Grass)

	-- Patches of darker, leafier grass. ReplaceMaterial only repaints, so the ground stays flat.
	for _ = 1, 16 do
		local center = randomPoint(rng, 0, radius)
		for _ = 1, 4 do
			local offset = Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
			local half = Vector3.new(rng:NextNumber(5, 12), 2, rng:NextNumber(5, 12))
			local region = Region3.new(center + offset - half - Vector3.new(0, 2, 0), center + offset + half)
			terrain:ReplaceMaterial(region:ExpandToGrid(4), 4, Enum.Material.Grass, Enum.Material.LeafyGrass)
		end
	end

	-- Two rings of rolling hills around the meadow.
	for ring = 1, 2 do
		local count = ring == 1 and 34 or 26
		for i = 1, count do
			local angle = (i + rng:NextNumber(-0.4, 0.4)) / count * math.pi * 2
			local hillRadius = ring == 1 and rng:NextNumber(18, 34) or rng:NextNumber(36, 58)
			local distance = radius + (ring == 1 and rng:NextNumber(30, 55) or rng:NextNumber(85, 120))
			local center = Vector3.new(math.cos(angle) * distance, -hillRadius * 0.55, math.sin(angle) * distance)
			terrain:FillBall(center, hillRadius, Enum.Material.Grass)
		end
	end
end

local function buildTree(parent, rng, position)
	local model = create("Model", { Name = "Tree" })
	local height = rng:NextNumber(11, 18)
	local width = rng:NextNumber(1.3, 2)
	local birch = rng:NextNumber() < 0.25
	local bark = birch and Color3.fromRGB(226, 222, 210) or Color3.fromRGB(102, 74, 50)

	local trunk = decor({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height + 1, width, width),
		CFrame = upright(position + Vector3.new(0, height / 2 - 0.5, 0)),
		Material = Enum.Material.Wood,
		Color = bark,
		CanCollide = true,
		CanQuery = true,
		Parent = model,
	})
	model.PrimaryPart = trunk
	decor({
		Name = "Flare",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, width * 1.35, width * 1.35),
		CFrame = upright(position + Vector3.new(0, 0.3, 0)),
		Material = Enum.Material.Wood,
		Color = bark,
		Parent = model,
	})

	-- Two branches reaching up into the leaves.
	for i = 1, 2 do
		local yaw = rng:NextNumber(0, math.pi * 2) + i * math.pi
		local base = position + Vector3.new(0, height * rng:NextNumber(0.55, 0.7), 0)
		local branch = CFrame.new(base) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(55))
		decor({
			Name = "Branch",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(4.5, width * 0.45, width * 0.45),
			CFrame = branch * CFrame.new(2, 0, 0),
			Material = Enum.Material.Wood,
			Color = bark,
			Parent = model,
		})
	end

	-- A cloud of leaf balls on top.
	local hue = birch and rng:NextNumber(0.2, 0.24) or rng:NextNumber(0.24, 0.3)
	local top = position + Vector3.new(0, height, 0)
	local leafCount = rng:NextInteger(5, 7)
	for i = 1, leafCount do
		local size = i == 1 and rng:NextNumber(9, 12) or rng:NextNumber(6, 9)
		local offset = i == 1 and Vector3.zero
			or Vector3.new(rng:NextNumber(-3.8, 3.8), rng:NextNumber(-2.2, 2), rng:NextNumber(-3.8, 3.8))
		decor({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			CFrame = CFrame.new(top + offset),
			Material = Enum.Material.LeafyGrass,
			Color = Color3.fromHSV(hue + rng:NextNumber(-0.02, 0.02), rng:NextNumber(0.5, 0.65), rng:NextNumber(0.42, 0.56)),
			Parent = model,
		})
	end
	model.Parent = parent
end

local function buildBush(parent, rng, position)
	local model = create("Model", { Name = "Bush" })
	local hue = rng:NextNumber(0.23, 0.3)
	for _ = 1, rng:NextInteger(2, 4) do
		local size = rng:NextNumber(3, 5.5)
		local offset = Vector3.new(rng:NextNumber(-1.8, 1.8), size * 0.22, rng:NextNumber(-1.8, 1.8))
		decor({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			CFrame = CFrame.new(position + offset),
			Material = Enum.Material.LeafyGrass,
			Color = Color3.fromHSV(hue, rng:NextNumber(0.5, 0.65), rng:NextNumber(0.4, 0.52)),
			Parent = model,
		})
	end
	model.Parent = parent
end

local function buildRock(parent, rng, position)
	local size = Vector3.new(rng:NextNumber(2.5, 6), rng:NextNumber(1.6, 3.2), rng:NextNumber(2.5, 5))
	local grey = rng:NextNumber(105, 135)
	ellipsoid(decor({
		Name = "Rock",
		Size = size,
		CFrame = CFrame.new(position + Vector3.new(0, size.Y * 0.2, 0))
			* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.2, 0.2)),
		Material = Enum.Material.Rock,
		Color = Color3.fromRGB(grey, grey - 2, grey - 8),
		CanCollide = true,
		CastShadow = true,
		Parent = parent,
	}))
end

local function buildFlower(parent, rng, species, position)
	local model = create("Model", { Name = species.name })
	local height = rng:NextNumber(species.height[1], species.height[2])
	local s = species.size * rng:NextNumber(0.85, 1.15)
	local tilt = CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
	local base = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * tilt

	decor({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 0.12 * math.max(1, s * 0.8), 0.12 * math.max(1, s * 0.8)),
		CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = STEM_COLOR,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
		Parent = model,
	})
	ellipsoid(decor({
		Name = "Leaf",
		Size = Vector3.new(0.55, 0.05, 0.22) * math.max(1, s * 0.8),
		CFrame = base * CFrame.new(0.22, height * 0.35, 0) * CFrame.Angles(0, 0, math.rad(25)),
		Color = STEM_COLOR,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
		Parent = model,
	}))

	-- The head faces the sky. Three crossing petal ovals make six petals.
	local head = base * CFrame.new(0, height, 0) * CFrame.Angles(math.rad(-15), 0, 0)
	for i = 0, 2 do
		ellipsoid(decor({
			Name = "Petals",
			Size = Vector3.new(0.3 * s, 0.07 * s, 1.15 * s),
			CFrame = head * CFrame.Angles(0, i * math.pi / 3, 0),
			Color = species.petal,
			Material = Enum.Material.SmoothPlastic,
			CastShadow = false,
			Parent = model,
		}))
	end
	ellipsoid(decor({
		Name = "Center",
		Size = Vector3.new(0.38, 0.18, 0.38) * s,
		CFrame = head * CFrame.new(0, 0.04 * s, 0),
		Color = species.center,
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
		Parent = model,
	}))
	model.Parent = parent
end

-- A tuft of long grass blades leaning out in all directions.
local function buildTuft(parent, rng, position)
	local model = create("Model", { Name = "Grass" })
	local hue = rng:NextNumber(0.24, 0.29)
	for i = 1, 4 do
		local height = rng:NextNumber(1.2, 2.4)
		local yaw = i / 4 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local lean = rng:NextNumber(0.15, 0.45)
		decor({
			Name = "Blade",
			Size = Vector3.new(0.06, height, 0.32),
			CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(lean, 0, 0) * CFrame.new(0, height / 2, 0),
			Color = Color3.fromHSV(hue, rng:NextNumber(0.5, 0.65), rng:NextNumber(0.5, 0.62)),
			Material = Enum.Material.SmoothPlastic,
			CastShadow = false,
			Parent = model,
		})
	end
	model.Parent = parent
end

-- An invisible wall far out in the hills so nobody walks off the edge of the world.
local function buildBoundary(parent, radius)
	local count = 48
	local distance = radius + 150
	local width = 2 * math.pi * distance / count + 4
	for i = 1, count do
		local angle = i / count * math.pi * 2
		local position = Vector3.new(math.cos(angle) * distance, 60, math.sin(angle) * distance)
		create("Part", {
			Name = "Wall",
			Anchored = true,
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Size = Vector3.new(width, 160, 4),
			CFrame = CFrame.lookAt(position, Vector3.new(0, 60, 0)),
			Parent = parent,
		})
	end
end

function FieldBuilder.build(config)
	local rng = Random.new(config.Seed)
	local radius = config.FieldRadius

	local old = Workspace:FindFirstChild("BugField")
	if old then
		old:Destroy()
	end
	if config.RemoveBaseplate then
		local baseplate = Workspace:FindFirstChild("Baseplate")
		if baseplate and baseplate:IsA("BasePart") then
			baseplate:Destroy()
		end
	end

	buildTerrain(config, rng)

	local root = create("Folder", { Name = "BugField" })
	local trees = create("Folder", { Name = "Trees", Parent = root })
	local plants = create("Folder", { Name = "Plants", Parent = root })
	local flowers = create("Folder", { Name = "Flowers", Parent = root })
	buildBoundary(create("Folder", { Name = "Boundary", Parent = root }), radius)

	-- Trees keep their distance from each other and from the spawn in the middle.
	local placed = {}
	for _ = 1, config.TreeCount do
		for _ = 1, 30 do
			local point = randomPoint(rng, 30, radius + 45)
			local free = true
			for _, other in placed do
				if (other - point).Magnitude < 16 then
					free = false
					break
				end
			end
			if free then
				table.insert(placed, point)
				buildTree(trees, rng, groundAt(point))
				break
			end
		end
	end

	for _ = 1, config.BushCount do
		buildBush(plants, rng, groundAt(randomPoint(rng, 14, radius + 30)))
	end
	for _ = 1, config.RockCount do
		buildRock(plants, rng, groundAt(randomPoint(rng, 18, radius + 30)))
	end

	for _ = 1, config.GrassTufts do
		buildTuft(plants, rng, randomPoint(rng, 6, radius))
	end

	-- Flowers grow in patches of one kind, like a real meadow.
	for _ = 1, config.FlowerPatches do
		local species = FLOWERS[rng:NextInteger(1, #FLOWERS)]
		local center = randomPoint(rng, 8, radius - 5)
		local spread = rng:NextNumber(4, 9)
		local count = species.name == "Sunflower" and rng:NextInteger(3, 6) or rng:NextInteger(7, 14)
		for _ = 1, count do
			local offset = randomPoint(rng, 0, spread)
			buildFlower(flowers, rng, species, center + offset)
		end
	end

	root.Parent = Workspace
	return root
end

return FieldBuilder
