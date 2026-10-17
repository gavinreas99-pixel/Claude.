--[[
	Shared look for the tutorial and the notifications: the same dark navy,
	red and gold as the Quests window, plus small helpers for building UI.
]]

local SoundService = game:GetService("SoundService")

local Style = {}

Style.Colors = {
	WindowTop = Color3.fromRGB(14, 20, 34),
	WindowBottom = Color3.fromRGB(6, 9, 16),
	WindowBorder = Color3.fromRGB(122, 8, 8),
	HeaderTop = Color3.fromRGB(176, 12, 12),
	HeaderBottom = Color3.fromRGB(98, 0, 0),
	CardTop = Color3.fromRGB(18, 30, 52),
	CardBottom = Color3.fromRGB(5, 9, 18),
	CardBorder = Color3.fromRGB(40, 60, 94),
	Slot = Color3.fromRGB(8, 10, 15),
	SlotBorder = Color3.fromRGB(44, 48, 60),
	ButtonTop = Color3.fromRGB(36, 36, 40),
	ButtonBottom = Color3.fromRGB(14, 14, 16),
	ButtonBorder = Color3.fromRGB(64, 64, 70),
	GoldTop = Color3.fromRGB(255, 226, 82),
	GoldBottom = Color3.fromRGB(214, 146, 10),
	GoldBorder = Color3.fromRGB(120, 72, 0),
	Track = Color3.fromRGB(18, 20, 24),
	Text = Color3.new(1, 1, 1),
	SubText = Color3.fromRGB(196, 202, 214),
	DarkText = Color3.fromRGB(40, 24, 0),
	Gold = Color3.fromRGB(255, 222, 40),
	Green = Color3.fromRGB(70, 214, 96),
	Close = Color3.fromRGB(236, 22, 34),
	Outline = Color3.new(0, 0, 0),
}

local FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"
Style.FontTitle = Font.new(FONT_FAMILY, Enum.FontWeight.ExtraBold)
Style.FontBold = Font.new(FONT_FAMILY, Enum.FontWeight.Bold)
Style.FontBody = Font.new(FONT_FAMILY, Enum.FontWeight.SemiBold)

function Style.make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local make = Style.make

function Style.gradient(gui, top, bottom, rotation)
	gui.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient tints this
	return make("UIGradient", { Rotation = rotation or 90, Color = ColorSequence.new(top, bottom) }, gui)
end

function Style.border(gui, color, thickness)
	return make("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, gui)
end

function Style.corner(gui, radius)
	return make("UICorner", { CornerRadius = radius or UDim.new(0, 8) }, gui)
end

function Style.label(props, parent)
	local defaults = {
		BackgroundTransparency = 1,
		FontFace = Style.FontBody,
		TextColor3 = Style.Colors.Text,
		TextSize = 16,
		TextWrapped = true,
		RichText = true,
	}
	for k, v in props do
		defaults[k] = v
	end
	return make("TextLabel", defaults, parent)
end

-- An emoji/text icon, or an image when given an asset id.
function Style.icon(icon, props, parent)
	if typeof(icon) == "string" and (icon:find("rbxassetid://", 1, true) or icon:find("rbxasset://", 1, true) or icon:find("http", 1, true)) then
		local image = make("ImageLabel", { BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit }, parent)
		for k, v in props do
			if k ~= "TextSize" then
				image[k] = v
			end
		end
		return image
	end
	local text = Style.label({ Text = icon or "", TextScaled = true, RichText = false, FontFace = Style.FontBold }, parent)
	for k, v in props do
		text[k] = v
	end
	return text
end

-- A button with the dark (or gold) gradient look. Returns the button.
function Style.button(text, gold, props, parent)
	local c = Style.Colors
	local button = make("TextButton", {
		Text = text,
		FontFace = Style.FontTitle,
		TextSize = 16,
		TextColor3 = gold and c.DarkText or c.Text,
		AutoButtonColor = true,
		BorderSizePixel = 0,
	}, parent)
	for k, v in props do
		button[k] = v
	end
	Style.gradient(button, gold and c.GoldTop or c.ButtonTop, gold and c.GoldBottom or c.ButtonBottom)
	Style.border(button, gold and c.GoldBorder or c.ButtonBorder, 2)
	Style.corner(button, UDim.new(0, 6))
	return button
end

-- Repaints a button made by Style.button as gold or dark.
function Style.setGold(button, gold)
	local c = Style.Colors
	local g = button:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(gold and c.GoldTop or c.ButtonTop, gold and c.GoldBottom or c.ButtonBottom)
	end
	local s = button:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = gold and c.GoldBorder or c.ButtonBorder
	end
	button.TextColor3 = gold and c.DarkText or c.Text
end

local soundCache = {}

function Style.playSound(id, volume)
	if not id or id == "" then
		return
	end
	local sound = soundCache[id]
	if not sound then
		sound = make("Sound", { SoundId = id, Volume = volume or 0.6 }, SoundService)
		soundCache[id] = sound
	end
	SoundService:PlayLocalSound(sound)
end

return Style
