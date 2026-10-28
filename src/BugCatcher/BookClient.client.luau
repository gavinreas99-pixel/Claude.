--[[
	Book client: the Bug Book and the catch popup.

	  * A book button on the right of the screen (or press B) opens the Bug Book.
	  * Every bug has a card with a little 3D model. Bugs you haven't caught
	    are black silhouettes with "???" and a hint about when they appear.
	    Caught bugs show in colour with their name and how many you've caught.
	  * A small popup slides in whenever you catch a bug.

	The collection comes from the server (the "BugCollection" attribute on
	your Player), so the book always matches your saved data.

	This is a Script with RunContext = Client, so it runs from ReplicatedStorage.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local folder = script.Parent
local BugData = require(folder:WaitForChild("BugData"))
local BugBuilder = require(folder:WaitForChild("BugBuilder"))
local Util = require(folder:WaitForChild("Util"))
local create = Util.create
local remote = folder:WaitForChild("BugRemote")

local player = Players.LocalPlayer

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local PAPER = rgb(250, 244, 228)
local CARD = rgb(255, 252, 243)
local INK = rgb(62, 44, 30)
local FADED = rgb(140, 124, 104)
local GREEN = rgb(108, 168, 74)
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium

local TOTAL = #BugData.List

local function corner(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(parent, color, thickness)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function label(props)
	local text = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		TextColor3 = INK,
		TextSize = 16,
	})
	for key, value in props do
		if key ~= "Parent" then
			text[key] = value
		end
	end
	text.Parent = props.Parent
	return text
end

-- Text that shrinks to fit its box on small screens.
local function fitText(text, maxSize)
	text.TextScaled = true
	create("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8, Parent = text })
	return text
end

-- Puts a bug model in a ViewportFrame and aims the camera at it.
local function showBug(viewport, bug)
	local camera = viewport.CurrentCamera
	if not camera then
		camera = create("Camera", { FieldOfView = 30, Parent = viewport })
		viewport.CurrentCamera = camera
	end
	local rig = BugBuilder.build(bug)
	-- See-through wings would vanish from the silhouettes, so make icons' wings more solid.
	for _, record in rig.parts do
		record.part.Transparency = math.min(record.part.Transparency, 0.25)
	end
	rig.model.Parent = viewport
	local box, size = rig.model:GetBoundingBox()
	local center = box.Position
	-- Flat, winged bugs look best from above; the rest from the front and side.
	local winged = bug.Shape == "Butterfly" or bug.Shape == "Dragonfly"
	local direction = (winged and Vector3.new(0.5, 1.25, -0.9) or Vector3.new(0.85, 0.6, -1)).Unit
	local distance = size.Magnitude / 2 / math.sin(math.rad(camera.FieldOfView / 2)) * 0.92
	camera.CFrame = CFrame.lookAt(center + direction * distance, center)
	return rig.model, center
end

local gui = create("ScreenGui", {
	Name = "BugBookGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})

-- ------------------------------------------------------------------ book button

local bookButton = create("TextButton", {
	Name = "BookButton",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(78, 82),
	BackgroundColor3 = PAPER,
	AutoButtonColor = true,
	Text = "",
	Parent = gui,
})
corner(bookButton, 18)
stroke(bookButton, INK, 3)
label({ Text = "📖", TextSize = 34, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 4), Parent = bookButton })
local countLabel = label({
	Text = "0/" .. TOTAL,
	Font = TITLE_FONT,
	TextSize = 18,
	Size = UDim2.new(1, 0, 0, 24),
	Position = UDim2.new(0, 0, 1, -30),
	Parent = bookButton,
})
local newBadge = label({
	Text = "!",
	Font = TITLE_FONT,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0,
	BackgroundColor3 = rgb(232, 84, 66),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(4, 4),
	Size = UDim2.fromOffset(26, 26),
	Visible = false,
	Parent = bookButton,
})
corner(newBadge, 13)
label({
	Text = "B",
	Font = TITLE_FONT,
	TextSize = 13,
	TextColor3 = FADED,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -6, 0, 4),
	Size = UDim2.fromOffset(14, 14),
	Visible = UserInputService.KeyboardEnabled,
	Parent = bookButton,
})

-- ------------------------------------------------------------------ the book

local book = create("Frame", {
	Name = "Book",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.92, 0.88),
	BackgroundColor3 = PAPER,
	Visible = false,
	Parent = gui,
})
create("UISizeConstraint", { MaxSize = Vector2.new(780, 580), Parent = book })
corner(book, 20)
stroke(book, INK, 4)
local bookScale = create("UIScale", { Parent = book })

label({
	Text = "Bug Book",
	Font = TITLE_FONT,
	TextSize = 30,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(20, 10),
	Size = UDim2.new(0.6, 0, 0, 38),
	Parent = book,
})
local progressText = label({
	Text = "",
	TextSize = 15,
	TextColor3 = FADED,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(20, 46),
	Size = UDim2.new(0.6, 0, 0, 20),
	Parent = book,
})
local progressBar = create("Frame", {
	BackgroundColor3 = rgb(228, 216, 190),
	Position = UDim2.fromOffset(20, 70),
	Size = UDim2.new(0.5, 0, 0, 10),
	Parent = book,
})
corner(progressBar, 5)
local progressFill = create("Frame", {
	BackgroundColor3 = GREEN,
	Size = UDim2.fromScale(0, 1),
	Parent = progressBar,
})
corner(progressFill, 5)

local closeButton = create("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(44, 44),
	BackgroundColor3 = rgb(232, 96, 80),
	Font = TITLE_FONT,
	Text = "X",
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = book,
})
corner(closeButton, 12)

local scroll = create("ScrollingFrame", {
	Name = "Cards",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(14, 92),
	Size = UDim2.new(1, -28, 1, -104),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = INK,
	Parent = book,
})
local grid = create("UIGridLayout", {
	CellSize = UDim2.fromOffset(132, 168),
	CellPadding = UDim2.fromOffset(12, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Parent = scroll,
})
create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10), Parent = scroll })

local cards = {}
for _, bug in BugData.List do
	local rarity = BugData.Rarities[bug.Rarity]
	local card = create("Frame", { Name = bug.Id, LayoutOrder = bug.Order, BackgroundColor3 = CARD, Parent = scroll })
	corner(card, 14)
	stroke(card, rarity.Color, 2.5)
	local view = create("ViewportFrame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0.64, -6),
		BackgroundColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.78),
		Ambient = rgb(150, 150, 150),
		LightColor = rgb(255, 255, 255),
		LightDirection = Vector3.new(-0.5, -1, -0.6),
		Parent = card,
	})
	corner(view, 10)
	local model, center = showBug(view, bug)
	cards[bug.Id] = {
		view = view,
		model = model,
		center = center,
		pivot = model:GetPivot(),
		name = fitText(label({ Font = TITLE_FONT, Position = UDim2.new(0, 4, 0.66, 2), Size = UDim2.new(1, -8, 0.15, 0), Parent = card }), 17),
		info = fitText(label({ Position = UDim2.new(0, 4, 0.82, 0), Size = UDim2.new(1, -8, 0.12, 0), Parent = card }), 13),
	}
end

-- Smaller cards on small (phone) screens.
local function layout()
	local s = math.clamp(gui.AbsoluteSize.Y / 640, 0.78, 1)
	grid.CellSize = UDim2.fromOffset(math.floor(132 * s), math.floor(168 * s))
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

local function readCollection()
	local raw = player:GetAttribute("BugCollection")
	if type(raw) ~= "string" then
		return {}
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return (ok and type(decoded) == "table") and decoded or {}
end

local function refresh()
	local collection = readCollection()
	local found = 0
	for _, bug in BugData.List do
		local card = cards[bug.Id]
		local rarity = BugData.Rarities[bug.Rarity]
		local count = tonumber(collection[bug.Id]) or 0
		if count > 0 then
			found += 1
			card.view.ImageColor3 = Color3.new(1, 1, 1)
			card.name.Text = bug.Name
			card.info.Text = string.format("%s  x%d", bug.Rarity, count)
			card.info.TextColor3 = rarity.Color:Lerp(INK, 0.4)
		else
			card.view.ImageColor3 = Color3.new(0, 0, 0) -- black silhouette
			card.name.Text = "???"
			card.info.Text = rarity.Hint
			card.info.TextColor3 = FADED
		end
	end
	countLabel.Text = found .. "/" .. TOTAL
	progressText.Text = string.format("Found %d of %d bugs", found, TOTAL)
	TweenService:Create(progressFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(found / TOTAL, 1) }):Play()
end

player:GetAttributeChangedSignal("BugCollection"):Connect(refresh)
refresh()

local isOpen = false
local function setOpen(open)
	isOpen = open
	if open then
		book.Visible = true
		newBadge.Visible = false
		bookScale.Scale = 0.85
		TweenService:Create(bookScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	else
		local shrink = TweenService:Create(bookScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 })
		shrink.Completed:Once(function()
			if not isOpen then
				book.Visible = false
			end
		end)
		shrink:Play()
	end
end

bookButton.Activated:Connect(function()
	setOpen(not isOpen)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B then
		setOpen(not isOpen)
	end
end)

-- Models sway gently while the book is open.
local sway = 0
RunService.RenderStepped:Connect(function(dt)
	if not isOpen then
		return
	end
	sway += dt
	for _, card in cards do
		local turn = CFrame.new(card.center) * CFrame.Angles(0, math.sin(sway * 0.8) * 0.45, 0) * CFrame.new(-card.center)
		card.model:PivotTo(turn * card.pivot)
	end
end)

-- ------------------------------------------------------------------ catch popup

local HIDDEN = UDim2.new(0.5, 0, 0, -140)
local SHOWN = UDim2.new(0.5, 0, 0, 12)

local toast = create("Frame", {
	Name = "CatchPopup",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = HIDDEN,
	Size = UDim2.fromOffset(330, 86),
	BackgroundColor3 = PAPER,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
})
corner(toast, 16)
local toastStroke = stroke(toast, INK, 3)
local toastView = create("ViewportFrame", {
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.fromOffset(70, 70),
	Ambient = rgb(150, 150, 150),
	LightColor = rgb(255, 255, 255),
	LightDirection = Vector3.new(-0.5, -1, -0.6),
	ZIndex = 5,
	Parent = toast,
})
corner(toastView, 12)
local toastTitle = label({ Font = TITLE_FONT, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(88, 9), Size = UDim2.new(1, -96, 0, 18), ZIndex = 5, Parent = toast })
local toastName = fitText(label({ Font = TITLE_FONT, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(88, 27), Size = UDim2.new(1, -96, 0, 30), ZIndex = 5, Parent = toast }), 24)
local toastSub = fitText(label({ TextColor3 = FADED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(88, 58), Size = UDim2.new(1, -96, 0, 18), ZIndex = 5, Parent = toast }), 14)

local queue = {}
local showing = false
local toastModel = nil

local function fillToast(item)
	if toastModel then
		toastModel:Destroy()
		toastModel = nil
	end
	local bug = item.bugId and BugData.ById[item.bugId]
	if bug then
		local rarity = BugData.Rarities[bug.Rarity]
		toastView.Visible = true
		toastView.BackgroundColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.75)
		toastModel = showBug(toastView, bug)
		toastStroke.Color = rarity.Color
		toastTitle.TextColor3 = rarity.Color:Lerp(INK, 0.25)
		toastTitle.Text = string.upper(item.isNew and ("New " .. bug.Rarity .. " bug!") or ("Caught a " .. bug.Rarity .. " bug"))
		toastName.Text = bug.Name
		toastSub.Text = item.isNew and "Added to your Bug Book" or string.format("Caught %d times", item.count or 1)
	else
		toastView.Visible = false
		toastStroke.Color = INK
		toastTitle.TextColor3 = INK
		toastTitle.Text = item.title or "Note"
		toastName.Text = ""
		toastSub.Text = item.text or ""
	end
end

local function showNext()
	local item = table.remove(queue, 1)
	if not item then
		showing = false
		toast.Visible = false
		return
	end
	showing = true
	fillToast(item)
	toast.Position = HIDDEN
	toast.Visible = true
	TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = SHOWN }):Play()
	task.delay(item.isNew and 3 or 2.2, function()
		local hide = TweenService:Create(toast, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = HIDDEN })
		hide.Completed:Once(showNext)
		hide:Play()
	end)
end

local function pushToast(item)
	-- Keep the queue short if lots of bugs are caught at once.
	if #queue >= 3 then
		table.remove(queue, 1)
	end
	table.insert(queue, item)
	if not showing then
		showNext()
	end
end

remote.OnClientEvent:Connect(function(action, ...)
	if action == "Caught" then
		local bugId, isNew, count = ...
		pushToast({ bugId = bugId, isNew = isNew, count = count })
		if isNew and not isOpen then
			newBadge.Visible = true
		end
	elseif action == "Notice" then
		local title, text = ...
		pushToast({ title = title, text = text })
	end
end)
