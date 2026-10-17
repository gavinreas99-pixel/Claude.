--[[
	Notifications: a big "LEVEL UP!" banner each time the player levels up, an
	"ISLAND UNLOCKED" banner for each new island, and small pop-ups in the
	top-right corner. Banners queue up, so several at once show one after another.
	This is a Script with RunContext = Client, so it runs from ReplicatedStorage.

	Levels and islands are detected automatically (see Config). Your own
	scripts can also show them; see the Notify module.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local Style = require(folder:WaitForChild("Style"))
local PlayerStats = require(folder:WaitForChild("PlayerStats"))
local Notify = require(folder:WaitForChild("Notify"))

local player = Players.LocalPlayer
local C = Style.Colors
local make = Style.make

local gui = make("ScreenGui", {
	Name = "LevelAlerts",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

local function tween(inst, time, props, style, direction)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Banners are sized for a PC screen; shrink them to fit phones.
local function screenScale()
	local view = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min(view.X / 900, view.Y / 640), 0.55, 1)
end

--------------------------------------------------------------------------------
-- Confetti
--------------------------------------------------------------------------------

local CONFETTI_COLORS = {
	C.Gold, C.Close, Color3.fromRGB(80, 170, 255), C.Green, Color3.new(1, 1, 1), Color3.fromRGB(255, 140, 30),
}

local function confetti(center, count)
	if not Config.Confetti then
		return
	end
	local layer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, gui)
	local bits = {}
	for _ = 1, count do
		local angle = math.rad(math.random(200, 340)) -- mostly upwards
		local speed = math.random(260, 620)
		local bit = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(math.random(6, 11), math.random(10, 16)),
			BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
		}, layer)
		table.insert(bits, {
			frame = bit,
			pos = center,
			vel = Vector2.new(math.cos(angle), math.sin(angle)) * speed,
			spin = math.random(-540, 540),
		})
	end
	local life, age = 2.2, 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		age += dt
		for _, b in bits do
			b.vel = Vector2.new(b.vel.X * (1 - 1.6 * dt), b.vel.Y + 900 * dt)
			b.pos += b.vel * dt
			b.frame.Position = UDim2.fromOffset(b.pos.X, b.pos.Y)
			b.frame.Rotation += b.spin * dt
			b.frame.BackgroundTransparency = math.clamp((age - life * 0.6) / (life * 0.4), 0, 1)
		end
		if age >= life then
			connection:Disconnect()
			layer:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- Banner queue
--------------------------------------------------------------------------------

local queue = {}
local running = false

local function runQueue()
	running = true
	while #queue > 0 do
		local show = table.remove(queue, 1)
		local ok, err = pcall(show)
		if not ok then
			warn("[TutorialAndAlerts] banner failed: " .. tostring(err))
		end
		task.wait(0.25)
	end
	running = false
end

local function enqueue(show)
	table.insert(queue, show)
	if not running then
		task.spawn(runQueue)
	end
end

-- Fades a banner in, holds it, then fades it out and removes it.
local function present(root, scale, hold)
	local y = root.Position
	root.GroupTransparency = 1
	root.Position = y + UDim2.fromOffset(0, -30)
	scale.Scale = screenScale() * 0.8
	root.Parent = gui
	tween(root, 0.3, { GroupTransparency = 0, Position = y })
	tween(scale, 0.45, { Scale = screenScale() }, Enum.EasingStyle.Back)
	task.wait(hold)
	tween(root, 0.4, { GroupTransparency = 1, Position = y + UDim2.fromOffset(0, -24) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(0.45)
	root:Destroy()
end

local function bannerCenter(root, yOffset)
	local view = Workspace.CurrentCamera.ViewportSize
	return Vector2.new(view.X * 0.5, view.Y * root.Position.Y.Scale + yOffset * screenScale())
end

--------------------------------------------------------------------------------
-- Level-up banner
--------------------------------------------------------------------------------

local function islandInfo(name)
	local squashed = name:lower():gsub("[%s_%-]", "")
	for _, island in Config.Islands do
		if island.Name:lower():gsub("[%s_%-]", "") == squashed then
			return island
		end
	end
	return nil
end

local function nextIsland(level)
	local best = nil
	for _, island in Config.Islands do
		if island.Level and island.Level > level and (not best or island.Level < best.Level) then
			best = island
		end
	end
	return best
end

local function showLevelUp(level, previous)
	Style.playSound(Config.Sounds.LevelUp, Config.Volume)

	local root = make("CanvasGroup", {
		Name = "LevelUp",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.1, 0),
		Size = UDim2.fromOffset(480, 420),
		BackgroundTransparency = 1,
	})
	local scale = make("UIScale", {}, root)

	-- Spinning light rays and a soft glow behind the badge.
	local rays = {}
	for i = 0, 5 do
		local ray = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(240, 100),
			Size = UDim2.fromOffset(320, 18),
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
			Rotation = i * 30,
		}, root)
		make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(rays, ray)
	end
	local glow = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(240, 100),
		Size = UDim2.fromOffset(190, 190),
		BackgroundColor3 = C.Gold,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
	}, root)
	Style.corner(glow, UDim.new(0.5, 0))

	-- Round gold badge with the new level number.
	local badge = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(240, 100),
		Size = UDim2.fromOffset(136, 136),
		BorderSizePixel = 0,
	}, root)
	Style.gradient(badge, C.GoldTop, C.GoldBottom)
	Style.border(badge, C.GoldBorder, 4)
	Style.corner(badge, UDim.new(0.5, 0))
	local badgeScale = make("UIScale", { Scale = 0 }, badge)
	Style.label({
		Text = "LEVEL",
		FontFace = Style.FontTitle,
		TextSize = 16,
		TextColor3 = C.DarkText,
		Position = UDim2.fromScale(0, 0.17),
		Size = UDim2.new(1, 0, 0, 18),
	}, badge)
	Style.label({
		Text = tostring(level),
		FontFace = Style.FontTitle,
		TextScaled = true,
		TextColor3 = C.DarkText,
		Position = UDim2.fromScale(0.1, 0.33),
		Size = UDim2.fromScale(0.8, 0.48),
	}, badge)

	-- Red "LEVEL UP!" ribbon.
	local ribbon = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(240, 172),
		Size = UDim2.fromOffset(300, 48),
		BorderSizePixel = 0,
	}, root)
	Style.gradient(ribbon, C.HeaderTop, C.HeaderBottom)
	Style.border(ribbon, C.WindowBorder, 2)
	Style.corner(ribbon, UDim.new(0, 6))
	Style.label({
		Text = "LEVEL UP!",
		FontFace = Style.FontTitle,
		TextSize = 30,
		TextStrokeTransparency = 0.3,
		Size = UDim2.fromScale(1, 1),
	}, ribbon)

	-- Card explaining what the level means.
	local card = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(240, 232),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
	}, root)
	Style.gradient(card, C.CardTop, C.CardBottom)
	Style.border(card, C.CardBorder, 2)
	Style.corner(card)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, card)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, card)

	local function line(text, color, size, order)
		Style.label({
			Text = text,
			TextColor3 = color,
			TextSize = size,
			FontFace = Style.FontBold,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
		}, card)
	end

	local gained = level - previous
	line(
		gained > 1 and string.format("You went up <b>%d levels</b> and reached <b>level %d</b>!", gained, level)
			or string.format("You reached <b>level %d</b>!", level),
		C.Text,
		18,
		1
	)
	local order = 2
	for l = previous + 1, level do
		local reward = Config.LevelRewards[l]
		if reward then
			line("★  " .. reward, C.Gold, 16, order)
			order += 1
		end
	end
	local upcoming = nextIsland(level)
	if upcoming then
		line(
			string.format("Next: <b>%s</b> unlocks at level %d (%d to go)", upcoming.Name, upcoming.Level, upcoming.Level - level),
			C.SubText,
			15,
			order
		)
	else
		line("Keep questing to earn more XP and level up again.", C.SubText, 15, order)
	end

	local spin = RunService.RenderStepped:Connect(function(dt)
		for _, ray in rays do
			ray.Rotation += 25 * dt
		end
		glow.BackgroundTransparency = 0.72 + math.sin(os.clock() * 4) * 0.08
	end)
	root.Destroying:Connect(function()
		spin:Disconnect()
	end)

	task.delay(0.1, function()
		tween(badgeScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
		confetti(bannerCenter(root, 100), 50)
	end)
	present(root, scale, Config.BannerTime)
end

--------------------------------------------------------------------------------
-- Island-unlocked banner
--------------------------------------------------------------------------------

local function showIsland(name, description)
	local info = islandInfo(name) or {}
	description = description or info.Description
	Style.playSound(Config.Sounds.Island, Config.Volume)

	local root = make("CanvasGroup", {
		Name = "IslandUnlocked",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.12, 0),
		Size = UDim2.fromOffset(540, 250),
		BackgroundTransparency = 1,
	})
	local scale = make("UIScale", {}, root)

	local window = make("Frame", { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BorderSizePixel = 0 }, root)
	Style.gradient(window, C.WindowTop, C.WindowBottom)
	Style.border(window, C.WindowBorder, 3)
	Style.corner(window)

	local header = make("Frame", { Size = UDim2.new(1, 0, 0, 46), BorderSizePixel = 0, ClipsDescendants = true }, window)
	Style.gradient(header, C.HeaderTop, C.HeaderBottom)
	Style.corner(header, UDim.new(0, 6))
	Style.label({
		Text = "🔓  NEW ISLAND UNLOCKED",
		FontFace = Style.FontTitle,
		TextSize = 22,
		TextStrokeTransparency = 0.3,
		Size = UDim2.fromScale(1, 1),
	}, header)
	local shine = make("Frame", {
		Position = UDim2.fromScale(-0.4, 0),
		Size = UDim2.fromScale(0.3, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Rotation = 0,
	}, header)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, shine)

	-- Picture of the island (or a big island emoji).
	local slot = make("Frame", {
		Position = UDim2.fromOffset(18, 62),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = C.Slot,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, window)
	Style.border(slot, C.Gold, 2)
	Style.corner(slot, UDim.new(0, 6))
	Style.icon(info.Image ~= nil and info.Image ~= "" and info.Image or "🏝️", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(info.Image and info.Image ~= "" and 1 or 0.7, info.Image and info.Image ~= "" and 1 or 0.7),
	}, slot)

	local text = make("Frame", {
		Position = UDim2.fromOffset(186, 60),
		Size = UDim2.new(1, -204, 1, -76),
		BackgroundTransparency = 1,
	}, window)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, text)
	local function line(content, color, size, font, order)
		Style.label({
			Text = content,
			TextColor3 = color,
			TextSize = size,
			FontFace = font,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
		}, text)
	end
	line(name, C.Gold, 32, Style.FontTitle, 1)
	if description and description ~= "" then
		line(description, C.SubText, 16, Style.FontBody, 2)
	end
	if info.Level then
		line(string.format("Unlocked for reaching <b>level %d</b>.", info.Level), C.Text, 15, Style.FontBold, 3)
	end
	if Config.IslandHint and Config.IslandHint ~= "" then
		line("➜  " .. Config.IslandHint, C.Green, 15, Style.FontBold, 4)
	end

	task.delay(0.35, function()
		tween(shine, 0.9, { Position = UDim2.fromScale(1.2, 0) }, Enum.EasingStyle.Sine)
		confetti(bannerCenter(root, 40), 60)
	end)
	present(root, scale, Config.BannerTime + 1)
end

--------------------------------------------------------------------------------
-- Small pop-ups (top-right)
--------------------------------------------------------------------------------

local toasts = make("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 64),
	Size = UDim2.new(0, 320, 1, -80),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, toasts)
local toastScale = make("UIScale", {}, toasts) -- smaller on phones so pop-ups don't cover the banners
local toastCount = 0

local function showToast(title, body)
	Style.playSound(Config.Sounds.Toast, Config.Volume)
	toastScale.Scale = screenScale()
	toastCount += 1
	local holder = make("Frame", {
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundTransparency = 1,
		LayoutOrder = toastCount,
	}, toasts)
	local card = make("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(340, 0),
		GroupTransparency = 1,
		BorderSizePixel = 0,
	}, holder)
	Style.gradient(card, C.CardTop, C.CardBottom)
	Style.corner(card)
	make("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = C.Gold, BorderSizePixel = 0 }, card)
	Style.label({
		Text = tostring(title or ""),
		FontFace = Style.FontTitle,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.new(1, -30, 0, 20),
	}, card)
	Style.label({
		Text = tostring(body or ""),
		TextColor3 = C.SubText,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(18, 30),
		Size = UDim2.new(1, -30, 0, 36),
	}, card)

	tween(card, 0.35, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, Enum.EasingStyle.Back)
	task.delay(Config.ToastTime, function()
		tween(card, 0.3, { Position = UDim2.fromOffset(340, 0), GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.35)
		holder:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Working out when to show them
--------------------------------------------------------------------------------

local joinedAt = os.clock()
local function loading()
	return os.clock() - joinedAt < Config.JoinGraceSeconds
end

local shownLevel = nil -- highest level the player is known to have reached
local knownIslands = {} -- squashed island name -> true once announced (or already owned)

local function squash(name)
	return (name:lower():gsub("[%s_%-]", ""))
end

local function islandUnlocked(name, description)
	if not name or name == "" or knownIslands[squash(name)] then
		return
	end
	knownIslands[squash(name)] = true
	enqueue(function()
		showIsland(name, description)
	end)
end

local function knowIslandsUpTo(level)
	for _, island in Config.Islands do
		if island.Level and island.Level <= level then
			knownIslands[squash(island.Name)] = true
		end
	end
end

local function levelReached(level, fromValue)
	level = math.floor(level)
	if shownLevel == nil or (fromValue and loading()) then
		-- First reading (or data still loading): this is where the player starts.
		shownLevel = level
		knowIslandsUpTo(level)
		return
	end
	if level < shownLevel then
		shownLevel = level -- level was reset (e.g. a rebirth), so count up from here again
		return
	end
	if level == shownLevel then
		return -- already shown
	end
	local previous = shownLevel
	shownLevel = level
	enqueue(function()
		showLevelUp(level, previous)
	end)
	for _, island in Config.Islands do
		if island.Level and island.Level > previous and island.Level <= level then
			islandUnlocked(island.Name)
		end
	end
end

PlayerStats.watchLevel(player, Config.LevelNames, function(level)
	levelReached(level, true)
end)

-- "Island_FrostPeaks" / "FrostPeaksUnlocked" -> "Frost Peaks" (or the name in Config.Islands).
local function islandNameFrom(raw)
	local name = raw:gsub("[Ii][Ss][Ll][Aa][Nn][Dd][Ss]?", ""):gsub("[Uu]nlocked", ""):gsub("[_%-]+", " ")
	name = name:gsub("(%l)(%u)", "%1 %2"):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return nil
	end
	local info = islandInfo(name)
	return info and info.Name or name
end

local function found(name)
	if not name then
		return
	end
	if loading() then
		knownIslands[squash(name)] = true -- owned before this visit
	else
		islandUnlocked(name)
	end
end

local function watchIslandValue(value)
	local parent = value.Parent
	local inFolder = parent and parent ~= player and parent.Name:lower():find("island") ~= nil
	local named = value.Name:lower():find("island") ~= nil
	if not inFolder and not named then
		return
	end
	local function name()
		if inFolder then
			if value:IsA("StringValue") and value.Value ~= "" then
				return value.Value
			end
			return value.Name
		end
		return islandNameFrom(value.Name)
	end
	if value:IsA("BoolValue") then
		local function check()
			if value.Value then
				found(name())
			end
		end
		value.Changed:Connect(check)
		check()
	elseif inFolder and (value:IsA("ValueBase") or value:IsA("Folder") or value:IsA("Configuration")) then
		if not value:IsA("NumberValue") and not value:IsA("IntValue") then
			found(name()) -- just being in the folder means it's unlocked
		end
	end
end

if Config.DetectIslands then
	player.AttributeChanged:Connect(function(attribute)
		if attribute:lower():find("island") and player:GetAttribute(attribute) == true then
			found(islandNameFrom(attribute))
		end
	end)
	for attribute, value in player:GetAttributes() do
		if attribute:lower():find("island") and value == true then
			found(islandNameFrom(attribute))
		end
	end
	local function candidate(value)
		return (value:IsA("ValueBase") or value:IsA("Folder") or value:IsA("Configuration"))
			and not value:FindFirstAncestorOfClass("PlayerGui")
			and not value:FindFirstAncestorOfClass("Backpack")
	end
	player.DescendantAdded:Connect(function(value)
		if candidate(value) then
			task.defer(watchIslandValue, value) -- let its name and value replicate first
		end
	end)
	for _, value in player:GetDescendants() do
		if candidate(value) then
			watchIslandValue(value)
		end
	end
end

--------------------------------------------------------------------------------
-- Calls from server scripts (Notify) and the tutorial
--------------------------------------------------------------------------------

local function handle(kind, ...)
	if kind == "LevelUp" then
		local level = tonumber((...))
		if level then
			if shownLevel == nil then
				shownLevel = level - 1
			end
			levelReached(level, false)
		end
	elseif kind == "Island" then
		local name, description = ...
		if typeof(name) == "string" then
			islandUnlocked(name, typeof(description) == "string" and description or nil)
		end
	elseif kind == "Toast" then
		local title, body = ...
		showToast(title, body)
	end
end

Notify.Remote.OnClientEvent:Connect(handle)
Notify.LocalEvent.Event:Connect(handle)
