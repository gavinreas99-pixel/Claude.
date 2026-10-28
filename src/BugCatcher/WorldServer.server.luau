--[[
	World server: builds the meadow and sets up realistic lighting.
	This is a Script with RunContext = Server, so it runs from ReplicatedStorage.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
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

setupLighting()
FieldBuilder.build(Config)
