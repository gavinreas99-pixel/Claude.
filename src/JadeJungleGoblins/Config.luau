--[[
	Jade Jungle goblin settings. Tweak these numbers to tune the goblins.

	Spawn points: make a Folder at Workspace > JadeJungle > GoblinSpawns and
	put a few anchored, invisible Parts in it. One goblin lives at each Part.
	If that folder doesn't exist, goblins spawn around FallbackCenter instead.
]]

return {
	-- Where the spawn-point Parts live, as a path from Workspace.
	SpawnFolderPath = { "JadeJungle", "GoblinSpawns" },

	-- Used only when the spawn folder above is missing.
	FallbackCenter = Vector3.new(0, 10, 0),
	FallbackRadius = 40,
	FallbackCount = 6,

	GoblinsPerSpawn = 1,
	MaxGoblins = 12,
	RespawnTime = 20, -- seconds after death before a goblin returns
	CorpseTime = 6, -- seconds the ragdoll stays before disappearing

	-- 1 = about 4.6 studs tall (a little shorter than a player).
	Scale = 1.1,

	MaxHealth = 100,
	WanderSpeed = 7,
	ChaseSpeed = 15,
	WanderRadius = 25, -- how far from its spawn a goblin wanders
	AggroRange = 45, -- how close a player must be to get chased
	LeashRange = 90, -- goblins give up once the player is this far from the spawn
	ThinkInterval = 0.15,

	AttackRange = 4.5,
	AttackDamage = 12,
	AttackCooldown = 1.4,
	AttackDuration = 0.65, -- length of the sword-swing animation

	-- Clients skip animating goblins farther away than this (performance).
	AnimateDistance = 300,

	Tag = "JadeGoblin",
}
