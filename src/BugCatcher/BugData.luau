--[[
	BugData: every bug in the game, in collection-book order.

	Fields:
	  Id       unique key, also used in saved data (don't rename once players have it)
	  Name     shown in the book and popups
	  Rarity   "Common" (any time), "Rare" (night only) or "Epic" (rain only)
	  Shape    body plan BugBuilder draws: Beetle, Bee, Butterfly, Dragonfly, Hopper, Ant, Worm
	  Move     "Fly" or "Crawl"
	  Scale    size multiplier
	  Speed    wandering speed in studs per second
	  Colors   colours for BugBuilder (Body, Accent, Wing, Glow, ...)
]]

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local BugData = {}

BugData.Rarities = {
	Common = {
		Order = 1,
		Color = rgb(112, 190, 96),
		Hint = "Any time",
		Glow = false,
		FleeRadius = 11, -- studs: how close a player can get before the bug runs
		FleeSpeed = 9.5,
	},
	Rare = {
		Order = 2,
		Color = rgb(112, 156, 255),
		Hint = "Only at night",
		Glow = true,
		FleeRadius = 13,
		FleeSpeed = 11.5,
	},
	Epic = {
		Order = 3,
		Color = rgb(255, 168, 40),
		Hint = "Only in the rain",
		Glow = true,
		FleeRadius = 14,
		FleeSpeed = 12.5,
	},
}

BugData.List = {
	{
		Id = "Ladybug",
		Name = "Ladybug",
		Rarity = "Common",
		Shape = "Beetle",
		Move = "Crawl",
		Scale = 1,
		Speed = 3.5,
		Spots = true,
		Colors = { Body = rgb(30, 28, 30), Shell = rgb(222, 38, 32), Accent = rgb(20, 20, 20) },
	},
	{
		Id = "Honeybee",
		Name = "Honeybee",
		Rarity = "Common",
		Shape = "Bee",
		Move = "Fly",
		Scale = 1,
		Speed = 7,
		Colors = { Body = rgb(246, 186, 36), Accent = rgb(40, 30, 22), Fuzz = rgb(196, 140, 44), Wing = rgb(228, 240, 255) },
	},
	{
		Id = "CabbageWhite",
		Name = "Cabbage White",
		Rarity = "Common",
		Shape = "Butterfly",
		Move = "Fly",
		Scale = 1.15,
		Speed = 5,
		Colors = { Body = rgb(70, 70, 72), Wing = rgb(250, 250, 242), Accent = rgb(52, 52, 56) },
	},
	{
		Id = "Grasshopper",
		Name = "Grasshopper",
		Rarity = "Common",
		Shape = "Hopper",
		Move = "Crawl",
		Scale = 1.2,
		Speed = 5,
		Colors = { Body = rgb(112, 172, 58), Accent = rgb(78, 128, 40) },
	},
	{
		Id = "BlueDragonfly",
		Name = "Blue Dragonfly",
		Rarity = "Common",
		Shape = "Dragonfly",
		Move = "Fly",
		Scale = 1.3,
		Speed = 9,
		Colors = { Body = rgb(40, 118, 222), Accent = rgb(24, 60, 120), Wing = rgb(220, 236, 255) },
	},
	{
		Id = "BlackAnt",
		Name = "Black Ant",
		Rarity = "Common",
		Shape = "Ant",
		Move = "Crawl",
		Scale = 1,
		Speed = 4.5,
		Colors = { Body = rgb(36, 30, 30), Accent = rgb(70, 50, 44) },
	},
	{
		Id = "Firefly",
		Name = "Firefly",
		Rarity = "Rare",
		Shape = "Bee",
		Move = "Fly",
		Scale = 1,
		Speed = 4,
		Colors = { Body = rgb(62, 52, 40), Accent = rgb(196, 64, 40), Fuzz = rgb(70, 58, 46), Wing = rgb(150, 132, 100), Glow = rgb(214, 255, 80) },
	},
	{
		Id = "LunaMoth",
		Name = "Luna Moth",
		Rarity = "Rare",
		Shape = "Butterfly",
		Move = "Fly",
		Scale = 1.45,
		Speed = 4,
		Tails = true,
		Colors = { Body = rgb(240, 240, 220), Wing = rgb(186, 240, 168), Accent = rgb(236, 196, 112), Glow = rgb(160, 255, 200) },
	},
	{
		Id = "Glowworm",
		Name = "Glowworm",
		Rarity = "Rare",
		Shape = "Worm",
		Move = "Crawl",
		Scale = 1.2,
		Speed = 2.5,
		Colors = { Body = rgb(58, 84, 88), Glow = rgb(80, 236, 255) },
	},
	{
		Id = "RainbowScarab",
		Name = "Rainbow Scarab",
		Rarity = "Epic",
		Shape = "Beetle",
		Move = "Crawl",
		Scale = 1.3,
		Speed = 4,
		Rainbow = true,
		Colors = { Body = rgb(40, 30, 60), Shell = rgb(170, 70, 255), Accent = rgb(60, 220, 200), Glow = rgb(220, 120, 255) },
	},
	{
		Id = "StormDragonfly",
		Name = "Storm Dragonfly",
		Rarity = "Epic",
		Shape = "Dragonfly",
		Move = "Fly",
		Scale = 1.5,
		Speed = 10,
		Colors = { Body = rgb(96, 70, 226), Accent = rgb(150, 220, 255), Wing = rgb(190, 214, 255), Glow = rgb(130, 196, 255) },
	},
	{
		Id = "CrystalButterfly",
		Name = "Crystal Butterfly",
		Rarity = "Epic",
		Shape = "Butterfly",
		Move = "Fly",
		Scale = 1.55,
		Speed = 5,
		Crystal = true,
		Colors = { Body = rgb(150, 220, 240), Wing = rgb(170, 238, 255), Accent = rgb(255, 255, 255), Glow = rgb(196, 248, 255) },
	},
}

BugData.ById = {}
BugData.ByRarity = { Common = {}, Rare = {}, Epic = {} }
for index, bug in BugData.List do
	bug.Order = index
	BugData.ById[bug.Id] = bug
	table.insert(BugData.ByRarity[bug.Rarity], bug)
end

return BugData
