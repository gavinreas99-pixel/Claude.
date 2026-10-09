--[[
	GoblinAnimator

	Procedural animation for goblins built by GoblinBuilder. Runs on each
	client and writes Motor6D.Transform every frame, so it's smooth and costs
	the server nothing.

	It blends between:
	  - idle:   crouched breathing, sword raised, looking around, ear twitches
	  - run:    full stride cycle with knee tuck, push-off, body bob, lean,
	            hip/shoulder counter-twist, swinging arms, flopping ears and
	            loincloth; it slows to a walk at low speed
	  - air:    legs tucked while jumping/falling
	  - attack: overhead scimitar slash (model attribute "AttackStart")
	  - hurt:   head-and-body flinch (model attribute "HurtStart")

	Sign conventions (see GoblinBuilder): +X swings a limb forward, -X leans
	the body forward, +Z raises the right side, Y twists.
]]

local GoblinAnimator = {}

local TAU = math.pi * 2

local JOINTS = {
	"Root", "Waist", "Neck", "LeftEar", "RightEar",
	"LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow",
	"LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle",
	"FrontFlap", "BackFlap",
}

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Sword swing keyframes: shoulder pitch, shoulder roll, elbow, waist twist, waist lean.
local READY = { 0.45, -0.2, 0.95, 0, 0 }
local WINDUP = { 2.8, -0.45, 1.7, 0.5, 0.08 }
local STRIKE = { 0.15, 0.25, 0.1, -0.55, -0.32 }

local function attackPose(u)
	local pose = table.create(5)
	local weight
	if u < 0.38 then
		local k = smooth(u / 0.38)
		for i = 1, 5 do
			pose[i] = lerp(READY[i], WINDUP[i], k)
		end
		weight = smooth(u / 0.1)
	elseif u < 0.58 then
		local k = (u - 0.38) / 0.2
		k = k * k -- accelerate into the hit
		for i = 1, 5 do
			pose[i] = lerp(WINDUP[i], STRIKE[i], k)
		end
		weight = 1
	else
		for i = 1, 5 do
			pose[i] = STRIKE[i]
		end
		weight = 1 - smooth((u - 0.58) / 0.42)
	end
	return pose, weight
end

function GoblinAnimator.new(model, config)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	for _, name in JOINTS do
		if not motors[name] then
			return nil
		end
	end
	local seed = math.random() * 100
	return {
		model = model,
		root = root,
		motors = motors,
		scale = model:GetAttribute("Scale") or 1,
		runSpeed = config.ChaseSpeed,
		attackDuration = config.AttackDuration,
		seed = seed,
		t = seed,
		phase = 0,
		move = 0,
		air = 0,
		twitchAt = seed + 1 + math.random() * 3,
		twitchStart = -math.huge,
		twitchSide = 1,
	}
end

-- grounded: whether the goblin is standing on something (the client raycasts for this).
function GoblinAnimator.step(rig, dt, serverNow, grounded)
	local motors = rig.motors
	local vel = rig.root.AssemblyLinearVelocity
	local speed = Vector2.new(vel.X, vel.Z).Magnitude
	local S = rig.scale

	rig.t += dt
	local t = rig.t

	-- Smoothed 0..1 "how much running" and "how much in the air".
	local moveTarget = math.clamp(speed / rig.runSpeed, 0, 1)
	rig.move += (moveTarget - rig.move) * math.min(1, dt * 7)
	local airTarget = (not grounded and math.abs(vel.Y) > 1) and 1 or 0
	rig.air += (airTarget - rig.air) * math.min(1, dt * 10)
	local m = rig.move * (1 - rig.air)
	local idle = (1 - rig.move) * (1 - rig.air)
	local air = rig.air

	-- Stride cycle: faster steps at higher speed, scaled for leg length.
	local strides = 0.9 + (speed / S) * 0.12
	if rig.move > 0.02 then
		rig.phase = (rig.phase + dt * strides * TAU) % TAU
	end
	local p = rig.phase
	local s, c = math.sin(p), math.cos(p)
	local bounce = math.sin(p * 2 - 1.0)
	local breath = math.sin(t * 2.2)

	-- Idle look-around and ear twitches.
	local lookYaw = 0.4 * math.sin(t * 0.45) * math.sin(t * 0.23 + 1.3)
	local lookPitch = 0.08 * math.sin(t * 0.37 + 2)
	if t >= rig.twitchAt then
		rig.twitchStart = t
		rig.twitchAt = t + 1.5 + math.random() * 4
		rig.twitchSide = -rig.twitchSide
	end
	local twitch = 0
	local tw = t - rig.twitchStart
	if tw < 0.25 then
		twitch = math.sin(tw / 0.25 * math.pi) * 0.35 * idle
	end

	-- Body: lean into the run, bob up at each push-off, twist with the hips.
	local lean = 0.32 * m
	local bob = (m * (0.16 * math.abs(s) - 0.06) - idle * 0.04 + idle * 0.012 * breath + air * 0.05) * S
	local rootPitch, rootYaw, rootRoll = -lean, -0.16 * s * m, 0.05 * s * m
	local waistPitch, waistYaw = -0.08 * m + 0.03 * breath * idle, 0.3 * s * m
	local neckPitch = lean * 0.8 + 0.05 * bounce * m + lookPitch * idle
	local neckYaw = lookYaw * idle - 0.15 * s * m

	-- Legs. side: -1 left, +1 right. The left leg leads when s > 0.
	local legs = {}
	for _, side in { -1, 1 } do
		local ls, lc = -side * s, -side * c
		local hip = lean + 0.95 * ls * m + 0.18 * idle + 0.7 * air
		local knee = -(m * (0.35 + 1.25 * ((1 + lc) / 2) ^ 2) + 0.36 * idle + 1.1 * air)
		-- Keep the foot roughly flat on the ground, and point the toes as it pushes off.
		local ankle = (lean - hip - knee) * 0.75 * (m + idle) - 0.35 * m * math.max(0, -ls) + 0.3 * air
		legs[side] = { hip, knee, ankle }
	end

	-- Arms. The sword arm swings opposite the left leg; the shield arm stays guarded.
	local lsPitch = idle * (0.45 + 0.04 * breath) + m * (0.35 - 0.55 * s) + air * 0.9
	local lsRoll = -(idle * 0.2 + m * 0.22 + air * 0.5)
	local lElbow = idle * 0.95 + m * (1.15 - 0.1 * s) + air * 1.0
	local rsPitch = idle * (0.25 + 0.03 * breath) + m * (0.3 + 0.25 * s) + air * 0.5
	local rsRoll = idle * 0.18 + m * 0.2 + air * 0.6
	local rElbow = idle * 0.35 + m * 0.5 + air * 0.4

	-- Sword attack overrides the sword arm and waist.
	local attackStart = rig.model:GetAttribute("AttackStart")
	if attackStart then
		local u = (serverNow - attackStart) / rig.attackDuration
		if u >= 0 and u < 1 then
			local pose, w = attackPose(u)
			lsPitch = lerp(lsPitch, pose[1], w)
			lsRoll = lerp(lsRoll, pose[2], w)
			lElbow = lerp(lElbow, pose[3], w)
			waistYaw = lerp(waistYaw, pose[4], w)
			waistPitch += pose[5] * w
		end
	end

	-- Flinch when hit.
	local hurtStart = rig.model:GetAttribute("HurtStart")
	if hurtStart then
		local u = (serverNow - hurtStart) / 0.35
		if u >= 0 and u < 1 then
			local k = math.sin(u * math.pi)
			neckPitch += 0.35 * k
			waistPitch += 0.2 * k
			rsPitch += 0.4 * k
		end
	end

	-- Ears flop with each bounce, sweep back in the wind, and twitch at rest.
	local earFlop = 0.14 * m * bounce + 0.04 * idle * breath - 0.2 * air
	local earSweep = 0.3 * m

	-- Loincloth: the front flap is kicked by whichever leg is forward, the back trails.
	local frontFlap = m * (0.12 + 0.45 * math.abs(s)) + air * 0.4
	local backFlap = -m * (0.45 + 0.12 * math.sin(p * 2)) - air * 0.3

	local CF, A = CFrame.new, CFrame.Angles
	motors.Root.Transform = CF(0, bob, 0) * A(rootPitch, rootYaw, rootRoll)
	motors.Waist.Transform = A(waistPitch, waistYaw, 0)
	motors.Neck.Transform = A(neckPitch, neckYaw, 0)
	motors.LeftEar.Transform = A(0.05 * m * bounce, earSweep, -(earFlop + (rig.twitchSide < 0 and twitch or 0)))
	motors.RightEar.Transform = A(0.05 * m * bounce, -earSweep, earFlop + (rig.twitchSide > 0 and twitch or 0))
	motors.LeftShoulder.Transform = A(lsPitch, 0, lsRoll)
	motors.RightShoulder.Transform = A(rsPitch, 0, rsRoll)
	motors.LeftElbow.Transform = A(lElbow, 0, 0)
	motors.RightElbow.Transform = A(rElbow, 0, 0)
	motors.LeftHip.Transform = A(legs[-1][1], 0, -0.05)
	motors.RightHip.Transform = A(legs[1][1], 0, 0.05)
	motors.LeftKnee.Transform = A(legs[-1][2], 0, 0)
	motors.RightKnee.Transform = A(legs[1][2], 0, 0)
	motors.LeftAnkle.Transform = A(legs[-1][3], 0, 0)
	motors.RightAnkle.Transform = A(legs[1][3], 0, 0)
	motors.FrontFlap.Transform = A(frontFlap, 0, 0)
	motors.BackFlap.Transform = A(backFlap, 0, 0)
end

return GoblinAnimator
