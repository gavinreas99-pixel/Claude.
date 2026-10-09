--[[
	Pistol settings. Change these numbers to tune the gun.
]]

return {
	ToolName = "Pistol",
	GiveOnSpawn = true, -- every player spawns with the pistol

	-- Size of the gun. 1 = about 1.55 studs long.
	Scale = 1,

	MagazineSize = 17,
	Damage = 22,
	HeadshotMultiplier = 2,
	Range = 400, -- studs
	FireCooldown = 0.13, -- seconds between shots
	Automatic = false, -- true = hold to keep firing
	SpreadDegrees = 0.5,
	ReloadTime = 1.6, -- seconds
	TeamKill = false, -- false = can't hurt players on your own team

	-- Camera kick per shot (degrees) and how fast it settles.
	RecoilKick = 1.8,
	RecoilRecover = 14,

	-- Sound IDs. Roblox doesn't ship gun sounds, so paste in your own from the
	-- Creator Store (search e.g. "pistol shot"), like "rbxassetid://123456".
	-- Leave "" for silence.
	Sounds = {
		Fire = "",
		Empty = "",
		Reload = "",
		Hit = "",
	},
	FireVolume = 0.8,

	Tag = "RealisticPistol",
}
