--[[
	GoblinBuilder

	Builds a rigged Jade Jungle goblin (big head, long ears, droopy nose,
	red tunic, leather belts, spiked round shield and curved scimitar) out
	of rounded parts, joined with Motor6Ds so GoblinAnimator can make it
	run, swing its sword and flinch.

	Layout while building: feet on y = 0, facing -Z (Roblox "forward").
	Every joint pivot is axis-aligned, so in GoblinAnimator:
	  +X rotation swings a limb forward, -X leans the body forward,
	  Z rotation raises an arm/ear sideways, Y rotation twists.

	Usage:
		local goblin = GoblinBuilder.build({ scale = 1.1 })
		goblin:PivotTo(CFrame.new(groundPosition))
		goblin.Parent = workspace
]]

local GoblinBuilder = {}

local PALETTE = {
	Skin = Color3.fromRGB(158, 180, 62),
	SkinDark = Color3.fromRGB(116, 136, 42),
	SkinLight = Color3.fromRGB(184, 198, 88),
	EarInner = Color3.fromRGB(212, 126, 72),
	EarTip = Color3.fromRGB(206, 150, 70),
	EyeWhite = Color3.fromRGB(236, 222, 176),
	Iris = Color3.fromRGB(226, 136, 28),
	Pupil = Color3.fromRGB(22, 14, 10),
	Mouth = Color3.fromRGB(64, 38, 28),
	Tunic = Color3.fromRGB(198, 72, 36),
	TunicDark = Color3.fromRGB(148, 48, 26),
	Leather = Color3.fromRGB(104, 64, 40),
	LeatherDark = Color3.fromRGB(64, 40, 28),
	Pants = Color3.fromRGB(92, 58, 38),
	Boot = Color3.fromRGB(128, 82, 50),
	Sole = Color3.fromRGB(52, 38, 30),
	Wood = Color3.fromRGB(124, 82, 46),
	WoodDark = Color3.fromRGB(70, 44, 26),
	Iron = Color3.fromRGB(150, 152, 158),
	IronDark = Color3.fromRGB(62, 64, 70),
	Blade = Color3.fromRGB(58, 60, 66),
	BladeEdge = Color3.fromRGB(150, 156, 164),
	Gold = Color3.fromRGB(214, 164, 52),
}

local SKIN_KEYS = { "Skin", "SkinDark", "SkinLight" }
local TUNIC_KEYS = { "Tunic", "TunicDark" }

-- Shifts a group of colours together so each goblin looks a bit different.
local function shiftColors(colors, keys, hue, value)
	for _, key in keys do
		local h, s, v = colors[key]:ToHSV()
		colors[key] = Color3.fromHSV((h + hue) % 1, s, math.clamp(v + value, 0, 1))
	end
end

function GoblinBuilder.build(options)
	options = options or {}
	local S = options.scale or 1
	local rng = options.random or Random.new()

	local C = table.clone(PALETTE)
	shiftColors(C, SKIN_KEYS, rng:NextNumber(-0.035, 0.035), rng:NextNumber(-0.06, 0.04))
	shiftColors(C, TUNIC_KEYS, rng:NextNumber(-0.03, 0.03), rng:NextNumber(-0.08, 0.04))

	local M = Enum.Material
	local model = Instance.new("Model")
	model.Name = options.name or "Jade Goblin"
	model:SetAttribute("Scale", S)

	-- A CFrame at a position given in unscaled goblin units.
	local function at(x, y, z)
		return CFrame.new(x * S, y * S, z * S)
	end

	local function newPart(kind, name, size, cf, color, material)
		local part
		if kind == "wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			if kind == "cyl" then
				part.Shape = Enum.PartType.Cylinder
			end
		end
		part.Name = name
		part.Size = size * S
		part.CFrame = cf
		part.Color = color
		part.Material = material or M.SmoothPlastic
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if kind == "ball" then
			-- A sphere mesh stretched to the part size gives smooth ellipsoids.
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		-- Parts sit directly in the model so weapon scripts that check
		-- hit.Parent:FindFirstChildOfClass("Humanoid") still hit the goblin.
		part.Parent = model
		return part
	end

	-- Decoration welded onto a body segment.
	local function deco(segment, kind, name, size, cf, color, material)
		local part = newPart(kind, name, size, cf, color, material)
		local weld = Instance.new("Weld")
		weld.Part0 = segment
		weld.Part1 = part
		weld.C0 = segment.CFrame:ToObjectSpace(cf)
		weld.Parent = part
		return part
	end

	local function joint(name, part0, part1, pivot)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = part0.CFrame:ToObjectSpace(pivot)
		motor.C1 = part1.CFrame:ToObjectSpace(pivot)
		motor.Parent = part1
		return motor
	end

	-- A cone made of stacked, shrinking cylinders. baseCF looks along the spike.
	local function cone(segment, name, baseCF, length, diameter, color, material, steps)
		steps = steps or 5
		local step = length / steps
		for i = 0, steps - 1 do
			local d = diameter * (1 - i / steps)
			local cf = baseCF * at(0, 0, -(i + 0.5) * step) * CFrame.Angles(0, math.pi / 2, 0)
			deco(segment, "cyl", name, Vector3.new(step * 1.02, d, d), cf, color, material)
		end
	end

	local vertical = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
	local alongZ = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis X -> -Z

	--------------------------------------------------------------------------
	-- Root
	--------------------------------------------------------------------------
	local root = newPart("block", "HumanoidRootPart", Vector3.new(1.6, 1.8, 1), at(0, 2, 0), Color3.new(), nil)
	root.Transparency = 1
	root.CanCollide = true
	root.Massless = false
	root.RootPriority = 127
	root.PivotOffset = CFrame.new(0, -2 * S, 0) -- model pivot sits at the feet
	model.PrimaryPart = root

	--------------------------------------------------------------------------
	-- Hips: tunic skirt, belts, loincloth flaps
	--------------------------------------------------------------------------
	local lowerTorso = newPart("ball", "LowerTorso", Vector3.new(1.5, 0.85, 1.1), at(0, 1.85, 0), C.Tunic, M.Fabric)
	joint("Root", root, lowerTorso, at(0, 1.85, 0))

	deco(lowerTorso, "ball", "Belt", Vector3.new(1.62, 0.26, 1.2), at(0, 2.02, 0), C.Leather, M.Leather)
	deco(lowerTorso, "ball", "Belt", Vector3.new(1.58, 0.22, 1.16), at(0, 1.8, 0) * CFrame.Angles(0, 0, 0.1), C.LeatherDark, M.Leather)
	-- Square iron buckles: an iron plate with a dark leather "hole" in it.
	deco(lowerTorso, "block", "Buckle", Vector3.new(0.3, 0.26, 0.06), at(-0.12, 2.02, -0.62), C.Iron, M.Metal)
	deco(lowerTorso, "block", "Buckle", Vector3.new(0.16, 0.12, 0.07), at(-0.12, 2.02, -0.625), C.LeatherDark, M.Leather)
	deco(lowerTorso, "block", "Buckle", Vector3.new(0.26, 0.22, 0.06), at(0.3, 1.8, -0.6) * CFrame.Angles(0, 0, 0.1), C.Iron, M.Metal)
	deco(lowerTorso, "block", "Buckle", Vector3.new(0.14, 0.1, 0.07), at(0.3, 1.8, -0.605) * CFrame.Angles(0, 0, 0.1), C.LeatherDark, M.Leather)

	local frontFlap = newPart("block", "FrontFlap", Vector3.new(0.66, 0.64, 0.07), at(0, 1.4, -0.5), C.Tunic, M.Fabric)
	deco(frontFlap, "block", "Hem", Vector3.new(0.66, 0.09, 0.08), at(0, 1.13, -0.5), C.TunicDark, M.Fabric)
	deco(frontFlap, "wedge", "Hem", Vector3.new(0.08, 0.14, 0.3), at(-0.18, 1.02, -0.5) * CFrame.Angles(0, math.pi / 2, math.pi), C.TunicDark, M.Fabric)
	deco(frontFlap, "wedge", "Hem", Vector3.new(0.08, 0.14, 0.3), at(0.16, 1.02, -0.5) * CFrame.Angles(0, -math.pi / 2, math.pi), C.TunicDark, M.Fabric)
	joint("FrontFlap", lowerTorso, frontFlap, at(0, 1.72, -0.5))

	local backFlap = newPart("block", "BackFlap", Vector3.new(0.8, 0.7, 0.07), at(0, 1.37, 0.5), C.Tunic, M.Fabric)
	deco(backFlap, "block", "Hem", Vector3.new(0.8, 0.09, 0.08), at(0, 1.07, 0.5), C.TunicDark, M.Fabric)
	joint("BackFlap", lowerTorso, backFlap, at(0, 1.72, 0.5))

	--------------------------------------------------------------------------
	-- Chest
	--------------------------------------------------------------------------
	local upperTorso = newPart("ball", "UpperTorso", Vector3.new(1.45, 1.25, 1.02), at(0, 2.6, 0.02), C.Tunic, M.Fabric)
	joint("Waist", lowerTorso, upperTorso, at(0, 2.05, 0))

	-- Diagonal leather strap from the left shoulder down to the right hip.
	deco(upperTorso, "ball", "ChestStrap", Vector3.new(0.3, 1.6, 1.1), at(0, 2.55, 0.02) * CFrame.Angles(0, 0, 0.7), C.Leather, M.Leather)
	deco(upperTorso, "block", "StrapBuckle", Vector3.new(0.26, 0.26, 0.06), at(0.02, 2.5, -0.55) * CFrame.Angles(0, 0, 0.7), C.Iron, M.Metal)
	deco(upperTorso, "block", "StrapBuckle", Vector3.new(0.13, 0.13, 0.07), at(0.02, 2.5, -0.555) * CFrame.Angles(0, 0, 0.7), C.LeatherDark, M.Leather)
	deco(upperTorso, "ball", "Collar", Vector3.new(1.0, 0.25, 0.8), at(0, 3.0, 0.02), C.TunicDark, M.Fabric)
	deco(upperTorso, "ball", "Neck", Vector3.new(0.7, 0.5, 0.65), at(0, 3.05, -0.02), C.Skin)
	-- Wooden board slung across the back, peeking over the left shoulder.
	deco(upperTorso, "block", "BackBoard", Vector3.new(0.55, 1.3, 0.18), at(-0.35, 3.0, 0.6) * CFrame.Angles(0.15, 0, 0.45), C.Wood, M.Wood)
	deco(upperTorso, "block", "BackBoard", Vector3.new(0.05, 1.28, 0.19), at(-0.35, 3.0, 0.6) * CFrame.Angles(0.15, 0, 0.45) * at(0.1, 0, 0), C.WoodDark, M.Wood)

	--------------------------------------------------------------------------
	-- Head
	--------------------------------------------------------------------------
	local head = newPart("ball", "Head", Vector3.new(1.75, 1.65, 1.6), at(0, 3.78, -0.05), C.Skin)
	joint("Neck", upperTorso, head, at(0, 3.0, 0))

	deco(head, "ball", "Jaw", Vector3.new(1.45, 1.0, 1.35), at(0, 3.25, -0.2), C.Skin)
	deco(head, "ball", "Chin", Vector3.new(0.6, 0.36, 0.45), at(0, 2.78, -0.48), C.Skin)
	deco(head, "ball", "Mouth", Vector3.new(0.6, 0.07, 0.08), at(0, 2.93, -0.715), C.Mouth)
	for _, side in { -1, 1 } do
		-- Down-turned corners of the mouth give the grumpy frown.
		deco(head, "ball", "Mouth", Vector3.new(0.18, 0.06, 0.07), at(side * 0.31, 2.89, -0.66) * CFrame.Angles(0, 0, side * 0.5), C.Mouth)
		deco(head, "ball", "Cheek", Vector3.new(0.5, 0.42, 0.42), at(side * 0.45, 3.4, -0.58), C.SkinLight)
		-- Heavy, angry brows that slope down toward the nose.
		deco(head, "ball", "Brow", Vector3.new(0.66, 0.26, 0.42), at(side * 0.32, 4.0, -0.68) * CFrame.Angles(0, 0, side * 0.28), C.SkinDark)
		-- Eye: white, orange iris, pupil, then a half-closed lid and an under-eye bag.
		deco(head, "ball", "EyeWhite", Vector3.new(0.34, 0.26, 0.2), at(side * 0.33, 3.78, -0.78), C.EyeWhite)
		deco(head, "ball", "Iris", Vector3.new(0.17, 0.17, 0.17), at(side * 0.31, 3.76, -0.86), C.Iris)
		deco(head, "ball", "Pupil", Vector3.new(0.08, 0.08, 0.06), at(side * 0.31, 3.76, -0.925), C.Pupil, M.Glass)
		deco(head, "ball", "Eyelid", Vector3.new(0.4, 0.16, 0.28), at(side * 0.33, 3.9, -0.8), C.Skin)
		deco(head, "ball", "EyeBag", Vector3.new(0.36, 0.1, 0.18), at(side * 0.33, 3.63, -0.77), C.SkinDark)
		deco(head, "ball", "Nostril", Vector3.new(0.12, 0.08, 0.1), at(side * 0.11, 3.0, -1.12), C.Mouth)
	end
	deco(head, "ball", "Nose", Vector3.new(0.42, 0.95, 0.55), at(0, 3.5, -0.92) * CFrame.Angles(0.35, 0, 0), C.SkinLight)
	deco(head, "ball", "NoseTip", Vector3.new(0.5, 0.44, 0.5), at(0, 3.18, -1.1), C.SkinLight)
	deco(head, "ball", "Wrinkle", Vector3.new(0.7, 0.045, 0.08), at(0, 4.2, -0.72), C.SkinDark)
	deco(head, "ball", "Wrinkle", Vector3.new(0.56, 0.045, 0.08), at(0, 4.3, -0.66), C.SkinDark)

	-- Long ears that sweep up and back. Each one is jointed so it can flop.
	for _, side in { -1, 1 } do
		local prefix = side < 0 and "Left" or "Right"
		local pivot = at(side * 0.8, 3.85, 0.05)
		local earCF = pivot * CFrame.Angles(0, -side * 0.35, side * 0.38) * at(side * 0.82, 0, 0)
		local ear = newPart("ball", prefix .. "Ear", Vector3.new(1.75, 0.6, 0.16), earCF, C.Skin)
		deco(ear, "ball", "EarInner", Vector3.new(1.3, 0.4, 0.06), earCF * at(side * 0.08, -0.02, -0.06), C.EarInner)
		deco(ear, "ball", "EarTip", Vector3.new(0.6, 0.36, 0.17), earCF * at(side * 0.6, 0.01, 0), C.EarTip)
		joint(prefix .. "Ear", head, ear, pivot)
	end

	--------------------------------------------------------------------------
	-- Arms (left = -X holds the scimitar, right = +X holds the shield)
	--------------------------------------------------------------------------
	local lowerArms = {}
	for _, side in { -1, 1 } do
		local prefix = side < 0 and "Left" or "Right"
		local upperArm = newPart("ball", prefix .. "UpperArm", Vector3.new(0.44, 0.9, 0.44), at(side * 0.9, 2.42, 0), C.Skin)
		joint(prefix .. "Shoulder", upperTorso, upperArm, at(side * 0.78, 2.85, 0))
		deco(upperArm, "ball", "Sleeve", Vector3.new(0.58, 0.52, 0.58), at(side * 0.86, 2.72, 0), C.Tunic, M.Fabric)
		deco(upperArm, "ball", "SleeveHem", Vector3.new(0.6, 0.1, 0.6), at(side * 0.87, 2.5, 0), C.TunicDark, M.Fabric)

		local lowerArm = newPart("ball", prefix .. "LowerArm", Vector3.new(0.4, 0.82, 0.4), at(side * 0.95, 1.66, 0), C.Skin)
		joint(prefix .. "Elbow", upperArm, lowerArm, at(side * 0.93, 2.02, 0))
		lowerArms[side] = lowerArm

		-- Clenched fist: palm, knuckles and thumb.
		deco(lowerArm, "ball", "Fist", Vector3.new(0.46, 0.44, 0.46), at(side * 0.97, 1.16, -0.02), C.Skin)
		deco(lowerArm, "ball", "Knuckles", Vector3.new(0.36, 0.22, 0.3), at(side * 0.97, 1.12, -0.2), C.SkinLight)
		deco(lowerArm, "ball", "Thumb", Vector3.new(0.16, 0.3, 0.16), at(side * 0.84, 1.22, -0.18), C.Skin)
	end

	-- Left shoulder: iron pauldron.
	local leftUpperArm = model:FindFirstChild("LeftUpperArm")
	deco(leftUpperArm, "ball", "Pauldron", Vector3.new(0.72, 0.42, 0.78), at(-0.88, 2.95, 0), C.Iron, M.Metal)
	deco(leftUpperArm, "ball", "Pauldron", Vector3.new(0.8, 0.12, 0.84), at(-0.9, 2.82, 0), C.IronDark, M.Metal)

	-- Left forearm: spiked leather bracer.
	local leftArm = lowerArms[-1]
	deco(leftArm, "cyl", "Bracer", Vector3.new(0.5, 0.52, 0.52), at(-0.95, 1.6, 0) * vertical, C.LeatherDark, M.Leather)
	deco(leftArm, "cyl", "BracerBand", Vector3.new(0.07, 0.56, 0.56), at(-0.95, 1.84, 0) * vertical, C.Iron, M.Metal)
	deco(leftArm, "cyl", "BracerBand", Vector3.new(0.07, 0.56, 0.56), at(-0.95, 1.37, 0) * vertical, C.Iron, M.Metal)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = at(-0.95, i % 2 == 0 and 1.68 or 1.52, 0).Position + dir * 0.24 * S
		cone(leftArm, "BracerSpike", CFrame.lookAt(base, base + dir), 0.26, 0.14, C.Iron, M.Metal, 4)
	end

	-- Scimitar held in the left fist. At rest the blade points forward, so
	-- bending the elbow swings it up.
	local hand = Vector3.new(-0.97, 1.16, -0.02)
	deco(leftArm, "cyl", "SwordGrip", Vector3.new(0.75, 0.16, 0.16), at(hand.X, hand.Y, hand.Z) * alongZ, C.LeatherDark, M.Leather)
	deco(leftArm, "cyl", "SwordPommel", Vector3.new(0.14, 0.24, 0.24), at(hand.X, hand.Y, 0.4) * alongZ, C.IronDark, M.Metal)
	deco(leftArm, "block", "SwordGuard", Vector3.new(0.14, 0.56, 0.16), at(hand.X, hand.Y, -0.42), C.Gold, M.Metal)
	deco(leftArm, "ball", "SwordGuard", Vector3.new(0.16, 0.16, 0.2), at(hand.X, hand.Y + 0.3, -0.44), C.Gold, M.Metal)
	deco(leftArm, "ball", "SwordGuard", Vector3.new(0.16, 0.16, 0.2), at(hand.X, hand.Y - 0.3, -0.44), C.Gold, M.Metal)
	local widths = { 0.26, 0.29, 0.33, 0.36, 0.38, 0.36 }
	local spine = 0.13 -- straight back edge; the blade widens toward the cutting edge
	local cur = at(hand.X, hand.Y, -0.5)
	for _, w in widths do
		local len = 0.34
		deco(leftArm, "block", "Blade", Vector3.new(0.06, w, len + 0.02), cur * at(0, spine - w / 2, -len / 2), C.Blade, M.Metal)
		deco(leftArm, "block", "BladeEdge", Vector3.new(0.065, 0.06, len + 0.02), cur * at(0, spine - w + 0.03, -len / 2), C.BladeEdge, M.Metal)
		cur = cur * at(0, 0, -len) * CFrame.Angles(0.09, 0, 0) -- curve upward
	end
	deco(leftArm, "wedge", "BladeTip", Vector3.new(0.06, 0.34, 0.5), cur * at(0, spine - 0.17, -0.25) * CFrame.Angles(0, 0, math.pi), C.Blade, M.Metal)

	-- Round wooden shield with an iron rim and centre spike, on the right forearm.
	local rightArm = lowerArms[1]
	deco(rightArm, "cyl", "ShieldStrap", Vector3.new(0.25, 0.46, 0.46), at(0.95, 1.55, 0) * vertical, C.LeatherDark, M.Leather)
	local shield = at(1.28, 1.6, -0.12) * CFrame.Angles(0, 0.95, 0) -- local +X = shield face
	deco(rightArm, "cyl", "ShieldWood", Vector3.new(0.14, 1.75, 1.75), shield, C.Wood, M.Wood)
	deco(rightArm, "cyl", "ShieldBack", Vector3.new(0.08, 1.92, 1.92), shield * at(-0.06, 0, 0), C.IronDark, M.Metal)
	for _, z in { -0.6, -0.3, 0, 0.3, 0.6 } do
		local chord = 2 * math.sqrt(0.875 ^ 2 - z ^ 2) * 0.98
		deco(rightArm, "block", "ShieldPlank", Vector3.new(0.02, chord, 0.035), shield * at(0.07, 0, z), C.WoodDark, M.Wood)
	end
	local rimPieces = 22
	for i = 0, rimPieces - 1 do
		local a = i / rimPieces * math.pi * 2
		local spin = shield * CFrame.Angles(a, 0, 0)
		deco(rightArm, "block", "ShieldRim", Vector3.new(0.24, 0.2, 2 * math.pi * 0.9 / rimPieces * 1.08), spin * at(0.02, 0.9, 0), C.Iron, M.Metal)
		if i % 2 == 0 then
			deco(rightArm, "ball", "Rivet", Vector3.new(0.1, 0.1, 0.1), spin * at(0.15, 0.9, 0), C.IronDark, M.Metal)
		end
	end
	deco(rightArm, "cyl", "ShieldBoss", Vector3.new(0.12, 0.62, 0.62), shield * at(0.11, 0, 0), C.Iron, M.Metal)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		deco(rightArm, "ball", "Rivet", Vector3.new(0.09, 0.09, 0.09), shield * CFrame.Angles(a, 0, 0) * at(0.18, 0.22, 0), C.IronDark, M.Metal)
	end
	cone(rightArm, "ShieldSpike", shield * at(0.17, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), 0.75, 0.3, C.Iron, M.Metal, 6)

	--------------------------------------------------------------------------
	-- Legs: leather trousers, folded boots
	--------------------------------------------------------------------------
	for _, side in { -1, 1 } do
		local prefix = side < 0 and "Left" or "Right"
		local x = side * 0.4

		local upperLeg = newPart("ball", prefix .. "UpperLeg", Vector3.new(0.6, 0.9, 0.62), at(x, 1.3, 0), C.Pants, M.Leather)
		joint(prefix .. "Hip", lowerTorso, upperLeg, at(side * 0.38, 1.68, 0))

		local lowerLeg = newPart("ball", prefix .. "LowerLeg", Vector3.new(0.48, 0.72, 0.5), at(x, 0.68, 0.02), C.Pants, M.Leather)
		joint(prefix .. "Knee", upperLeg, lowerLeg, at(x, 0.98, 0))
		deco(lowerLeg, "ball", "Boot", Vector3.new(0.64, 0.6, 0.66), at(x, 0.55, 0), C.Boot, M.Leather)
		deco(lowerLeg, "ball", "BootCuff", Vector3.new(0.74, 0.22, 0.76), at(x, 0.8, 0) * CFrame.Angles(0.12, 0, 0), C.Boot, M.Leather)
		deco(lowerLeg, "ball", "BootStrap", Vector3.new(0.67, 0.08, 0.69), at(x, 0.48, 0), C.LeatherDark, M.Leather)

		local foot = newPart("ball", prefix .. "Foot", Vector3.new(0.6, 0.46, 1.0), at(x, 0.24, -0.2), C.Boot, M.Leather)
		joint(prefix .. "Ankle", lowerLeg, foot, at(x, 0.36, 0))
		deco(foot, "ball", "Sole", Vector3.new(0.64, 0.16, 1.04), at(x, 0.08, -0.2), C.Sole, M.Leather)
		deco(foot, "ball", "ToeSeam", Vector3.new(0.5, 0.1, 0.36), at(x, 0.36, -0.46) * CFrame.Angles(-0.4, 0, 0), C.LeatherDark, M.Leather)
	end

	--------------------------------------------------------------------------
	-- Humanoid
	--------------------------------------------------------------------------
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 1.1 * S -- root bottom (y = 1.1) to the ground
	humanoid.AutomaticScalingEnabled = false
	humanoid.BreakJointsOnDeath = false -- the spawner ragdolls the goblin instead
	humanoid.RequiresNeck = false
	humanoid.DisplayName = "Jade Goblin"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.NameDisplayDistance = 60
	humanoid.HealthDisplayDistance = 60
	humanoid.Parent = model

	return model
end

return GoblinBuilder
