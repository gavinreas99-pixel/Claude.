--[[
	Bug Catcher settings. Change these numbers to tune the game.
]]

return {
	-- Field ------------------------------------------------------------------
	FieldRadius = 150, -- radius of the open meadow, in studs
	Seed = 7, -- change this for a different layout of trees and flowers
	TreeCount = 30,
	BushCount = 22,
	RockCount = 12,
	FlowerPatches = 55,
	GrassTufts = 260,
	RemoveBaseplate = true, -- delete the template "Baseplate" so it doesn't cover the grass

	-- Day and night ----------------------------------------------------------
	DayMinutes = 6, -- real minutes from sunrise to sunset
	NightMinutes = 4, -- real minutes from sunset to sunrise
	StartClockTime = 8.5, -- time of day when the server starts (24-hour clock)

	-- Rain -------------------------------------------------------------------
	RainCheckSeconds = 40, -- how often the sky "rolls the dice" for rain
	RainChance = 0.3, -- chance that it starts raining on each roll
	RainSeconds = { 50, 100 }, -- a shower lasts between these many seconds

	-- Bugs -------------------------------------------------------------------
	MaxCommonBugs = 14,
	MaxRareBugs = 5, -- only at night
	MaxEpicBugs = 4, -- only while it rains
	SpawnInterval = 1.5, -- seconds between spawn attempts
	SpawnMinPlayerDistance = 20, -- bugs never pop in right next to a player

	-- Bug net ----------------------------------------------------------------
	NetName = "Bug Net",
	SwingCooldown = 0.55, -- seconds between swings
	NetReach = 3.5, -- how far in front of the player the net lands
	NetRadius = 6, -- bugs this close (sideways) to that spot get caught
	NetHeight = 4.5, -- ...and this close vertically

	-- Saving -----------------------------------------------------------------
	DataStoreName = "BugCatcher_v1",
	AutosaveSeconds = 90,

	-- Sounds -----------------------------------------------------------------
	-- Built-in Roblox sounds (rbxasset://) always work. The rain loop is a free
	-- Roblox library sound. Paste any other ID from the Creator Store to swap one,
	-- like Rain = "rbxassetid://123456". Leave "" for silence.
	Sounds = {
		Footsteps = "rbxasset://sounds/action_footsteps_plastic.mp3",
		Rain = "rbxassetid://9112854440",
		Swing = "rbxasset://sounds/swordslash.wav",
		Catch = "rbxasset://sounds/electronicpingshort.wav",
		NewBug = "rbxasset://sounds/victory.wav", -- extra fanfare for a bug you've never caught
	},
	FootstepVolume = 0.45,
	RainVolume = 0.7,
}
