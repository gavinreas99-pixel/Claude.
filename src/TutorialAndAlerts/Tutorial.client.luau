--[[
	Guided tutorial. Shows one card at a time with a picture, a clear
	explanation, key hints for the player's device, and often a goal to try
	("Walk 30 studs", "Open your bag") that ticks off by itself. While a step is
	open it can light up a button on screen or point a gold arrow and trail at
	something in the world.

	It opens on a player's first visit (the server remembers who finished it),
	and the round "?" button on the left replays it. Steps live in Config.Steps.
	This is a Script with RunContext = Client, so it runs from ReplicatedStorage.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local Style = require(folder:WaitForChild("Style"))
local PlayerStats = require(folder:WaitForChild("PlayerStats"))
local Notify = require(folder:WaitForChild("Notify"))

local settings = Config.Tutorial
if not settings.Enabled then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local C = Style.Colors
local make = Style.make

local CARD_WIDTH = 540
local SPOT_PAD = 8 -- gap between a highlighted button and the gold ring

local gui = make("ScreenGui", {
	Name = "GuideOverlay",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 15,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local getLevel = PlayerStats.watchLevel(player, Config.LevelNames, function() end)

local function tween(inst, time, props, style, direction)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function camera()
	return Workspace.CurrentCamera
end

local function screenScale()
	local view = camera().ViewportSize
	return math.clamp(math.min(view.X / 720, view.Y / 600), 0.55, 1)
end

local function rootPart()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

--------------------------------------------------------------------------------
-- Device-specific text
--------------------------------------------------------------------------------

local function device()
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif last == Enum.UserInputType.Keyboard or last.Name:sub(1, 5) == "Mouse" then
		return "Keyboard"
	end
	return (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) and "Touch" or "Keyboard"
end

local function isPerDevice(value)
	return typeof(value) == "table" and (value.Keyboard ~= nil or value.Touch ~= nil or value.Gamepad ~= nil)
end

-- Text falls back to the keyboard version; key hints don't (no "W A S D" on a phone).
local function pick(value, fallback)
	if isPerDevice(value) then
		local own = value[device()]
		if own == nil and fallback then
			return value.Keyboard
		end
		return own
	end
	return value
end

local function islandList()
	local islands = table.clone(Config.Islands)
	table.sort(islands, function(a, b)
		return (a.Level or 1) < (b.Level or 1)
	end)
	local lines = {}
	for _, island in islands do
		table.insert(lines, string.format("   •  <b>%s</b>  –  level %d", island.Name, island.Level or 1))
	end
	return table.concat(lines, "\n")
end

local function fill(text)
	text = tostring(text or "")
	text = text:gsub("{Tool}", function()
		return Config.ToolName
	end)
	text = text:gsub("{Islands}", islandList)
	return text
end

--------------------------------------------------------------------------------
-- Finding things the steps point at
--------------------------------------------------------------------------------

local function ours(inst)
	return inst:IsDescendantOf(gui) or inst:FindFirstAncestor("GuideMarker") ~= nil or inst:FindFirstAncestor("LevelAlerts") ~= nil
end

-- True when a GUI element is actually showing on screen.
local function onScreen(element)
	local node = element
	while node and node ~= playerGui do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("LayerCollector") and not node.Enabled then
			return false
		end
		node = node.Parent
	end
	if node ~= playerGui then
		return false
	end
	local size = element.AbsoluteSize
	return size.X > 4 and size.Y > 4
end

local function hasWord(element, words)
	local name = element.Name:lower()
	local text = (element:IsA("TextButton") or element:IsA("TextLabel")) and element.Text:lower() or ""
	for _, word in words do
		word = word:lower()
		if name:find(word, 1, true) or text:find(word, 1, true) then
			return true
		end
	end
	return false
end

-- The smallest visible button whose name or text has one of the words.
local function findButton(words)
	local best, bestArea = nil, math.huge
	for _, element in playerGui:GetDescendants() do
		if element:IsA("GuiButton") and element:FindFirstAncestorWhichIsA("ScreenGui") and not ours(element) and onScreen(element) then
			local matched = hasWord(element, words)
			if not matched then
				local label = element:FindFirstChildWhichIsA("TextLabel")
				matched = label ~= nil and hasWord(label, words)
			end
			local size = element.AbsoluteSize
			if matched and size.X * size.Y < bestArea then
				best, bestArea = element, size.X * size.Y
			end
		end
	end
	return best
end

-- Open windows (big visible panels, not buttons) whose name, or whose
-- ScreenGui's name, has one of the words.
local function findWindows(words)
	local function window(element)
		if not element:IsA("GuiObject") or element:IsA("GuiButton") then
			return false
		end
		local size = element.AbsoluteSize
		if size.X < 160 or size.Y < 120 then
			return false
		end
		local panel = element.BackgroundTransparency < 0.95
			or ((element:IsA("ImageLabel") or element:IsA("ImageButton")) and element.Image ~= "" and element.ImageTransparency < 0.95)
		return panel and onScreen(element)
	end
	local found = {}
	for _, layer in playerGui:GetChildren() do
		if layer:IsA("ScreenGui") and layer.Enabled and not ours(layer) then
			local layerMatches = hasWord(layer, words)
			for _, element in layer:GetDescendants() do
				if (layerMatches or hasWord(element, words)) and window(element) then
					found[element] = true
				end
			end
		end
	end
	return found
end

-- Screen rectangle of a GUI element in this overlay's coordinates.
local function guiRect(element)
	local position = element.AbsolutePosition
	local layer = element:FindFirstAncestorWhichIsA("ScreenGui")
	if layer and not layer.IgnoreGuiInset then
		position += GuiService:GetGuiInset()
	end
	return position, element.AbsoluteSize
end

local function resolvePath(path)
	local node = Workspace
	for _, name in path do
		node = node:FindFirstChild(name)
		if not node then
			return nil
		end
	end
	return node
end

local function partOf(inst)
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function alive(inst)
	local humanoid = inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid")
	return not humanoid or humanoid.Health > 0
end

-- The nearest part for a { Tag = ... } or { Path = ... } spec.
local function findWorld(spec)
	local candidates = {}
	if spec.Tag then
		candidates = CollectionService:GetTagged(spec.Tag)
	elseif spec.Path then
		local node = resolvePath(spec.Path)
		if node then
			candidates = (node:IsA("Folder") or (node:IsA("Model") and not node:FindFirstChildOfClass("Humanoid"))) and node:GetChildren() or { node }
		end
	end
	local root = rootPart()
	local best, bestDistance = nil, math.huge
	for _, inst in candidates do
		if inst:IsDescendantOf(Workspace) and alive(inst) then
			local part = partOf(inst)
			if part then
				local distance = root and (part.Position - root.Position).Magnitude or 0
				if distance < bestDistance then
					best, bestDistance = part, distance
				end
			end
		end
	end
	return best
end

local function hasTool(name)
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") and (not name or tool.Name == name) then
					return true
				end
			end
		end
	end
	return false
end

-- Steps with OnlyIf are left out when the thing they explain isn't in this game.
local function available(step)
	local only = step.OnlyIf
	if not only then
		return true
	elseif only.Tool then
		return hasTool(only.Tool)
	elseif only.Tag then
		return #CollectionService:GetTagged(only.Tag) > 0
	elseif only.Gui then
		return findButton(only.Gui) ~= nil or next(findWindows(only.Gui)) ~= nil
	elseif only.Path then
		return resolvePath(only.Path) ~= nil
	end
	return true
end

--------------------------------------------------------------------------------
-- Overlay pieces: dimmed screen, gold ring, arrows
--------------------------------------------------------------------------------

local dims = {}
for i = 1, 4 do
	dims[i] = make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 1,
	}, gui)
end

local ring = make("Frame", { BackgroundTransparency = 1, Visible = false, ZIndex = 2 }, gui)
local ringStroke = make("UIStroke", { Color = C.Gold, Thickness = 3 }, ring)
Style.corner(ring, UDim.new(0, 10))

local function rotate(v, degrees)
	local r = math.rad(degrees)
	local cos, sin = math.cos(r), math.sin(r)
	return Vector2.new(v.X * cos - v.Y * sin, v.X * sin + v.Y * cos)
end

-- A double chevron ">>" made of four bars, so it can point any way.
local function newChevron(parent, z)
	local bars = {}
	for i = 1, 4 do
		bars[i] = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(24, 8),
			BackgroundColor3 = C.Gold,
			BackgroundTransparency = i > 2 and 0.4 or 0,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = z,
		}, parent)
		Style.corner(bars[i], UDim.new(0.5, 0))
		make("UIStroke", { Color = C.Outline, Thickness = 1.5, Transparency = 0.35 }, bars[i])
	end
	return bars
end

-- angle: 0 points right, 90 points down.
local function placeChevron(bars, tip, angle)
	local a = math.rad(angle)
	local dir = Vector2.new(math.cos(a), math.sin(a))
	for k = 0, 1 do
		local point = tip - dir * (k * 14)
		for s = 0, 1 do
			local back = rotate(-dir, s == 0 and 45 or -45)
			local center = point + back * 9
			local bar = bars[k * 2 + s + 1]
			bar.Position = UDim2.fromOffset(center.X, center.Y)
			bar.Rotation = math.deg(math.atan2(back.Y, back.X))
			bar.Visible = true
		end
	end
end

local function hideChevron(bars)
	for _, bar in bars do
		bar.Visible = false
	end
end

local guiArrow = newChevron(gui, 3)
local edgeArrow = newChevron(gui, 3)
local edgeLabel = Style.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(160, 40),
	FontFace = Style.FontTitle,
	TextSize = 15,
	TextStrokeTransparency = 0.2,
	Visible = false,
	ZIndex = 3,
}, gui)

--------------------------------------------------------------------------------
-- The card
--------------------------------------------------------------------------------

local card = make("CanvasGroup", {
	Name = "Card",
	Size = UDim2.fromOffset(CARD_WIDTH, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 10,
}, gui)
Style.gradient(card, C.WindowTop, C.WindowBottom)
Style.corner(card, UDim.new(0, 10))
local cardScale = make("UIScale", {}, card)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, card)

-- The card's border is a frame behind it, since a CanvasGroup would clip a stroke.
local cardBorder = make("Frame", {
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 9,
}, gui)
make("UIStroke", { Color = C.WindowBorder, Thickness = 3 }, cardBorder)
Style.corner(cardBorder, UDim.new(0, 10))

local header = make("Frame", { Size = UDim2.new(1, 0, 0, 42), BorderSizePixel = 0, LayoutOrder = 1 }, card)
Style.gradient(header, C.HeaderTop, C.HeaderBottom)
Style.label({
	Text = "📘  TUTORIAL",
	FontFace = Style.FontTitle,
	TextSize = 17,
	TextStrokeTransparency = 0.4,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(16, 0),
	Size = UDim2.new(0.5, 0, 1, 0),
}, header)
local stepLabel = Style.label({
	FontFace = Style.FontBold,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(255, 214, 214),
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -52, 0, 0),
	Size = UDim2.new(0.5, -60, 1, 0),
}, header)
local closeButton = make("TextButton", {
	Text = "X",
	FontFace = Style.FontTitle,
	TextSize = 22,
	TextColor3 = C.Text,
	TextStrokeTransparency = 0.3,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -6, 0.5, 0),
	Size = UDim2.fromOffset(40, 40),
}, header)

local helpButton = make("TextButton", {
	Name = "TutorialHelp",
	Text = "?",
	FontFace = Style.FontTitle,
	TextSize = 28,
	TextColor3 = C.DarkText,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = settings.HelpButtonPosition or UDim2.new(0, 14, 0.5, 0),
	Size = UDim2.fromOffset(48, 48),
	Visible = false,
	ZIndex = 4,
}, gui)
Style.gradient(helpButton, C.GoldTop, C.GoldBottom)
Style.border(helpButton, C.GoldBorder, 3)
Style.corner(helpButton, UDim.new(0.5, 0))
Style.label({
	Text = "HELP",
	FontFace = Style.FontTitle,
	TextSize = 11,
	TextStrokeTransparency = 0.3,
	Position = UDim2.new(0, -10, 1, 4),
	Size = UDim2.new(1, 20, 0, 14),
	ZIndex = 4,
}, helpButton)

--------------------------------------------------------------------------------
-- Tutorial state
--------------------------------------------------------------------------------

local open = false
local active = {} -- the steps shown this time (OnlyIf ones left out)
local current = 0
local stepToken = 0 -- changes every step, so delayed callbacks from old steps do nothing
local stepCleanup = {}
local goal = { progress = 0, done = false, status = "" }
local highlight = nil -- what the open step points at
local dimOn = false
local body = nil
local ui = {}

local showStep, finish, renderCard

local function cleanStep()
	for _, item in stepCleanup do
		if typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
		elseif typeof(item) == "Instance" then
			item:Destroy()
		elseif type(item) == "function" then
			item()
		end
	end
	table.clear(stepCleanup)
	highlight = nil
end

local function placeCard(where)
	if where == "top" then
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, 64)
	elseif where == "center" then
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
	else
		card.AnchorPoint = Vector2.new(0.5, 1)
		card.Position = UDim2.new(0.5, 0, 1, -96) -- above the hotbar
	end
	cardScale.Scale = screenScale()
end

--------------------------------------------------------------------------------
-- Goal box and buttons
--------------------------------------------------------------------------------

local function updateGoalUI()
	if not ui.fill or not ui.fill.Parent then
		return
	end
	local done = goal.done
	ui.fill.Size = UDim2.fromScale(goal.progress, 1)
	ui.fill.BackgroundColor3 = done and C.Green or C.Gold
	ui.status.Text = done and "DONE!" or goal.status
	ui.status.TextColor3 = done and C.Green or C.SubText
	ui.checkMark.Visible = done
	ui.check.BackgroundColor3 = done and C.Green or C.Track
	ui.goalStroke.Color = done and C.Green or C.SlotBorder
end

local function updateNext()
	if not ui.next or not ui.next.Parent then
		return
	end
	local step = active[current]
	local last = current == #active
	local ready = step.Goal == nil or goal.done
	ui.next.Text = last and "Finish  ✓" or (ready and "Next  ›" or "Skip step  ›")
	Style.setGold(ui.next, ready or last)
	if ready and not ui.pulsed and step.Goal then
		ui.pulsed = true
		local scale = make("UIScale", {}, ui.next)
		tween(scale, 0.15, { Scale = 1.12 }).Completed:Connect(function()
			tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
end

local function completeGoal()
	if goal.done then
		return
	end
	goal.done = true
	goal.progress = 1
	updateGoalUI()
	updateNext()
	Style.playSound(Config.Sounds.StepDone, Config.Volume)
	if ui.check and ui.check.Parent then
		local pop = make("UIScale", { Scale = 1.5 }, ui.check)
		tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	local token = stepToken
	task.delay(settings.AutoAdvanceDelay, function()
		if open and token == stepToken and current < #active and not ui.confirming then
			showStep(current + 1)
		end
	end)
end

local function setProgress(progress, status)
	if goal.done then
		return
	end
	goal.progress = math.clamp(progress, 0, 1)
	goal.status = status or ""
	if goal.progress >= 1 then
		completeGoal()
	else
		updateGoalUI()
	end
end

local GOAL_TEXT = {
	Move = function(g)
		return string.format("Walk %d studs", g.Distance or 30)
	end,
	Jump = function()
		return "Jump once"
	end,
	Look = function()
		return "Turn the camera around"
	end,
	Equip = function(g)
		return g.Tool and ("Take out your " .. g.Tool) or "Take out a tool"
	end,
	Open = function()
		return "Open the window"
	end,
	Reach = function()
		return "Follow the arrow"
	end,
	Level = function(g)
		return string.format("Reach level %d", g.Level or 2)
	end,
}

local function goalText(g)
	if g.Text then
		return fill(g.Text)
	end
	local text = GOAL_TEXT[g.Type]
	return text and text(g) or "Try it out"
end

--------------------------------------------------------------------------------
-- Drawing a step's card
--------------------------------------------------------------------------------

local function keycap(text, parent, order)
	local cap = Style.label({
		Text = text,
		FontFace = Style.FontTitle,
		TextSize = 14,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		LayoutOrder = order,
	}, parent)
	Style.gradient(cap, C.ButtonTop, C.ButtonBottom)
	Style.border(cap, Color3.fromRGB(110, 112, 122), 2)
	Style.corner(cap, UDim.new(0, 6))
	make("UIPadding", { PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11) }, cap)
	return cap
end

local function newBody()
	if body then
		body:Destroy()
	end
	table.clear(ui)
	body = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, card)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 16),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, body)
	make("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	return body
end

local function renderConfirm()
	newBody()
	ui.confirming = true
	stepLabel.Text = ""
	Style.label({
		Text = "Skip the tutorial?",
		FontFace = Style.FontTitle,
		TextSize = 24,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
	}, body)
	Style.label({
		Text = "You can watch it again anytime with the round <b>?</b> button on the left of the screen.",
		TextColor3 = C.SubText,
		TextSize = 17,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	}, body)
	local row = make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 3 }, body)
	local keep = Style.button("Keep going", true, { Size = UDim2.new(0.5, -6, 1, 0) }, row)
	local skip = Style.button("Skip tutorial", false, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, -6, 1, 0) }, row)
	keep.Activated:Connect(function()
		renderCard()
	end)
	skip.Activated:Connect(function()
		finish(true)
	end)
end

function renderCard()
	local step = active[current]
	if not step then
		return
	end
	newBody()
	stepLabel.Text = string.format("STEP %d OF %d", current, #active)

	-- Progress bar: one segment per step.
	local count = #active
	local segments = make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = 1 }, body)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, segments)
	for i = 1, count do
		local segment = make("Frame", {
			Size = UDim2.new(1 / count, -4 * (count - 1) / count, 1, 0),
			BackgroundColor3 = i < current and C.Gold or (i == current and C.Text or C.Track),
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, segments)
		Style.corner(segment, UDim.new(0.5, 0))
	end

	-- Picture on the left, explanation on the right.
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, body)
	local iconSlot = make("Frame", { Size = UDim2.fromOffset(84, 84), BackgroundColor3 = C.Slot, BorderSizePixel = 0 }, row)
	Style.border(iconSlot, C.Gold, 2)
	Style.corner(iconSlot)
	Style.icon(step.Icon or "❔", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
	}, iconSlot)
	local iconScale = make("UIScale", { Scale = 0.6 }, iconSlot)
	tween(iconScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)

	local column = make("Frame", {
		Position = UDim2.fromOffset(100, 0),
		Size = UDim2.new(1, -100, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, row)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, column)
	Style.label({
		Text = fill(step.Title),
		FontFace = Style.FontTitle,
		TextSize = 24,
		TextStrokeTransparency = 0.6,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
	}, column)
	Style.label({
		Text = fill(pick(step.Body, true)),
		TextColor3 = C.SubText,
		TextSize = 17,
		LineHeight = 1.1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	}, column)

	local keys = pick(step.Keys, false)
	if keys and #keys > 0 then
		local keyRow = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 }, column)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, keyRow)
		for i, key in keys do
			keycap(key, keyRow, i)
		end
	end

	local tip = pick(step.Tip, true)
	if tip and tip ~= "" then
		Style.label({
			Text = "💡  " .. fill(tip),
			FontFace = Style.FontBold,
			TextColor3 = C.Gold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 4,
		}, column)
	end

	-- Goal box: what to do, a tick box and a progress bar.
	if step.Goal then
		local box = make("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.Slot, BorderSizePixel = 0, LayoutOrder = 3 }, body)
		ui.goalStroke = Style.border(box, C.SlotBorder, 2)
		Style.corner(box)
		ui.check = make("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = C.Track,
			BorderSizePixel = 0,
		}, box)
		Style.border(ui.check, C.Gold, 2)
		Style.corner(ui.check, UDim.new(0, 6))
		ui.checkMark = Style.label({
			Text = "✓",
			FontFace = Style.FontTitle,
			TextSize = 22,
			RichText = false,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
		}, ui.check)
		Style.label({
			Text = "GOAL",
			FontFace = Style.FontTitle,
			TextSize = 12,
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(58, 8),
			Size = UDim2.fromOffset(60, 14),
		}, box)
		Style.label({
			Text = goalText(step.Goal),
			FontFace = Style.FontBold,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.fromOffset(58, 22),
			Size = UDim2.new(1, -170, 0, 20),
		}, box)
		ui.status = Style.label({
			FontFace = Style.FontTitle,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 22),
			Size = UDim2.fromOffset(110, 20),
		}, box)
		local track = make("Frame", {
			Position = UDim2.fromOffset(58, 48),
			Size = UDim2.new(1, -72, 0, 6),
			BackgroundColor3 = C.Track,
			BorderSizePixel = 0,
		}, box)
		Style.corner(track, UDim.new(0.5, 0))
		ui.fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Gold, BorderSizePixel = 0 }, track)
		Style.corner(ui.fill, UDim.new(0.5, 0))
		updateGoalUI()
	end

	-- Back / Skip tutorial / Next.
	local footer = make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 4 }, body)
	local back = Style.button("‹  Back", false, { Size = UDim2.fromOffset(112, 44), Visible = current > 1 }, footer)
	local skip = make("TextButton", {
		Text = "Skip tutorial",
		FontFace = Style.FontBold,
		TextSize = 14,
		TextColor3 = C.SubText,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(130, 34),
	}, footer)
	ui.next = Style.button("Next  ›", true, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(176, 44),
	}, footer)
	back.Activated:Connect(function()
		if current > 1 then
			showStep(current - 1)
		end
	end)
	skip.Activated:Connect(renderConfirm)
	ui.next.Activated:Connect(function()
		if current >= #active then
			finish(false)
		else
			showStep(current + 1)
		end
	end)
	updateNext()

	-- On a gamepad, select Next so A presses it (not on goal steps, where A means jump).
	if device() == "Gamepad" and not step.Goal then
		GuiService.SelectedObject = ui.next
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

--------------------------------------------------------------------------------
-- Goals
--------------------------------------------------------------------------------

local function track(item)
	table.insert(stepCleanup, item)
end

local GOALS = {}

function GOALS.Move(g)
	local needed = g.Distance or 30
	local walked = 0
	local last = nil
	setProgress(0, string.format("0 / %d", needed))
	track(RunService.Heartbeat:Connect(function()
		local root = rootPart()
		if not root then
			last = nil
			return
		end
		local position = root.Position * Vector3.new(1, 0, 1)
		if last then
			local step = (position - last).Magnitude
			if step < 10 then -- ignore teleports and respawns
				walked += step
			end
		end
		last = position
		setProgress(walked / needed, string.format("%d / %d", math.floor(walked), needed))
	end))
end

function GOALS.Jump()
	setProgress(0, "0 / 1")
	track(UserInputService.JumpRequest:Connect(function()
		setProgress(1, "1 / 1")
	end))
end

function GOALS.Look(g)
	local needed = g.Degrees or 120
	local turned = 0
	local function yaw()
		local look = camera().CFrame.LookVector
		return math.deg(math.atan2(look.X, look.Z))
	end
	local last = yaw()
	setProgress(0, string.format("0° / %d°", needed))
	track(RunService.RenderStepped:Connect(function()
		local now = yaw()
		local delta = (now - last + 180) % 360 - 180
		last = now
		turned += math.abs(delta)
		setProgress(turned / needed, string.format("%d° / %d°", math.floor(turned), needed))
	end))
end

function GOALS.Equip(g)
	setProgress(0, "")
	track(RunService.Heartbeat:Connect(function()
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		if tool and (not g.Tool or tool.Name == g.Tool) then
			setProgress(1, "")
		end
	end))
end

function GOALS.Open(g)
	setProgress(0, "")
	-- Only a window that opens during this step counts (not HUD panels that are always there).
	local words = g.Gui or {}
	local alreadyOpen = findWindows(words)
	local nextCheck = 0
	track(RunService.Heartbeat:Connect(function()
		if os.clock() < nextCheck then
			return
		end
		nextCheck = os.clock() + 0.25
		local openNow = findWindows(words)
		for element in openNow do
			if not alreadyOpen[element] then
				setProgress(1, "")
				return
			end
		end
		alreadyOpen = openNow -- something closed: opening it again counts
	end))
end

function GOALS.Reach(g)
	local radius = g.Radius or 15
	local startDistance = nil
	local target, nextFind = nil, 0
	setProgress(0, "")
	track(RunService.Heartbeat:Connect(function()
		if os.clock() >= nextFind then
			nextFind = os.clock() + 0.5
			target = findWorld(g)
		end
		local root = rootPart()
		if not target or not root then
			return
		end
		local distance = (target.Position - root.Position).Magnitude
		startDistance = startDistance or math.max(distance, radius + 1)
		local progress = distance <= radius and 1 or (1 - (distance - radius) / (startDistance - radius))
		setProgress(math.max(progress, goal.progress), string.format("%d studs away", math.floor(math.max(distance - radius, 0))))
	end))
end

function GOALS.Level(g)
	local needed = g.Level or 2
	track(RunService.Heartbeat:Connect(function()
		local level = getLevel() or 0
		setProgress(level / needed, string.format("Level %d / %d", level, needed))
	end))
end

--------------------------------------------------------------------------------
-- Highlights
--------------------------------------------------------------------------------

local function newMarker(part, label)
	local marker = make("BillboardGui", {
		Name = "GuideMarker",
		Adornee = part,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(160, 110),
		StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2, 0),
		ResetOnSpawn = false,
	}, playerGui)
	local bars = newChevron(marker, 1)
	local title = Style.label({
		Text = label,
		FontFace = Style.FontTitle,
		TextSize = 18,
		TextStrokeTransparency = 0.2,
		Size = UDim2.new(1, 0, 0, 20),
	}, marker)
	local distance = Style.label({
		FontFace = Style.FontBold,
		TextSize = 14,
		TextColor3 = C.Gold,
		TextStrokeTransparency = 0.2,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 18),
	}, marker)
	return { gui = marker, bars = bars, title = title, distance = distance }
end

local function startWorldHighlight(spec)
	local h = { kind = "world", spec = spec, part = nil, nextFind = 0 }
	local a0 = make("Attachment", { Name = "GuideTrailStart" })
	local a1 = make("Attachment", { Name = "GuideTrailEnd" })
	local beam = make("Beam", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = ColorSequence.new(C.Gold),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.2, 0.35),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		LightEmission = 1,
		FaceCamera = true,
		Width0 = 0.35,
		Width1 = 0.35,
		Segments = 1,
	})
	h.a0, h.a1, h.beam = a0, a1, beam
	track(a0)
	track(a1)
	track(beam)
	track(function()
		if h.marker then
			h.marker.gui:Destroy()
		end
	end)
	highlight = h
end

local function updateWorld(h, now)
	if now >= h.nextFind then
		h.nextFind = now + 1
		local part = findWorld(h.spec)
		if part ~= h.part then
			h.part = part
			if h.marker then
				h.marker.gui:Destroy()
				h.marker = nil
			end
			if part then
				local model = part:FindFirstAncestorOfClass("Model")
				local name = h.spec.Label or (model and model ~= Workspace and model.Name) or part.Name
				h.marker = newMarker(part, name)
				h.a1.Parent = part
			else
				h.a1.Parent = nil
			end
		end
	end
	local part, root = h.part, rootPart()
	if not part or not part:IsDescendantOf(Workspace) or not root then
		h.beam.Parent = nil
		hideChevron(edgeArrow)
		edgeLabel.Visible = false
		return
	end
	-- Gold trail from the player to the target.
	if h.a0.Parent ~= root then
		h.a0.Parent = root
	end
	h.beam.Parent = root

	local distance = (part.Position - root.Position).Magnitude
	local bounce = math.abs(math.sin(now * 4)) * 10
	placeChevron(h.marker.bars, Vector2.new(80, 80 + bounce), 90)
	h.marker.distance.Text = string.format("%d studs", math.floor(distance))

	-- When it's off screen, an arrow on the screen edge shows which way to turn.
	local view = camera().ViewportSize
	local point, visible = camera():WorldToViewportPoint(part.Position)
	local margin = 60
	if visible and point.X > margin and point.X < view.X - margin and point.Y > margin and point.Y < view.Y - margin then
		hideChevron(edgeArrow)
		edgeLabel.Visible = false
		return
	end
	local center = view / 2
	local dir = Vector2.new(point.X, point.Y) - center
	if point.Z < 0 then
		dir = -dir
	end
	if dir.Magnitude < 1 then
		dir = Vector2.new(0, 1)
	end
	local half = center - Vector2.new(margin, margin)
	local scale = math.min(half.X / math.max(math.abs(dir.X), 1e-3), half.Y / math.max(math.abs(dir.Y), 1e-3))
	local edge = center + dir * scale
	placeChevron(edgeArrow, edge + dir.Unit * (bounce * 0.6), math.deg(math.atan2(dir.Y, dir.X)))
	local labelAt = edge - dir.Unit * 60
	edgeLabel.Position = UDim2.fromOffset(labelAt.X, labelAt.Y)
	edgeLabel.Text = string.format("%s\n<font color=\"#ffde28\">%d studs</font>", h.marker.title.Text, math.floor(distance))
	edgeLabel.Visible = true
end

local function setDim(rectPos, rectSize)
	if not dimOn then
		for _, d in dims do
			d.Visible = false
		end
		return
	end
	local view = camera().ViewportSize
	if not rectPos then
		dims[1].Position = UDim2.fromOffset(0, 0)
		dims[1].Size = UDim2.fromOffset(view.X, view.Y)
		dims[1].Visible = true
		for i = 2, 4 do
			dims[i].Visible = false
		end
		return
	end
	local top = rectPos.Y - SPOT_PAD
	local bottom = rectPos.Y + rectSize.Y + SPOT_PAD
	local left = rectPos.X - SPOT_PAD
	local right = rectPos.X + rectSize.X + SPOT_PAD
	local boxes = {
		{ 0, 0, view.X, top },
		{ 0, bottom, view.X, view.Y - bottom },
		{ 0, top, left, bottom - top },
		{ right, top, view.X - right, bottom - top },
	}
	for i, b in boxes do
		dims[i].Position = UDim2.fromOffset(b[1], b[2])
		dims[i].Size = UDim2.fromOffset(math.max(b[3], 0), math.max(b[4], 0))
		dims[i].Visible = true
	end
end

local function updateOverlay()
	local now = os.clock()
	local h = highlight
	local rectPos, rectSize = nil, nil
	if h and h.kind == "gui" then
		if now >= h.nextFind then
			h.nextFind = now + 0.5
			h.target = findButton(h.words)
		end
		if h.target and onScreen(h.target) then
			rectPos, rectSize = guiRect(h.target)
		end
	end
	setDim(rectPos, rectSize)

	if rectPos then
		local pulse = 2 + math.sin(now * 5) * 3
		ring.Position = UDim2.fromOffset(rectPos.X - SPOT_PAD - pulse, rectPos.Y - SPOT_PAD - pulse)
		ring.Size = UDim2.fromOffset(rectSize.X + (SPOT_PAD + pulse) * 2, rectSize.Y + (SPOT_PAD + pulse) * 2)
		ringStroke.Transparency = 0.15 + (math.sin(now * 5) + 1) * 0.15
		ring.Visible = true
		local mid = rectPos + rectSize / 2
		local bounce = math.abs(math.sin(now * 4)) * 10
		if mid.Y < camera().ViewportSize.Y * 0.5 then
			placeChevron(guiArrow, Vector2.new(mid.X, rectPos.Y + rectSize.Y + SPOT_PAD + 14 + bounce), -90)
		else
			placeChevron(guiArrow, Vector2.new(mid.X, rectPos.Y - SPOT_PAD - 14 - bounce), 90)
		end
	else
		ring.Visible = false
		hideChevron(guiArrow)
	end

	if h and h.kind == "world" then
		updateWorld(h, now)
	else
		hideChevron(edgeArrow)
		edgeLabel.Visible = false
	end

	-- Keep the card's red border lined up with the card.
	cardBorder.Visible = card.Visible
	if card.Visible then
		local s = cardScale.Scale
		local size = card.AbsoluteSize
		cardBorder.Position = UDim2.fromOffset(card.AbsolutePosition.X, card.AbsolutePosition.Y)
		cardBorder.Size = UDim2.fromOffset(size.X, size.Y)
		cardBorder:FindFirstChildOfClass("UIStroke").Thickness = 3 * s
		cardBorder:FindFirstChildOfClass("UIStroke").Transparency = card.GroupTransparency
	end
end

--------------------------------------------------------------------------------
-- Moving between steps
--------------------------------------------------------------------------------

local function cardSpot(step)
	local h = step.Highlight
	if h and h.Gui then
		local button = findButton(h.Gui)
		if button then
			local pos, size = guiRect(button)
			return (pos.Y + size.Y / 2 > camera().ViewportSize.Y * 0.5) and "top" or "bottom"
		end
	end
	if dimOn and not step.Goal and not (h and (h.Tag or h.Path)) then
		return "center"
	end
	if device() == "Touch" then
		return "top" -- keep the joystick and jump button free
	end
	return "bottom"
end

function showStep(index)
	cleanStep()
	stepToken += 1
	current = index
	local step = active[index]
	goal = { progress = 0, done = false, status = "" }

	local h = step.Highlight
	local gameplay = step.Goal and step.Goal.Type ~= "Open"
	if step.Dim ~= nil then
		dimOn = step.Dim
	else
		dimOn = (h ~= nil and h.Gui ~= nil) or (not gameplay and not (h and (h.Tag or h.Path)))
	end

	if h and h.Gui then
		highlight = { kind = "gui", words = h.Gui, nextFind = 0 }
	elseif h and (h.Tag or h.Path) then
		startWorldHighlight(h)
	end

	placeCard(cardSpot(step))
	renderCard()
	if step.Goal then
		local start = GOALS[step.Goal.Type]
		if start then
			start(step.Goal)
		else
			warn("[TutorialAndAlerts] unknown goal type: " .. tostring(step.Goal.Type))
		end
	end

	-- Slide the new card in.
	local target = card.Position
	card.Position = target + UDim2.fromOffset(0, 14)
	card.GroupTransparency = 0.6
	tween(card, 0.25, { Position = target, GroupTransparency = 0 })
end

local hidden = {} -- old tutorial screens we've turned off

local function hideOldTutorial(screenGui)
	if not settings.HideOldTutorial or hidden[screenGui] or screenGui == gui or not screenGui:IsA("LayerCollector") then
		return
	end
	for _, word in settings.OldTutorialNames do
		if screenGui.Name:lower():find(word:lower(), 1, true) then
			hidden[screenGui] = true
			screenGui.Enabled = false
			screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if screenGui.Enabled then
					screenGui.Enabled = false
				end
			end)
			return
		end
	end
end

local overlayConnection = nil

local function start()
	active = {}
	for _, step in Config.Steps do
		if available(step) then
			table.insert(active, step)
		end
	end
	if #active == 0 then
		return
	end
	open = true
	helpButton.Visible = false
	card.Visible = true
	if not overlayConnection then
		overlayConnection = RunService.RenderStepped:Connect(updateOverlay)
	end
	showStep(1)
end

function finish(skipped)
	if not open then
		return
	end
	open = false
	stepToken += 1
	cleanStep()
	dimOn = false
	tween(card, 0.25, { GroupTransparency = 1 }).Completed:Connect(function()
		if not open then
			card.Visible = false
			if overlayConnection then
				overlayConnection:Disconnect()
				overlayConnection = nil
			end
			updateOverlay()
			if body then
				body:Destroy()
				body = nil
			end
		end
	end)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
	helpButton.Visible = settings.HelpButton
	if settings.HelpButton then
		local pop = make("UIScale", { Scale = 1.6 }, helpButton)
		tween(pop, 0.5, { Scale = 1 }, Enum.EasingStyle.Back).Completed:Connect(function()
			pop:Destroy()
		end)
	end
	Notify.Remote:FireServer("TutorialDone")
	Notify.Toast(
		player,
		skipped and "Tutorial skipped" or "Tutorial complete!",
		"Press the ? button on the left to watch it again."
	)
end

closeButton.Activated:Connect(function()
	if open then
		renderConfirm()
	end
end)

helpButton.Activated:Connect(function()
	if not open then
		start()
	end
end)

-- Redraw the card when the player switches between keyboard, touch and gamepad.
local lastDevice = device()
UserInputService.LastInputTypeChanged:Connect(function()
	local now = device()
	if now ~= lastDevice then
		lastDevice = now
		if open and ui.next and ui.next.Parent then
			renderCard()
		end
	end
end)

local function onRemote(kind)
	if kind == "ShowTutorial" and not open then
		start()
	end
end
Notify.Remote.OnClientEvent:Connect(onRemote)
Notify.LocalEvent.Event:Connect(onRemote)

playerGui.ChildAdded:Connect(hideOldTutorial)
for _, screenGui in playerGui:GetChildren() do
	hideOldTutorial(screenGui)
end

-- Open on the first visit, once the server says whether it's been done before.
task.spawn(function()
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	task.wait(settings.StartDelay)
	local waited = 0
	while player:GetAttribute("TutorialDone") == nil and waited < 10 do
		waited += task.wait(0.2)
	end
	helpButton.Visible = settings.HelpButton
	if settings.ShowOnFirstJoin and player:GetAttribute("TutorialDone") ~= true and not open then
		start()
	end
end)
