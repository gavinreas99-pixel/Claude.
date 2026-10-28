--[[
	Bug visuals: draws every bug on this player's screen.

	The server moves one invisible part per bug (Workspace.Bugs). Here each
	part gets a full bug model that glides after it, so motion stays smooth
	even though the server only sends positions over the network. On top of
	that: wing flaps, scuttling legs, hops, worm wiggles, banking turns,
	pulsing glow for rare bugs, and a sparkle burst when a bug is caught.

	This is a Script with RunContext = Client, so it runs from ReplicatedStorage.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local BugData = require(folder:WaitForChild("BugData"))
local BugBuilder = require(folder:WaitForChild("BugBuilder"))
local Util = require(folder:WaitForChild("Util"))
local create, smooth = Util.create, Util.smooth

local bugsFolder = Workspace:WaitForChild("Bugs")
local visualFolder = create("Folder", { Name = "BugVisuals", Parent = Workspace })

local DRAW_DISTANCE = 420 -- the whole meadow; farther bugs freeze in place

-- How each body plan flaps: frequency (flaps per second), amplitude and resting angle (radians).
local FLAP = {
	Butterfly = { freq = 3.2, amp = 0.62, bias = 0.38 },
	Bee = { freq = 17, amp = 0.5, bias = 0.25 },
	Dragonfly = { freq = 11, amp = 0.32, bias = 0.05 },
}

local visuals = {} -- [anchor Part] = visual

local function addBug(anchor)
	if not anchor:IsA("BasePart") or visuals[anchor] then
		return
	end
	local bug = BugData.ById[anchor:GetAttribute("BugId") or anchor.Name]
	if not bug then
		return
	end
	local rig = BugBuilder.build(bug, { effects = true })
	rig.model:PivotTo(anchor.CFrame) -- so it never flashes at the world origin
	rig.model.Parent = visualFolder
	visuals[anchor] = {
		anchor = anchor,
		bug = bug,
		rig = rig,
		cframe = anchor.CFrame,
		lastTarget = anchor.CFrame,
		lastUpdate = os.clock(),
		speed = 0,
		smoothSpeed = 0,
		turn = 0,
		roll = 0,
		stride = 0,
		phase = math.random() * math.pi * 2,
		baseLight = rig.light and rig.light.Brightness or 0,
	}
end

local function sparkleBurst(position, color)
	local holder = create("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(position),
		Parent = visualFolder,
	})
	local emitter = create("ParticleEmitter", {
		Enabled = false,
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(5, 11),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
		LightEmission = 1,
		Parent = holder,
	})
	emitter:Emit(26)
	task.delay(1.2, function()
		holder:Destroy()
	end)
end

local function removeBug(anchor)
	local visual = visuals[anchor]
	if not visual then
		return
	end
	visuals[anchor] = nil
	local model = visual.rig.model
	if anchor:GetAttribute("Caught") then
		sparkleBurst(visual.cframe.Position, BugData.Rarities[visual.bug.Rarity].Color)
		model:Destroy()
		return
	end
	-- Flew off or wandered out of range: fade away.
	local info = TweenInfo.new(0.4)
	for _, record in visual.rig.parts do
		TweenService:Create(record.part, info, { Transparency = 1 }):Play()
	end
	if visual.rig.light then
		TweenService:Create(visual.rig.light, info, { Brightness = 0 }):Play()
	end
	task.delay(0.45, function()
		model:Destroy()
	end)
end

bugsFolder.ChildAdded:Connect(addBug)
bugsFolder.ChildRemoved:Connect(removeBug)
for _, anchor in bugsFolder:GetChildren() do
	addBug(anchor)
end

local function animate(visual, t, dt, parts, cframes)
	local bug, rig = visual.bug, visual.rig
	local s = rig.scale
	local target = visual.anchor.CFrame

	-- How fast the server is moving and turning this bug. Updates arrive less
	-- often than frames, so measure over the time between updates.
	local moved = (target.Position - visual.lastTarget.Position).Magnitude
	if moved > 0 then
		local elapsed = math.clamp(t - visual.lastUpdate, 1 / 120, 0.5)
		local turn = visual.lastTarget.LookVector:Cross(target.LookVector).Y / elapsed
		visual.speed = moved / elapsed
		visual.turn = turn
		visual.lastTarget = target
		visual.lastUpdate = t
	elseif t - visual.lastUpdate > 0.25 then
		visual.speed, visual.turn = 0, 0
	end
	visual.smoothSpeed += (visual.speed - visual.smoothSpeed) * smooth(6, dt)
	-- Lean into turns.
	visual.roll += (math.clamp(-visual.turn * 0.12, -0.6, 0.6) - visual.roll) * smooth(6, dt)

	-- Glide after the server position.
	if (visual.cframe.Position - target.Position).Magnitude > 20 then
		visual.cframe = target -- too far behind (just streamed in): snap
	else
		visual.cframe = visual.cframe:Lerp(target, smooth(10, dt))
	end

	local speed = visual.smoothSpeed
	local root
	if bug.Move == "Fly" then
		local bob = math.sin(t * 2.4 + visual.phase) * 0.22 * s
		local pitch = -math.min(speed / 25, 0.3)
		root = visual.cframe * CFrame.new(0, bob, 0) * CFrame.Angles(pitch, 0, visual.roll)
	else
		visual.stride += dt * (speed / s) * 3
		local hop = 0
		if bug.Shape == "Hopper" and speed > 1 then
			hop = math.abs(math.sin(visual.stride * 0.9)) * 0.9 * s
		end
		root = visual.cframe * CFrame.new(0, hop, 0)
	end

	local flap = FLAP[bug.Shape]
	local flapRate = flap and flap.freq * (1 + math.min(speed / 12, 0.6)) or 0
	for _, record in rig.parts do
		local kind = record.kind
		local cf
		if kind == "wing" then
			local angle = flap.bias + math.sin(t * flapRate * math.pi * 2 + record.phase + visual.phase) * flap.amp
			cf = root * record.hinge * CFrame.Angles(0, 0, record.side * angle) * record.rel
		elseif kind == "leg" then
			local swing = bug.Move == "Crawl" and math.sin(visual.stride * 4 + record.phase) * 0.45 * math.min(speed, 1)
				or math.sin(t * 2 + record.phase) * 0.08
			cf = root * record.hinge * CFrame.Angles(0, swing, 0) * record.rel
		elseif kind == "antenna" then
			local twitch = math.sin(t * 3.1 + record.phase * 1.7 + visual.phase) * 0.12
			cf = root * record.hinge * CFrame.Angles(twitch, 0, 0) * record.rel
		elseif kind == "segment" then
			local wave = visual.stride * 2.2 - record.index * 0.9
			cf = root * CFrame.new(math.sin(wave) * 0.07 * s, math.max(0, math.sin(wave)) * 0.04 * s, 0) * record.rel
		else
			cf = root * record.rel
		end
		table.insert(parts, record.part)
		table.insert(cframes, cf)
	end

	if rig.light then
		rig.light.Brightness = visual.baseLight * (0.7 + 0.3 * math.sin(t * 2.6 + visual.phase))
	end
	for _, part in rig.rainbow do
		part.Color = Color3.fromHSV((t * 0.12 + visual.phase / 6) % 1, 0.65, 1)
	end
end

RunService.RenderStepped:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position or Vector3.zero
	local t = os.clock()
	local parts, cframes = {}, {}
	for _, visual in visuals do
		if (visual.anchor.Position - cameraPosition).Magnitude < DRAW_DISTANCE then
			animate(visual, t, dt, parts, cframes)
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
