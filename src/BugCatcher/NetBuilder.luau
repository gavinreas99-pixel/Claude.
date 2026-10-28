--[[
	NetBuilder: builds the bug net Tool.

	Layout (the Handle's own space): the pole runs along +Y, the hand holds
	it 1 stud below the Handle's centre, and the hoop sits on top facing -Z
	with the mesh bag trailing behind it (+Z). Tool.Grip tilts the pole
	forward so the net is held up and ready.

	Usage (server):
		local net = NetBuilder.build(Config)
		net.Parent = game:GetService("StarterPack")
]]

local Util = require(script.Parent:WaitForChild("Util"))
local create, ellipsoid = Util.create, Util.ellipsoid

local NetBuilder = {}

local WOOD = Color3.fromRGB(150, 104, 62)
local GRIP = Color3.fromRGB(70, 46, 34)
local METAL = Color3.fromRGB(200, 204, 210)
local MESH = Color3.fromRGB(246, 246, 238)

local POLE_LENGTH = 4.6
local HOOP_RADIUS = 1.15
NetBuilder.HoopCenter = Vector3.new(0, POLE_LENGTH / 2 + HOOP_RADIUS, 0)

function NetBuilder.build(config)
	local tool = create("Tool", {
		Name = config.NetName,
		ToolTip = "Click or tap to swing",
		CanBeDropped = false,
		RequiresHandle = true,
		-- Hold the pole leaning 55 degrees forward, gripped 1 stud below its middle.
		Grip = (CFrame.Angles(math.rad(-55), 0, 0) * CFrame.new(0, 1, 0)):Inverse(),
	})

	local handle = create("Part", {
		Name = "Handle",
		Size = Vector3.new(0.2, POLE_LENGTH, 0.2),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CFrame = CFrame.identity,
		Parent = tool,
	})

	local function piece(props)
		local part = create("Part", {
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Massless = true,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
		})
		for key, value in props do
			part[key] = value
		end
		part.Parent = tool
		create("WeldConstraint", { Part0 = handle, Part1 = part, Parent = part })
		return part
	end

	local alongY = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's X axis to +Y

	piece({
		Name = "Pole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(POLE_LENGTH, 0.2, 0.2),
		CFrame = alongY,
		Color = WOOD,
		Material = Enum.Material.Wood,
	})
	piece({
		Name = "GripWrap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.1, 0.27, 0.27),
		CFrame = CFrame.new(0, -1, 0) * alongY,
		Color = GRIP,
		Material = Enum.Material.Fabric,
	})
	piece({
		Name = "EndCap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.3,
		CFrame = CFrame.new(0, -POLE_LENGTH / 2, 0),
		Color = GRIP,
	})
	piece({
		Name = "Collar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 0.26, 0.26),
		CFrame = CFrame.new(0, POLE_LENGTH / 2 - 0.1, 0) * alongY,
		Color = METAL,
		Material = Enum.Material.Metal,
	})

	-- The hoop: a ring of short metal segments.
	local center = NetBuilder.HoopCenter
	local segments = 18
	for i = 1, segments do
		local angle = i / segments * math.pi * 2
		local position = center + Vector3.new(math.cos(angle), math.sin(angle), 0) * HOOP_RADIUS
		piece({
			Name = "Hoop",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2 * math.pi * HOOP_RADIUS / segments * 1.12, 0.11, 0.11),
			CFrame = CFrame.new(position) * CFrame.Angles(0, 0, angle + math.pi / 2),
			Color = METAL,
			Material = Enum.Material.Metal,
		})
	end

	-- The mesh bag trails behind the hoop: a wide mouth tapering to a drooping tip.
	for _, bag in {
		{ name = "Bag", size = Vector3.new(HOOP_RADIUS * 1.9, HOOP_RADIUS * 1.9, 1.3), offset = Vector3.new(0, -0.05, 0.5) },
		{ name = "BagTip", size = Vector3.new(1.25, 1.2, 1.7), offset = Vector3.new(0, -0.35, 1.3) },
	} do
		ellipsoid(piece({
			Name = bag.name,
			Size = bag.size,
			CFrame = CFrame.new(center + bag.offset),
			Color = MESH,
			Material = Enum.Material.Fabric,
			Transparency = 0.4,
			CastShadow = false,
		}))
	end

	-- A faint swoosh trail drawn by the hoop during a swing (switched on by NetClient).
	local a0 = create("Attachment", { Name = "TrailBottom", Position = center - Vector3.new(0, HOOP_RADIUS, 0), Parent = handle })
	local a1 = create("Attachment", { Name = "TrailTop", Position = center + Vector3.new(0, HOOP_RADIUS, 0), Parent = handle })
	create("Trail", {
		Name = "SwingTrail",
		Attachment0 = a0,
		Attachment1 = a1,
		Enabled = false,
		Lifetime = 0.18,
		MinLength = 0.05,
		FaceCamera = true,
		LightEmission = 0.3,
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Parent = handle,
	})

	create("Sound", {
		Name = "SwingSound",
		SoundId = config.Sounds.Swing,
		Volume = 0.55,
		PlaybackSpeed = 1.25,
		RollOffMaxDistance = 60,
		Parent = handle,
	})

	return tool
end

return NetBuilder
