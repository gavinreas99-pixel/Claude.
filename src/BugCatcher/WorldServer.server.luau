--[[
	World server: builds the meadow, sets up realistic lighting, starts the
	day/night clock and decides when it rains. WorldClient does the visuals.
	This is a Script with RunContext = Server, so it runs from ReplicatedStorage.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local Environment = require(folder:WaitForChild("Environment"))
local FieldBuilder = require(folder:WaitForChild("FieldBuilder"))
local Util = require(folder:WaitForChild("Util"))
local create = Util.create

local function findOrCreate(parent, className, props)
	local instance = parent:FindFirstChildOfClass(className)
	if not instance then
		return create(className, props)
	end
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	return instance
end

local function setupLighting()
	-- Soft, realistic sunlight. LightingStyle is new; older engines just skip it.
	pcall(function()
		Lighting.LightingStyle = Enum.LightingStyle.Realistic
	end)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.Brightness = 2.4
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.Ambient = Color3.fromRGB(70, 72, 82)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 136)
	Lighting.ExposureCompensation = 0
	Lighting.GeographicLatitude = 35
	Lighting.ClockTime = Config.StartClockTime

	findOrCreate(Lighting, "Sky", {
		StarCount = 3000,
		SunAngularSize = 14,
		MoonAngularSize = 9,
		CelestialBodiesShown = true,
		Parent = Lighting,
	})
	-- Atmosphere gives the light fog and the hazy horizon.
	findOrCreate(Lighting, "Atmosphere", {
		Density = 0.3,
		Offset = 0.25,
		Color = Color3.fromRGB(199, 212, 226),
		Decay = Color3.fromRGB(106, 124, 148),
		Glare = 0.3,
		Haze = 1.2,
		Parent = Lighting,
	})
	findOrCreate(Lighting, "BloomEffect", {
		Intensity = 0.5,
		Size = 24,
		Threshold = 1.6,
		Parent = Lighting,
	})
	findOrCreate(Lighting, "ColorCorrectionEffect", {
		Contrast = 0.06,
		Saturation = 0.12,
		TintColor = Color3.new(1, 1, 1),
		Parent = Lighting,
	})
	findOrCreate(Lighting, "SunRaysEffect", {
		Intensity = 0.05,
		Spread = 0.7,
		Parent = Lighting,
	})
	findOrCreate(Workspace.Terrain, "Clouds", {
		Cover = 0.55,
		Density = 0.55,
		Color = Color3.new(1, 1, 1),
		Parent = Workspace.Terrain,
	})
end

-- Day/night: clients and the bug spawner work out the time from this one value.
local function startClock()
	local sunrise = Workspace:GetServerTimeNow() - Environment.secondsAfterSunrise(Config.StartClockTime)
	folder:SetAttribute("SunriseTime", sunrise)
end

-- Weather: every so often there's a chance of a shower.
local function runWeather()
	local rng = Random.new()
	folder:SetAttribute("Raining", false)
	while true do
		task.wait(Config.RainCheckSeconds)
		if rng:NextNumber() < Config.RainChance then
			folder:SetAttribute("Raining", true)
			task.wait(rng:NextNumber(Config.RainSeconds[1], Config.RainSeconds[2]))
			folder:SetAttribute("Raining", false)
		end
	end
end

setupLighting()
startClock()
FieldBuilder.build(Config)
task.spawn(runWeather)
