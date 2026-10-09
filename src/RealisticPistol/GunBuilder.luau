--[[
	GunBuilder

	Builds the pistol Tool: a polymer-frame, striker-fired style handgun with a
	matte steel slide, rear slide serrations, an ejection port showing the
	barrel hood, U-notch rear sight, dot front sight, accessory rail,
	squared trigger guard, bladed trigger, angled grip with stippled panels
	and a removable magazine.

	Measurements are written in millimetres (real-world pistol proportions)
	and converted to studs. Layout: barrel points -Z, up is +Y, the back of
	the slide is at z = 0 and the top of the frame at y = 0.

	Moving parts are joined with Motor6Ds so the client can animate them:
	  Slide     - slides back (+Z) when firing / locks back when empty
	  Trigger   - rotates back when the trigger is pulled
	  Magazine  - drops down the grip during reloads
]]

local GunBuilder = {}

local COLORS = {
	Slide = Color3.fromRGB(38, 39, 42),
	SlideDark = Color3.fromRGB(16, 16, 18),
	Frame = Color3.fromRGB(30, 30, 32),
	FrameDark = Color3.fromRGB(17, 17, 18),
	Stipple = Color3.fromRGB(34, 34, 36),
	Steel = Color3.fromRGB(92, 94, 99),
	MagSteel = Color3.fromRGB(44, 45, 48),
	Brass = Color3.fromRGB(196, 158, 78),
	Bore = Color3.fromRGB(6, 6, 6),
	Dot = Color3.fromRGB(236, 236, 226),
	Flash = Color3.fromRGB(255, 194, 90),
}

local GRIP_ANGLE = math.rad(22)

function GunBuilder.build(config)
	local S = (config.Scale or 1) * 1.55 / 186 -- millimetres -> studs (186 mm long gun)
	local M = Enum.Material

	local tool = Instance.new("Tool")
	tool.Name = config.ToolName or "Pistol"
	tool.ToolTip = tool.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Ammo", config.MagazineSize)
	tool:SetAttribute("Reloading", false)

	local function at(x, y, z)
		return CFrame.new(x * S, y * S, z * S)
	end
	local alongZ = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis X -> Z
	local alongY = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y

	local function newPart(kind, name, size, cf, color, material)
		local p
		if kind == "wedge" then
			p = Instance.new("WedgePart")
		else
			p = Instance.new("Part")
			if kind == "cyl" then
				p.Shape = Enum.PartType.Cylinder
			elseif kind == "ball" then
				p.Shape = Enum.PartType.Ball
			end
		end
		p.Name = name
		p.Size = size * S
		p.CFrame = cf
		p.Color = color
		p.Material = material or M.SmoothPlastic
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = tool
		return p
	end

	local function weldTo(base, p)
		local w = Instance.new("Weld")
		w.Part0 = base
		w.Part1 = p
		w.C0 = base.CFrame:ToObjectSpace(p.CFrame)
		w.Parent = p
		return p
	end

	local function joint(name, part0, part1, pivot)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = part0.CFrame:ToObjectSpace(pivot)
		m.C1 = part1.CFrame:ToObjectSpace(pivot)
		m.Parent = part1
		return m
	end

	-- Grip frame: tilted back 22 degrees from the bottom of the frame.
	local gripTop = at(0, -8, -36) * CFrame.Angles(-GRIP_ANGLE, 0, 0)
	local function onGrip(x, y, z)
		return gripTop * at(x, y, z)
	end

	--------------------------------------------------------------------------
	-- Handle (invisible; this is where the hand holds the gun)
	--------------------------------------------------------------------------
	local handle = newPart("block", "Handle", Vector3.new(12, 12, 12), CFrame.new(onGrip(0, -42, 0).Position), COLORS.Frame)
	handle.Transparency = 1

	local function frame(kind, name, size, cf, color, material)
		return weldTo(handle, newPart(kind, name, size, cf, color or COLORS.Frame, material or M.SmoothPlastic))
	end

	--------------------------------------------------------------------------
	-- Polymer frame
	--------------------------------------------------------------------------
	frame("block", "Frame", Vector3.new(22, 14, 140), at(0, -7, -80))
	frame("block", "DustCover", Vector3.new(22, 12, 32), at(0, -6, -166))
	for _, z in { -157, -165, -173 } do
		frame("block", "RailSlot", Vector3.new(22.4, 3, 3), at(0, -10.5, z), COLORS.FrameDark)
	end
	frame("block", "Beavertail", Vector3.new(24, 7, 14), at(0, -9.5, -4) * CFrame.Angles(-0.25, 0, 0))

	-- Grip: a block with rounded front and back straps.
	frame("block", "Grip", Vector3.new(30, 100, 26), onGrip(0, -50, 0))
	frame("cyl", "GripFront", Vector3.new(100, 30, 30), onGrip(0, -50, -13) * alongY)
	frame("cyl", "GripBack", Vector3.new(100, 30, 30), onGrip(0, -50, 13) * alongY)
	for _, side in { -1, 1 } do
		-- Stippled texture panels and the thumb rest dimple.
		frame("block", "Stippling", Vector3.new(0.8, 64, 40), onGrip(side * 15.2, -56, 1), COLORS.Stipple, M.Concrete)
		frame("ball", "ThumbRest", Vector3.new(16, 16, 16), onGrip(side * 9.5, -12, -2), COLORS.FrameDark)
		-- Slide stop (left) / takedown levers.
		frame("block", "TakedownLever", Vector3.new(1.6, 3, 7), at(side * 11.6, -3, -104), COLORS.FrameDark)
	end
	frame("block", "SlideStop", Vector3.new(2, 4, 18), at(-11.8, -1, -74), COLORS.FrameDark)
	-- Rear stippling on the backstrap.
	frame("block", "BackStippling", Vector3.new(18, 60, 0.8), onGrip(0, -56, 28.2), COLORS.Stipple, M.Concrete)

	-- Squared trigger guard.
	frame("block", "TriggerGuard", Vector3.new(18, 5, 79), at(0, -47, -89.5))
	frame("block", "TriggerGuard", Vector3.new(18, 31, 5), at(0, -31, -127.5) * CFrame.Angles(0.06, 0, 0))
	frame("cyl", "TriggerGuard", Vector3.new(18, 10, 10), at(0, -44.5, -125))

	--------------------------------------------------------------------------
	-- Trigger (jointed)
	--------------------------------------------------------------------------
	local triggerPivot = at(0, -14, -96)
	local trigger = newPart("block", "Trigger", Vector3.new(6, 11, 5), at(0, -20, -97), COLORS.FrameDark)
	weldTo(trigger, newPart("block", "TriggerCurve", Vector3.new(6, 10, 5), at(0, -29, -96.5) * CFrame.Angles(0.25, 0, 0), COLORS.FrameDark))
	weldTo(trigger, newPart("block", "TriggerCurve", Vector3.new(6, 8, 5), at(0, -36.5, -94.5) * CFrame.Angles(0.55, 0, 0), COLORS.FrameDark))
	weldTo(trigger, newPart("block", "TriggerSafety", Vector3.new(2.2, 20, 2), at(0, -30, -99.2) * CFrame.Angles(0.2, 0, 0), COLORS.Frame))
	joint("Trigger", handle, trigger, triggerPivot)

	--------------------------------------------------------------------------
	-- Magazine (jointed; mostly hidden inside the grip until a reload)
	--------------------------------------------------------------------------
	local magazine = newPart("block", "Magazine", Vector3.new(22, 95, 30), onGrip(0, -52, 2), COLORS.MagSteel, M.Metal)
	weldTo(magazine, newPart("block", "MagBaseplate", Vector3.new(32, 8, 56), onGrip(0, -103.5, 1), COLORS.Frame))
	weldTo(magazine, newPart("cyl", "Cartridge", Vector3.new(19, 9, 9), onGrip(0, -2, -2) * alongZ, COLORS.Brass, M.Metal))
	joint("Magazine", handle, magazine, onGrip(0, -50, 0))

	--------------------------------------------------------------------------
	-- Slide (jointed)
	--------------------------------------------------------------------------
	local slide = newPart("block", "Slide", Vector3.new(25, 28, 186), at(0, 14, -93), COLORS.Slide, M.Metal)
	slide.Reflectance = 0.04
	local function onSlide(kind, name, size, cf, color, material)
		local p = newPart(kind, name, size, cf, color or COLORS.Slide, material or M.Metal)
		return weldTo(slide, p)
	end
	-- Rounded top edges.
	onSlide("block", "SlideTop", Vector3.new(17, 4, 186), at(0, 30, -93))
	onSlide("cyl", "SlideEdge", Vector3.new(186, 8, 8), at(-8.5, 28, -93) * alongZ)
	onSlide("cyl", "SlideEdge", Vector3.new(186, 8, 8), at(8.5, 28, -93) * alongZ)
	-- Rear slide serrations.
	for i = 0, 6 do
		onSlide("block", "Serration", Vector3.new(25.6, 22, 1.8), at(0, 13, -9 - i * 5), COLORS.SlideDark)
	end
	-- Ejection port with the barrel hood showing through.
	onSlide("block", "EjectionPort", Vector3.new(14, 0.6, 37), at(3.5, 32.05, -62), COLORS.SlideDark)
	onSlide("block", "BarrelHood", Vector3.new(11, 0.9, 32), at(3.5, 32.2, -62), COLORS.Steel)
	onSlide("block", "EjectionPort", Vector3.new(0.6, 9, 37), at(12.55, 25.5, -62), COLORS.SlideDark)
	onSlide("block", "BarrelHood", Vector3.new(0.9, 7, 32), at(12.7, 25.5, -62), COLORS.Steel)
	onSlide("block", "Extractor", Vector3.new(0.8, 3, 15), at(12.8, 20, -50), COLORS.SlideDark)
	-- Sights.
	onSlide("block", "FrontSight", Vector3.new(3.5, 5, 6), at(0, 34.5, -179), COLORS.SlideDark)
	onSlide("block", "FrontSightDot", Vector3.new(1.6, 1.6, 0.4), at(0, 35.5, -175.9), COLORS.Dot, M.SmoothPlastic)
	onSlide("block", "RearSight", Vector3.new(23, 2.5, 7), at(0, 33.2, -10), COLORS.SlideDark)
	for _, side in { -1, 1 } do
		onSlide("block", "RearSight", Vector3.new(8, 6, 7), at(side * 7.5, 35, -10), COLORS.SlideDark)
		onSlide("block", "RearSightOutline", Vector3.new(1.2, 4, 0.4), at(side * 4.1, 35.4, -6.4), COLORS.Dot, M.SmoothPlastic)
	end
	onSlide("block", "RearSightOutline", Vector3.new(9.4, 1.2, 0.4), at(0, 33.9, -6.4), COLORS.Dot, M.SmoothPlastic)
	-- Muzzle: barrel crown, bore, recoil spring guide.
	onSlide("cyl", "BarrelCrown", Vector3.new(1.2, 13, 13), at(0, 16, -186.4) * alongZ, COLORS.Steel)
	onSlide("cyl", "Bore", Vector3.new(1.4, 9, 9), at(0, 16, -186.6) * alongZ, COLORS.Bore, M.SmoothPlastic)
	onSlide("cyl", "SpringGuide", Vector3.new(0.6, 7, 7), at(0, 4, -186.2) * alongZ, COLORS.Bore, M.SmoothPlastic)
	joint("Slide", handle, slide, at(0, 14, -93))

	--------------------------------------------------------------------------
	-- Effects: muzzle flash, light, smoke, ejection point
	--------------------------------------------------------------------------
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = handle.CFrame:ToObjectSpace(at(0, 16, -189))
	muzzle.Parent = handle

	local light = Instance.new("PointLight")
	light.Name = "FlashLight"
	light.Color = COLORS.Flash
	light.Brightness = 6
	light.Range = 12
	light.Enabled = false
	light.Parent = muzzle

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "FlashParticles"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(COLORS.Flash)
	sparks.LightEmission = 1
	sparks.Lifetime = NumberRange.new(0.03, 0.07)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(14, 14)
	sparks.Size = NumberSequence.new(0.35 * (config.Scale or 1), 0)
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks.Rate = 0
	sparks.Parent = muzzle

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "SmokeParticles"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(190, 190, 190))
	smoke.Lifetime = NumberRange.new(0.4, 0.8)
	smoke.Speed = NumberRange.new(1, 3)
	smoke.SpreadAngle = Vector2.new(20, 20)
	smoke.Size = NumberSequence.new(0.15, 0.7)
	smoke.Transparency = NumberSequence.new(0.6, 1)
	smoke.EmissionDirection = Enum.NormalId.Front
	smoke.Rate = 0
	smoke.Parent = muzzle

	-- Neon flash star (hidden until a shot).
	for i, spec in {
		{ Vector3.new(4, 4, 46), at(0, 16, -212) },
		{ Vector3.new(28, 4, 4), at(0, 16, -194) },
		{ Vector3.new(4, 28, 4), at(0, 16, -194) },
	} do
		local flash = frame("block", "MuzzleFlash", spec[1], spec[2], COLORS.Flash, M.Neon)
		flash.Transparency = 1
		flash.CastShadow = false
		flash.CanQuery = false
		flash:SetAttribute("FlashIndex", i)
	end

	local ejection = Instance.new("Attachment")
	ejection.Name = "Ejection"
	ejection.CFrame = handle.CFrame:ToObjectSpace(at(10, 30, -62))
	ejection.Parent = handle

	return tool
end

return GunBuilder
