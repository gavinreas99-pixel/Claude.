--[[
	BugBuilder

	Draws a bug out of small rounded parts. Each bug faces -Z with its body
	centre at the origin. Moving parts (wings, legs, antennae, worm segments)
	are recorded with the hinge they turn around, so BugVisuals can flap and
	scuttle them every frame without any joints or physics.

	Usage:
		local rig = BugBuilder.build(BugData.ById.Ladybug, { effects = true })
		rig.model.Parent = workspace
		-- rig.parts: { part, rel, kind, side, hinge, phase, index }
		-- rig.glow / rig.rainbow: parts to pulse or recolour, rig.light: PointLight or nil

	BugBuilder.groundOffset(bug) is how high a crawling bug's centre sits
	above the ground; the server uses it too, so it builds nothing on require.
]]

local Util = require(script.Parent:WaitForChild("Util"))
local BugData = require(script.Parent:WaitForChild("BugData"))
local create, ellipsoid = Util.create, Util.ellipsoid

local BugBuilder = {}

local SIZE = 1.3 -- a Scale 1 bug's body is about 1.3 studs long

local SHAPE_HEIGHT = {
	Beetle = 0.38,
	Bee = 0.38,
	Butterfly = 0.1,
	Dragonfly = 0.12,
	Hopper = 0.36,
	Ant = 0.3,
	Worm = 0.16,
}

local DARK = Color3.fromRGB(22, 20, 24)
local WHITE = Color3.fromRGB(245, 245, 240)

local V = Vector3.new

function BugBuilder.scale(bug)
	return SIZE * bug.Scale
end

function BugBuilder.groundOffset(bug)
	return (SHAPE_HEIGHT[bug.Shape] or 0.3) * BugBuilder.scale(bug)
end

local function scaled(cf, s)
	return CFrame.new(cf.Position * s) * cf.Rotation
end

-- A CFrame at `from` whose X axis (a cylinder's length) points at `to`.
local function along(from, to)
	local direction = to - from
	local up = math.abs(direction.Unit.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
	return CFrame.lookAt((from + to) / 2, to, up) * CFrame.Angles(0, math.pi / 2, 0)
end

local function add(rig, spec)
	local s = rig.scale
	local cf = scaled(spec.cf, s)
	local transparency = spec.transparency or 0
	local part = create("Part", {
		Name = spec.name or "Part",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CastShadow = transparency < 0.3,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Size = spec.size * s,
		CFrame = cf,
		Color = spec.color,
		Material = spec.material or Enum.Material.SmoothPlastic,
		Transparency = transparency,
		Reflectance = spec.reflectance or 0,
	})
	if spec.shape == "cyl" then
		part.Shape = Enum.PartType.Cylinder
	elseif spec.shape ~= "block" then
		ellipsoid(part)
	end
	part.Parent = rig.model
	if not rig.model.PrimaryPart then
		rig.model.PrimaryPart = part
	end

	local hinge = spec.hinge and scaled(spec.hinge, s)
	table.insert(rig.parts, {
		part = part,
		rel = hinge and hinge:Inverse() * cf or cf,
		kind = spec.kind,
		side = spec.side or 1,
		hinge = hinge,
		phase = spec.phase or 0,
		index = spec.index or 0,
	})
	if spec.glow then
		table.insert(rig.glow, part)
	end
	if spec.rainbow then
		table.insert(rig.rainbow, part)
	end
	return part
end

-- A thin cylinder from one point to another (legs, antennae).
local function limb(rig, from, to, thickness, color, kind, side, phase)
	return add(rig, {
		name = kind == "antenna" and "Antenna" or "Leg",
		shape = "cyl",
		size = V((to - from).Magnitude, thickness, thickness),
		cf = along(from, to),
		color = color,
		kind = kind,
		side = side,
		hinge = CFrame.new(from),
		phase = phase,
	})
end

local function antennae(rig, from, to, color, club)
	for _, side in { -1, 1 } do
		local a = V(from.X * side, from.Y, from.Z)
		local b = V(to.X * side, to.Y, to.Z)
		limb(rig, a, b, 0.03, color, "antenna", side, side)
		if club then
			add(rig, { name = "Club", size = V(0.07, 0.07, 0.1), cf = CFrame.new(b), color = color, kind = "antenna", side = side, hinge = CFrame.new(a), phase = side })
		end
	end
end

-- Six legs in two rows. `rows` = { { z, reachZ }, ... } front to back.
local function sixLegs(rig, hipX, hipY, footX, footY, rows, thickness, color)
	for i, row in rows do
		for _, side in { -1, 1 } do
			local hip = V(hipX * side, hipY, row[1])
			local foot = V(footX * side, footY, row[1] + row[2])
			-- Tripod gait: front and back legs on one side move with the middle leg on the other.
			local phase = ((i + (side > 0 and 1 or 0)) % 2) * math.pi
			limb(rig, hip, foot, thickness, color, "leg", side, phase)
		end
	end
end

local function wing(rig, spec, side)
	spec.name = spec.name or "Wing"
	spec.kind = "wing"
	spec.side = side
	return add(rig, spec)
end

local BUILDERS = {}

function BUILDERS.Beetle(rig, bug)
	local c = bug.Colors
	add(rig, { name = "Body", size = V(0.7, 0.3, 0.85), cf = CFrame.new(0, -0.08, 0.04), color = c.Body })
	add(rig, {
		name = "Shell",
		size = V(0.82, 0.5, 0.95),
		cf = CFrame.new(0, 0.05, 0.06),
		color = c.Shell,
		reflectance = bug.Rainbow and 0.25 or 0.05,
		rainbow = bug.Rainbow,
	})
	add(rig, { name = "Seam", shape = "block", size = V(0.025, 0.03, 0.6), cf = CFrame.new(0, 0.29, 0.12), color = c.Accent })
	add(rig, { name = "Head", size = V(0.42, 0.3, 0.3), cf = CFrame.new(0, -0.02, -0.46), color = c.Body })

	if bug.Spots then
		-- Spots sit on the shell surface, tilted to follow its curve.
		local a, b, cz = 0.41, 0.25, 0.475
		for _, spot in { { 0.2, -0.12 }, { 0.27, 0.18 }, { 0.12, 0.42 } } do
			for _, side in { -1, 1 } do
				local x, z = spot[1] * side, spot[2]
				local u = (x / a) ^ 2 + ((z - 0.06) / cz) ^ 2
				local y = 0.05 + b * math.sqrt(math.max(0, 1 - u))
				local position = V(x, y - 0.01, z)
				local normal = V(x / a ^ 2, (y - 0.05) / b ^ 2, (z - 0.06) / cz ^ 2).Unit
				add(rig, {
					name = "Spot",
					size = V(0.17, 0.06, 0.17),
					cf = CFrame.lookAt(position, position + normal) * CFrame.Angles(-math.pi / 2, 0, 0),
					color = c.Accent,
				})
			end
		end
		for _, side in { -1, 1 } do
			add(rig, { name = "Cheek", size = V(0.1, 0.06, 0.08), cf = CFrame.new(0.12 * side, 0.08, -0.53), color = WHITE })
		end
	end

	antennae(rig, V(0.08, 0.05, -0.58), V(0.18, 0.18, -0.78), c.Body, false)
	sixLegs(rig, 0.28, -0.12, 0.48, -0.38, { { -0.22, -0.1 }, { 0.04, 0 }, { 0.3, 0.1 } }, 0.045, c.Body)
end

function BUILDERS.Bee(rig, bug)
	local c = bug.Colors
	local firefly = c.Glow ~= nil
	add(rig, { name = "Body", size = V(0.42, 0.4, 0.42), cf = CFrame.new(0, 0.02, -0.08), color = c.Fuzz, material = Enum.Material.Fabric })
	add(rig, { name = "Abdomen", size = V(0.44, 0.42, 0.68), cf = CFrame.new(0, -0.02, 0.36), color = c.Body })
	if firefly then
		add(rig, { name = "Lantern", size = V(0.36, 0.34, 0.3), cf = CFrame.new(0, -0.04, 0.6), color = c.Glow, material = Enum.Material.Neon, glow = true })
	else
		-- Stripes: thin rings just proud of the abdomen's surface.
		for _, z in { 0.3, 0.46, 0.6 } do
			local k = math.sqrt(1 - ((z - 0.36) / 0.34) ^ 2)
			add(rig, { name = "Stripe", size = V(0.44 * k + 0.025, 0.42 * k + 0.025, 0.08), cf = CFrame.new(0, -0.02, z), color = c.Accent })
		end
	end
	add(rig, { name = "Head", size = V(0.32, 0.3, 0.26), cf = CFrame.new(0, 0.03, -0.38), color = c.Accent })
	for _, side in { -1, 1 } do
		add(rig, { name = "Eye", size = V(0.13, 0.15, 0.12), cf = CFrame.new(0.12 * side, 0.06, -0.44), color = DARK, reflectance = 0.2 })
	end
	antennae(rig, V(0.06, 0.15, -0.46), V(0.14, 0.32, -0.62), DARK, false)
	for _, side in { -1, 1 } do
		local transparency = firefly and 0.15 or 0.45
		wing(rig, {
			size = V(0.62, 0.02, 0.26),
			cf = CFrame.new(0.34 * side, 0.24, 0.02) * CFrame.Angles(0, -0.35 * side, 0),
			color = c.Wing,
			transparency = transparency,
			hinge = CFrame.new(0.05 * side, 0.22, -0.06),
		}, side)
		wing(rig, {
			size = V(0.42, 0.02, 0.2),
			cf = CFrame.new(0.26 * side, 0.22, 0.16) * CFrame.Angles(0, -0.6 * side, 0),
			color = c.Wing,
			transparency = transparency,
			hinge = CFrame.new(0.05 * side, 0.22, -0.06),
		}, side)
	end
	sixLegs(rig, 0.14, -0.15, 0.24, -0.38, { { -0.14, 0.05 }, { -0.02, 0.05 }, { 0.1, 0.05 } }, 0.035, DARK)
end

function BUILDERS.Butterfly(rig, bug)
	local c = bug.Colors
	local wingMaterial = bug.Crystal and Enum.Material.Glass or Enum.Material.SmoothPlastic
	local wingTransparency = bug.Crystal and 0.3 or 0
	add(rig, { name = "Body", size = V(0.13, 0.13, 0.72), cf = CFrame.new(0, 0, 0.04), color = c.Body, material = Enum.Material.Fabric })
	add(rig, { name = "Head", size = V(0.17, 0.16, 0.16), cf = CFrame.new(0, 0.02, -0.36), color = c.Body })
	antennae(rig, V(0.04, 0.06, -0.42), V(0.16, 0.26, -0.72), c.Body, true)

	for _, side in { -1, 1 } do
		local foreHinge = CFrame.new(0.05 * side, 0.03, -0.05)
		local hindHinge = CFrame.new(0.05 * side, 0.01, 0.08)
		local fore = CFrame.new(0.42 * side, 0.03, -0.1) * CFrame.Angles(0, 0.3 * side, 0)
		local hind = CFrame.new(0.32 * side, 0.01, 0.2) * CFrame.Angles(0, -0.45 * side, 0)
		wing(rig, { size = V(0.78, 0.025, 0.56), cf = fore, color = c.Wing, material = wingMaterial, transparency = wingTransparency, hinge = foreHinge, glow = bug.Crystal }, side)
		wing(rig, { size = V(0.58, 0.025, 0.48), cf = hind, color = c.Wing, material = wingMaterial, transparency = wingTransparency, hinge = hindHinge, glow = bug.Crystal }, side)

		if bug.Tails then
			-- Luna moth: eyespots and long trailing tails.
			wing(rig, { name = "Eyespot", size = V(0.13, 0.03, 0.13), cf = hind * CFrame.new(0.02 * side, 0.004, 0), color = c.Accent, hinge = hindHinge }, side)
			wing(rig, { name = "Tail", size = V(0.1, 0.025, 0.62), cf = hind * CFrame.new(0.06 * side, 0, 0.42), color = c.Wing, hinge = hindHinge }, side)
		elseif bug.Crystal then
			wing(rig, { name = "Shine", size = V(0.3, 0.03, 0.2), cf = fore * CFrame.new(0.12 * side, 0.004, -0.04), color = c.Accent, material = Enum.Material.Neon, transparency = 0.4, hinge = foreHinge, glow = true }, side)
		else
			-- Cabbage white: dark wing tips and a spot.
			wing(rig, { name = "Tip", size = V(0.26, 0.03, 0.2), cf = fore * CFrame.new(0.26 * side, 0.004, -0.09), color = c.Accent, hinge = foreHinge }, side)
			wing(rig, { name = "Dot", size = V(0.1, 0.03, 0.1), cf = fore * CFrame.new(0.06 * side, 0.004, 0.08), color = c.Accent, hinge = foreHinge }, side)
		end
	end
end

function BUILDERS.Dragonfly(rig, bug)
	local c = bug.Colors
	local storm = c.Glow ~= nil
	add(rig, { name = "Body", size = V(0.22, 0.24, 0.36), cf = CFrame.new(0, 0, -0.2), color = c.Body })
	add(rig, { name = "Tail", size = V(0.1, 0.1, 1.25), cf = CFrame.new(0, 0, 0.58), color = c.Body, reflectance = 0.15 })
	for _, z in { 0.25, 0.5, 0.75, 0.98 } do
		local k = math.sqrt(1 - ((z - 0.58) / 0.625) ^ 2)
		add(rig, {
			name = "Ring",
			size = V(0.1 * k + 0.02, 0.1 * k + 0.02, 0.06),
			cf = CFrame.new(0, 0, z),
			color = storm and c.Glow or c.Accent,
			material = storm and Enum.Material.Neon or Enum.Material.SmoothPlastic,
			glow = storm,
		})
	end
	add(rig, { name = "Head", size = V(0.26, 0.22, 0.2), cf = CFrame.new(0, 0.02, -0.44), color = c.Body })
	for _, side in { -1, 1 } do
		add(rig, { name = "Eye", size = V(0.17, 0.17, 0.17), cf = CFrame.new(0.09 * side, 0.05, -0.47), color = c.Accent, reflectance = 0.25 })
		wing(rig, {
			size = V(1, 0.02, 0.17),
			cf = CFrame.new(0.54 * side, 0.13, -0.28) * CFrame.Angles(0, 0.08 * side, 0),
			color = c.Wing,
			transparency = 0.55,
			hinge = CFrame.new(0.06 * side, 0.12, -0.26),
		}, side)
		wing(rig, {
			size = V(0.95, 0.02, 0.2),
			cf = CFrame.new(0.52 * side, 0.13, -0.08) * CFrame.Angles(0, -0.1 * side, 0),
			color = c.Wing,
			transparency = 0.55,
			hinge = CFrame.new(0.06 * side, 0.12, -0.1),
			phase = math.pi / 2,
		}, side)
	end
end

function BUILDERS.Hopper(rig, bug)
	local c = bug.Colors
	add(rig, { name = "Body", size = V(0.3, 0.32, 0.95), cf = CFrame.new(0, 0.04, 0.08), color = c.Body })
	add(rig, { name = "Head", size = V(0.28, 0.36, 0.3), cf = CFrame.new(0, 0.12, -0.46) * CFrame.Angles(0.4, 0, 0), color = c.Body })
	for _, side in { -1, 1 } do
		add(rig, { name = "Eye", size = V(0.1, 0.12, 0.1), cf = CFrame.new(0.12 * side, 0.2, -0.5), color = Color3.fromRGB(60, 44, 30) })
		add(rig, { name = "WingCover", size = V(0.2, 0.05, 0.75), cf = CFrame.new(0.08 * side, 0.18, 0.2), color = c.Accent })
		-- Big jumping legs: thigh up and back to a high knee, shin down to the ground.
		local hip = V(0.17 * side, 0.02, 0.05)
		local knee = V(0.22 * side, 0.3, 0.45)
		local foot = V(0.25 * side, -0.36, 0.36)
		limb(rig, hip, knee, 0.12, c.Body, nil, side)
		limb(rig, knee, foot, 0.05, c.Accent, nil, side)
	end
	antennae(rig, V(0.05, 0.25, -0.56), V(0.16, 0.45, -0.95), c.Accent, false)
	for i, z in { -0.3, -0.1 } do
		for _, side in { -1, 1 } do
			local phase = ((i + (side > 0 and 1 or 0)) % 2) * math.pi
			limb(rig, V(0.14 * side, -0.06, z), V(0.32 * side, -0.36, z - 0.06), 0.045, c.Accent, "leg", side, phase)
		end
	end
end

function BUILDERS.Ant(rig, bug)
	local c = bug.Colors
	add(rig, { name = "Body", size = V(0.18, 0.18, 0.36), cf = CFrame.new(0, 0.02, -0.15), color = c.Body, reflectance = 0.1 })
	add(rig, { name = "Head", size = V(0.3, 0.28, 0.3), cf = CFrame.new(0, 0.05, -0.48), color = c.Body, reflectance = 0.1 })
	add(rig, { name = "Waist", size = V(0.1, 0.1, 0.12), cf = CFrame.new(0, 0, 0.06), color = c.Body })
	add(rig, { name = "Abdomen", size = V(0.38, 0.36, 0.5), cf = CFrame.new(0, 0.06, 0.34), color = c.Body, reflectance = 0.15 })
	for _, side in { -1, 1 } do
		local base = V(0.06 * side, 0.15, -0.56)
		local elbow = V(0.16 * side, 0.3, -0.68)
		limb(rig, base, elbow, 0.03, c.Accent, "antenna", side, side)
		add(rig, {
			name = "Antenna",
			shape = "cyl",
			size = V(0.2, 0.03, 0.03),
			cf = along(elbow, V(0.2 * side, 0.22, -0.86)),
			color = c.Accent,
			kind = "antenna",
			side = side,
			hinge = CFrame.new(base),
			phase = side,
		})
	end
	sixLegs(rig, 0.08, -0.04, 0.42, -0.3, { { -0.24, -0.18 }, { -0.14, 0 }, { -0.04, 0.18 } }, 0.035, c.Accent)
end

function BUILDERS.Worm(rig, bug)
	local c = bug.Colors
	for i = 0, 6 do
		local radius = 0.17 - i * 0.012
		local glowing = i >= 4
		add(rig, {
			name = i == 0 and "Body" or "Segment",
			size = V(radius * 2, radius * 1.8, radius * 2.1),
			cf = CFrame.new(0, 0, -0.45 + i * 0.15),
			color = glowing and c.Glow or c.Body,
			material = glowing and Enum.Material.Neon or Enum.Material.SmoothPlastic,
			kind = "segment",
			index = i,
			glow = glowing,
		})
	end
	for _, side in { -1, 1 } do
		add(rig, { name = "Eye", size = V(0.05, 0.05, 0.05), cf = CFrame.new(0.07 * side, 0.07, -0.58), color = DARK, kind = "segment", index = 0 })
	end
end

-- Glowing bugs get a soft light, a faint halo and drifting sparkles.
local function addGlow(rig, bug)
	local glowColor = bug.Colors.Glow or BugData.Rarities[bug.Rarity].Color
	local body = rig.model.PrimaryPart
	-- Fireflies and glowworms glow from their tails; everything else from the body.
	local tail = rig.glow[1]
	local core = (tail and (tail.Name == "Lantern" or tail.Name == "Segment")) and tail or body
	rig.light = create("PointLight", {
		Color = glowColor,
		Brightness = 2,
		Range = 10,
		Shadows = false,
		Parent = core,
	})
	add(rig, {
		name = "Halo",
		size = V(1.2, 1.2, 1.2),
		cf = CFrame.new(core.Position / rig.scale),
		color = glowColor,
		material = Enum.Material.Neon,
		transparency = 0.9,
	})
	local attachment = create("Attachment", { Parent = body })
	create("ParticleEmitter", {
		Rate = 5,
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(0.4, 1),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18 * rig.scale), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(glowColor),
		LightEmission = 1,
		LightInfluence = 0,
		Parent = attachment,
	})
end

function BugBuilder.build(bug, options)
	local rig = {
		model = create("Model", { Name = bug.Name }),
		parts = {},
		glow = {},
		rainbow = {},
		scale = BugBuilder.scale(bug),
		bug = bug,
		light = nil,
	}
	BUILDERS[bug.Shape](rig, bug)
	if options and options.effects and BugData.Rarities[bug.Rarity].Glow then
		addGlow(rig, bug)
	end
	return rig
end

return BugBuilder
