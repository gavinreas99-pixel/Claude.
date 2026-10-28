--[[
	World client: everything about the world you see and hear.

	  * Moves the sun and moon and blends the lighting between day, dusk,
	    night and rain (soft shadows, light fog, clouds, colour grading).
	  * Rain: falling streaks around the camera, splashes on the grass and
	    a looping rain sound.
	  * Footsteps on the grass for every player.

	This is a Script with RunContext = Client, so it runs from ReplicatedStorage.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local Environment = require(folder:WaitForChild("Environment"))
local Util = require(folder:WaitForChild("Util"))
local create, lerp, smooth = Util.create, Util.lerp, Util.smooth

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function waitForClass(parent, className)
	local found = parent:FindFirstChildOfClass(className)
	local started = os.clock()
	while not found and os.clock() - started < 10 do
		task.wait(0.2)
		found = parent:FindFirstChildOfClass(className)
	end
	return found
end

local atmosphere = waitForClass(Lighting, "Atmosphere")
local bloom = waitForClass(Lighting, "BloomEffect")
local grading = waitForClass(Lighting, "ColorCorrectionEffect")
local sunRays = waitForClass(Lighting, "SunRaysEffect")
local clouds = waitForClass(Workspace.Terrain, "Clouds")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Lighting looks: { day, night, rain }. Rain blends over whichever of day/night it is.
local LOOK = {
	OutdoorAmbient = { rgb(128, 128, 136), rgb(58, 68, 108), rgb(108, 112, 120) },
	Ambient = { rgb(70, 72, 82), rgb(28, 32, 52), rgb(62, 64, 70) },
	AtmosphereColor = { rgb(199, 212, 226), rgb(46, 56, 86), rgb(150, 156, 166) },
	AtmosphereDecay = { rgb(106, 124, 148), rgb(28, 34, 56), rgb(110, 116, 126) },
	Tint = { rgb(255, 255, 255), rgb(196, 210, 255), rgb(226, 232, 240) },
	CloudColor = { rgb(255, 255, 255), rgb(120, 130, 160), rgb(150, 154, 162) },
}
local DUSK_TINT = rgb(255, 222, 196)

-- --------------------------------------------------------------- day, night and lighting

local rain = 0 -- 0 = dry, 1 = full rain; eases in and out

local function updateLighting(dt)
	local clock = Environment.getClockTime()
	Lighting.ClockTime = clock

	local target = Environment.isRaining() and 1 or 0
	rain += math.clamp(target - rain, -dt / 6, dt / 6)

	local sunHeight = math.sin((clock - 6) / 12 * math.pi) -- 1 at noon, -1 at midnight
	local day = math.clamp(sunHeight * 4 + 0.25, 0, 1)
	local dusk = math.clamp(1 - math.abs(sunHeight) * 3.5, 0, 1)

	local function look(name)
		local values = LOOK[name]
		local base = values[2]:Lerp(values[1], day)
		local wet = values[3]:Lerp(values[2], (1 - day) * 0.7)
		return base:Lerp(wet, rain)
	end

	Lighting.Brightness = lerp(1.1, 2.4, day) * (1 - 0.45 * rain)
	Lighting.OutdoorAmbient = look("OutdoorAmbient")
	Lighting.Ambient = look("Ambient")

	if atmosphere then
		atmosphere.Color = look("AtmosphereColor")
		atmosphere.Decay = look("AtmosphereDecay")
		atmosphere.Density = 0.3 + 0.17 * rain
		atmosphere.Haze = 1.2 + 1.6 * rain
		atmosphere.Glare = 0.3 * day * (1 - rain)
	end
	if grading then
		grading.TintColor = look("Tint"):Lerp(DUSK_TINT, dusk * 0.6 * (1 - rain))
		grading.Saturation = lerp(-0.12, 0.12, day) - 0.22 * rain
		grading.Contrast = 0.06
	end
	if bloom then
		-- Lower threshold at night so glowing bugs bloom more.
		bloom.Threshold = lerp(1.05, 1.6, day)
		bloom.Intensity = lerp(0.9, 0.5, day)
	end
	if sunRays then
		sunRays.Intensity = 0.05 * day * (1 - rain)
	end
	if clouds then
		clouds.Cover = 0.55 + 0.4 * rain
		clouds.Density = 0.55 + 0.35 * rain
		clouds.Color = look("CloudColor")
	end
end

-- --------------------------------------------------------------- rain

local DROP_COUNT = isMobile and 110 or 220
local DROP_VELOCITY = Vector3.new(5, -85, 2.5)
local DROP_AREA = 55 -- half-width of the box of rain around the camera
local PARKED = CFrame.new(0, -500, 0)

-- Turn each streak to match the slant of the falling rain.
local slant = -DROP_VELOCITY.Unit
local slantAxis = Vector3.yAxis:Cross(slant)
local DROP_ROTATION = slantAxis.Magnitude > 1e-4
		and CFrame.fromAxisAngle(slantAxis.Unit, math.acos(Vector3.yAxis:Dot(slant)))
	or CFrame.identity

local rainFolder = create("Folder", { Name = "BugCatcherRain", Parent = Workspace })
local drops = {}
for i = 1, DROP_COUNT do
	drops[i] = {
		part = create("Part", {
			Name = "Drop",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.SmoothPlastic,
			Color = rgb(196, 210, 228),
			Transparency = 0.55,
			Size = Vector3.new(0.05, 1.7, 0.05),
			CFrame = PARKED,
			Parent = rainFolder,
		}),
		position = nil,
	}
end

local splashPart = create("Part", {
	Name = "Splashes",
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	Transparency = 1,
	Size = Vector3.new(DROP_AREA * 1.6, 0.2, DROP_AREA * 1.6),
	CFrame = PARKED,
	Parent = rainFolder,
})
local splashes = create("ParticleEmitter", {
	Rate = 0,
	Lifetime = NumberRange.new(0.15, 0.3),
	Speed = NumberRange.new(2, 4),
	SpreadAngle = Vector2.new(35, 35),
	EmissionDirection = Enum.NormalId.Top,
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0.04) }),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
	Color = ColorSequence.new(rgb(220, 232, 255)),
	Acceleration = Vector3.new(0, -25, 0),
	LightInfluence = 1,
	Parent = splashPart,
})

local rainSound = create("Sound", {
	Name = "Rain",
	SoundId = Config.Sounds.Rain,
	Looped = true,
	Volume = 0,
	Parent = SoundService,
})

local rng = Random.new()

local function respawnDrop(drop, cameraPosition, anywhereInColumn)
	local fallTime = rng:NextNumber(0.2, 0.6)
	local x = cameraPosition.X + rng:NextNumber(-DROP_AREA, DROP_AREA) - DROP_VELOCITY.X * fallTime
	local z = cameraPosition.Z + rng:NextNumber(-DROP_AREA, DROP_AREA) - DROP_VELOCITY.Z * fallTime
	local y = cameraPosition.Y + (anywhereInColumn and rng:NextNumber(-25, 45) or rng:NextNumber(30, 50))
	drop.position = Vector3.new(x, y, z)
end

local activeDrops = 0

local function updateRain(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local wanted = math.floor(DROP_COUNT * rain + 0.5)

	local parts, cframes = {}, {}
	for i, drop in drops do
		if i <= wanted then
			if not drop.position then
				respawnDrop(drop, cameraPosition, true)
			end
			local position = drop.position + DROP_VELOCITY * dt
			if position.Y < -1 or position.Y < cameraPosition.Y - 40 then
				respawnDrop(drop, cameraPosition, false)
				position = drop.position
			end
			drop.position = position
			table.insert(parts, drop.part)
			table.insert(cframes, CFrame.new(position) * DROP_ROTATION)
		elseif i <= activeDrops then
			-- This drop just switched off: park it out of sight once.
			drop.position = nil
			table.insert(parts, drop.part)
			table.insert(cframes, PARKED)
		end
	end
	activeDrops = wanted
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end

	splashes.Rate = (isMobile and 140 or 260) * rain
	splashPart.CFrame = rain > 0 and CFrame.new(cameraPosition.X, 0.15, cameraPosition.Z) or PARKED

	rainSound.Volume = Config.RainVolume * rain
	if rain > 0.01 and not rainSound.IsPlaying then
		rainSound:Play()
	elseif rain <= 0.01 and rainSound.IsPlaying then
		rainSound:Stop()
	end
end

-- --------------------------------------------------------------- footsteps

-- Roblox's default footsteps sound like plastic. Each character gets a softer,
-- muffled loop that only plays while it walks on the ground.
local walkers = {}

local function addCharacter(character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not root or not humanoid or Config.Sounds.Footsteps == "" then
		return
	end
	local steps = create("Sound", {
		Name = "GrassSteps",
		SoundId = Config.Sounds.Footsteps,
		Looped = true,
		Volume = 0,
		RollOffMaxDistance = 60,
		Parent = root,
	})
	create("EqualizerSoundEffect", { HighGain = -12, MidGain = -2, LowGain = 3, Parent = steps })
	steps:Play()
	walkers[character] = { root = root, humanoid = humanoid, sound = steps, volume = 0 }
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(addCharacter)
	if player.Character then
		task.spawn(addCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

local function updateFootsteps(dt)
	for character, walker in walkers do
		if not character.Parent or not walker.root.Parent then
			walkers[character] = nil
			continue
		end
		local defaultSteps = walker.root:FindFirstChild("Running")
		if defaultSteps and defaultSteps:IsA("Sound") then
			defaultSteps.Volume = 0
		end
		local velocity = walker.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local grounded = math.abs(velocity.Y) < 2 and walker.humanoid.Health > 0
		local target = (grounded and speed > 1.5) and Config.FootstepVolume * math.clamp(speed / 16, 0.4, 1.2) or 0
		walker.volume = lerp(walker.volume, target, smooth(18, dt))
		walker.sound.Volume = walker.volume
		walker.sound.PlaybackSpeed = math.clamp(speed / 16, 0.6, 1.4) * 0.92
	end
end

-- --------------------------------------------------------------- main loop

RunService.RenderStepped:Connect(function(dt)
	updateLighting(dt)
	updateRain(dt)
	updateFootsteps(dt)
end)
