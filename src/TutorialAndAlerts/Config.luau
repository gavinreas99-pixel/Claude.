--[[
	Tutorial and notification settings. Edit the text and numbers here.

	TUTORIAL STEPS
	The guided tutorial shows Steps in order, one card at a time. A step can have:

	  Title      Heading of the card.
	  Icon       A big emoji, or an image like "rbxassetid://123456".
	  Body       The explanation (rich text: <b>bold</b>, <i>italic</i>, <font color="#ffde28">colour</font>).
	             Use { Keyboard = "...", Touch = "...", Gamepad = "..." } for different text on
	             each device. Missing devices fall back to Keyboard.
	             {Islands} is replaced with the island list below, {Tool} with the pistol name.
	  Keys       Key hints drawn as keycaps, e.g. { "W", "A", "S", "D" } (per-device table allowed).
	  Tip        A short extra hint shown in gold under the explanation.
	  Highlight  Something to point at while the step is open:
	               { Gui = { "bag", "inventory" } }      a button on screen whose name or text contains a word
	               { Tag = "JadeGoblin" }                 the nearest thing with this CollectionService tag
	               { Path = { "JadeJungle", "GoblinSpawns" } } a part (or the first part in a folder) in Workspace
	  Goal       Something the player does to finish the step. It gets ticked off and the
	             tutorial moves on by itself. Players can always press Next to skip ahead.
	               { Type = "Move", Distance = 30 }       walk this many studs
	               { Type = "Jump" }
	               { Type = "Look", Degrees = 120 }       turn the camera
	               { Type = "Equip", Tool = "Pistol" }    hold a tool (leave Tool out for any tool)
	               { Type = "Open", Gui = { "bag" } }     open a window whose name contains a word
	               { Type = "Reach", Tag = "JadeGoblin", Radius = 40 }  (or Path = { ... })
	               { Type = "Level", Level = 2 }
	             Add Text = "..." to change how the goal is worded.
	  OnlyIf     Skip the step when something isn't in your game, e.g. { Tool = "Pistol" },
	             { Tag = "JadeGoblin" }, { Gui = { "bag" } } or { Path = { ... } }.
	  Dim        true/false: darken the screen behind the card. By default it darkens for
	             reading steps and stays clear for steps where the player has to move.
]]

local Config = {}

Config.Tutorial = {
	Enabled = true,
	ShowOnFirstJoin = true, -- open automatically for players who haven't finished it
	SaveProgress = true, -- remember (in a DataStore) who finished it, so it only shows once
	DataStoreName = "TutorialAndAlerts",
	StartDelay = 2, -- seconds after spawning before it opens
	AutoAdvanceDelay = 1.2, -- seconds to wait after a goal is done before moving on
	HelpButton = true, -- the round "?" button on the left that replays the tutorial
	HelpButtonPosition = UDim2.new(0, 14, 0.5, 0), -- move it if it covers your own buttons

	-- Hide the game's old tutorial screen so two tutorials don't show at once.
	-- Any ScreenGui whose name contains one of these words is turned off.
	HideOldTutorial = true,
	OldTutorialNames = { "tutorial" },
}

Config.ToolName = "Pistol" -- used for {Tool} in the text below

Config.Steps = {
	{
		Title = "Welcome, adventurer!",
		Icon = "👋",
		Body = "This short guide shows you how to play, one thing at a time.\n\n"
			.. "Some steps ask you to try something. A <b>goal box</b> shows what to do, and it ticks off "
			.. "when you've done it. Then the guide moves on by itself.",
		Tip = "Press Next and Back to move between steps, or X to skip. The ? button on the left replays this guide.",
	},
	{
		Title = "Walking",
		Icon = "🏃",
		Body = {
			Keyboard = "Hold <b>W</b> to walk forward. <b>A</b> and <b>D</b> walk left and right, <b>S</b> walks backwards. "
				.. "The arrow keys work too.\n\nYou always walk the way the camera faces.",
			Touch = "Put your thumb on the bottom-left of the screen and drag. A <b>joystick</b> appears, "
				.. "and you walk the way you drag it.\n\nYou always walk the way the camera faces.",
			Gamepad = "Push the <b>left stick</b> to walk. Push it a little to walk slowly, or all the way to run.",
		},
		Keys = { Keyboard = { "W", "A", "S", "D" }, Gamepad = { "Left stick" } },
		Goal = { Type = "Move", Distance = 30, Text = "Walk 30 studs in any direction" },
		Tip = "The goal bar fills up as you walk.",
	},
	{
		Title = "Jumping",
		Icon = "🦘",
		Body = {
			Keyboard = "Press <b>Space</b> to jump. Jump onto ledges, over rocks and across gaps. "
				.. "Hold <b>Space</b> to keep jumping.",
			Touch = "Tap the round <b>jump button</b> in the bottom-right corner to jump onto ledges, "
				.. "over rocks and across gaps.",
			Gamepad = "Press <b>A</b> to jump onto ledges, over rocks and across gaps.",
		},
		Keys = { Keyboard = { "Space" }, Gamepad = { "A" } },
		Goal = { Type = "Jump", Text = "Jump once" },
	},
	{
		Title = "Looking around",
		Icon = "🎥",
		Body = {
			Keyboard = "Hold the <b>right mouse button</b> and move the mouse to turn the camera. "
				.. "Scroll the <b>mouse wheel</b> to zoom in and out.\n\nZoom all the way in for first-person view.",
			Touch = "Drag one finger across an empty part of the screen to turn the camera. "
				.. "<b>Pinch</b> with two fingers to zoom in and out.",
			Gamepad = "Push the <b>right stick</b> to turn the camera. Press it in to zoom.",
		},
		Keys = { Keyboard = { "Right mouse", "Mouse wheel" }, Gamepad = { "Right stick" } },
		Goal = { Type = "Look", Degrees = 120, Text = "Turn the camera around" },
	},
	{
		Title = "Your {Tool}",
		Icon = "🔫",
		OnlyIf = { Tool = "Pistol" },
		Body = {
			Keyboard = "Your {Tool} is in the <b>hotbar</b> at the bottom of the screen. Press <b>1</b> or click it to take it out.\n\n"
				.. "<b>Click</b> to shoot at the middle of the crosshair. The box in the bottom-right shows how many "
				.. "bullets are left. Press <b>R</b> to reload.",
			Touch = "Your {Tool} is in the <b>hotbar</b> at the bottom of the screen. Tap it to take it out.\n\n"
				.. "<b>Tap</b> where you want to shoot. When you run out of bullets, tap the <b>RELOAD</b> button.",
			Gamepad = "Your {Tool} is in the <b>hotbar</b>. Press <b>LB</b> or <b>RB</b> to pick it, then <b>RT</b> to shoot.",
		},
		Keys = { Keyboard = { "1", "Click", "R" }, Gamepad = { "LB / RB", "RT" } },
		Goal = { Type = "Equip", Tool = "Pistol", Text = "Take out your {Tool}" },
		Tip = "Headshots do double damage.",
	},
	{
		Title = "Goblins",
		Icon = "👺",
		OnlyIf = { Tag = "JadeGoblin" },
		Highlight = { Tag = "JadeGoblin" },
		Body = "Goblins live in the <b>Jade Jungle</b>. The gold arrow points to the nearest one.\n\n"
			.. "When you get close, they run at you and swing their swords. Keep your distance and shoot them. "
			.. "Defeated goblins come back after a while.",
		Goal = { Type = "Reach", Tag = "JadeGoblin", Radius = 60, Text = "Get close to a goblin" },
		Tip = "Watch your health bar. If it gets low, back away and let it refill.",
	},
	{
		Title = "Your bag",
		Icon = "🎒",
		OnlyIf = { Gui = { "bag", "inventory", "backpack" } },
		Highlight = { Gui = { "bag", "inventory", "backpack" } },
		Body = "This button opens your <b>Bag</b>. It holds everything you collect.\n\n"
			.. "Click an item to see what it does. Use or equip it from there.",
		Goal = { Type = "Open", Gui = { "bag", "inventory", "backpack" }, Text = "Open your bag" },
	},
	{
		Title = "Quests",
		Icon = "📜",
		OnlyIf = { Gui = { "quest" } },
		Highlight = { Gui = { "quest" } },
		Body = "This button opens <b>Quests</b>. Each quest is a small job, like defeating goblins or collecting items.\n\n"
			.. "The bar on each quest shows your progress. When it fills, claim the reward to get "
			.. "<font color=\"#ffde28\"><b>XP</b></font>.",
		Goal = { Type = "Open", Gui = { "quest" }, Text = "Open your quests" },
	},
	{
		Title = "Levels and XP",
		Icon = "⭐",
		Body = "You earn <font color=\"#ffde28\"><b>XP</b></font> from quests and from defeating enemies. "
			.. "When you have enough, you <b>level up</b>, and a big banner shows what you unlocked.\n\n"
			.. "Higher levels unlock stronger gear and new places to explore.",
		Tip = "Quests usually give more XP than fighting.",
	},
	{
		Title = "Islands",
		Icon = "🏝",
		Body = "The world is made of <b>islands</b>. You unlock new ones as you level up:\n\n{Islands}\n\n"
			.. "When a new island opens, a banner tells you how to get there.",
	},
	{
		Title = "You're ready!",
		Icon = "🏆",
		Body = "That's everything you need to get started. Go take on the goblins and do some quests.\n\n"
			.. "You can replay this guide anytime with the <b>?</b> button on the left of the screen.",
	},
}

--------------------------------------------------------------------------------
-- Level and island notifications
--------------------------------------------------------------------------------

-- Where the player's level is found. The scripts look for, in order:
--   an attribute on the player with one of these names
--   a number value with one of these names in leaderstats
--   a number value with one of these names anywhere else under the player (e.g. a Data folder)
Config.LevelNames = { "Level", "Lvl", "LV" }

-- Islands and the level that unlocks each. When a player reaches the level, an
-- "Island unlocked" banner shows. Replace these with your game's islands.
-- Image is optional ("rbxassetid://..."), and Hint says how to get there.
Config.Islands = {
	{ Name = "Jade Jungle", Level = 1, Description = "Overgrown ruins full of goblins." },
	-- { Name = "Frost Peaks", Level = 10, Description = "Icy cliffs and snow trolls.", Image = "" },
	-- { Name = "Ember Isle", Level = 25, Description = "A volcano that never stops smoking." },
}
Config.IslandHint = "Open the map or use a portal to travel there."

-- Islands are also detected when your game unlocks them some other way:
--   an attribute on the player with "island" in its name set to true, e.g. "Island_FrostPeaks"
--   a value in a folder under the player with "island" in its name, e.g. UnlockedIslands > "Frost Peaks"
-- Server scripts can also show the banner themselves; see the Notify module.
Config.DetectIslands = true

-- Extra lines shown on the level-up banner when a player reaches these levels.
Config.LevelRewards = {
	-- [5] = "New quests at the jungle temple",
	-- [10] = "Frost Peaks unlocked",
}

-- Data saved by your game usually loads a few seconds after joining. Level and
-- island changes in this window are treated as loading, not as a level up.
Config.JoinGraceSeconds = 8

Config.BannerTime = 4 -- seconds a level-up / island banner stays up
Config.ToastTime = 4 -- seconds a small notification stays up
Config.Confetti = true

-- Sound IDs, e.g. "rbxassetid://123456" from the Creator Store. "" = silent.
Config.Sounds = {
	LevelUp = "",
	Island = "",
	Toast = "",
	StepDone = "",
}
Config.Volume = 0.6

return Config
