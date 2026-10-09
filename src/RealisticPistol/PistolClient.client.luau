--[[
	Pistol client: aiming, firing, recoil, slide / trigger / magazine
	animation, muzzle flash, shell casings, tracers, bullet holes, and the
	crosshair + ammo HUD. This is a Script with RunContext = Client, so it
	runs from ReplicatedStorage.

	Controls: click / tap to shoot, R (or the on-screen button) to reload.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local remote = folder:WaitForChild("PistolRemote")

local player = Players.LocalPlayer
local MM = (Config.Scale or 1) * 1.55 / 186 -- millimetres -> studs, matches GunBuilder

local SLIDE_TRAVEL = 22 -- mm the slide moves back
local MAG_DROP = 115 -- mm the magazine slides out

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

--------------------------------------------------------------------------------
-- Per-tool state (every pistol in the game, so other players' guns animate too)
--------------------------------------------------------------------------------

local states = {}

local function getState(tool)
	local state = states[tool]
	if state then
		return state
	end
	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if not muzzle then
		return nil
	end
	local function motor(name)
		local part = tool:FindFirstChild(name)
		return part and part:FindFirstChild(name)
	end
	local magParts, flashParts = {}, {}
	for _, child in tool:GetChildren() do
		if child.Name == "Magazine" or child.Name == "MagBaseplate" or child.Name == "Cartridge" then
			table.insert(magParts, child)
		elseif child.Name == "MuzzleFlash" then
			table.insert(flashParts, child)
		end
	end
	local sounds = {}
	for key, id in Config.Sounds do
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = id
			sound.Volume = key == "Fire" and Config.FireVolume or 0.6
			sound.RollOffMaxDistance = key == "Fire" and 250 or 60
			sound.Parent = handle
			sounds[key] = sound
		end
	end
	state = {
		tool = tool,
		handle = handle,
		muzzle = muzzle,
		ejection = handle:FindFirstChild("Ejection"),
		slide = motor("Slide"),
		trigger = motor("Trigger"),
		magazine = motor("Magazine"),
		magParts = magParts,
		flashParts = flashParts,
		sounds = sounds,
		shotAt = -math.huge,
		emptyReload = false,
		magHidden = false,
	}
	states[tool] = state
	tool:GetAttributeChangedSignal("Reloading"):Connect(function()
		if tool:GetAttribute("Reloading") then
			state.emptyReload = (tool:GetAttribute("Ammo") or 0) <= 0
		end
	end)
	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(game) then
			states[tool] = nil
		end
	end)
	return state
end

local function play(state, key)
	local sound = state.sounds[key]
	if sound then
		sound.PlaybackSpeed = key == "Fire" and (0.95 + math.random() * 0.1) or 1
		sound:Play()
	end
end

--------------------------------------------------------------------------------
-- Shot effects
--------------------------------------------------------------------------------

local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "PistolEffects"
effectsFolder.Parent = Workspace

local function effectPart(size, cf, color, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = effectsFolder
	return p
end

local function burst(position, normal, color, count, speed)
	local holder = effectPart(Vector3.new(0.05, 0.05, 0.05), CFrame.lookAt(position, position + normal), color)
	holder.Transparency = 1
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Lifetime = NumberRange.new(0.15, 0.35)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(50, 50)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Size = NumberSequence.new(0.12, 0)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Rate = 0
	emitter.Parent = attachment
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 145, 135))
	dust.Lifetime = NumberRange.new(0.3, 0.6)
	dust.Speed = NumberRange.new(1, 3)
	dust.SpreadAngle = Vector2.new(30, 30)
	dust.Size = NumberSequence.new(0.2, 0.7)
	dust.Transparency = NumberSequence.new(0.5, 1)
	dust.EmissionDirection = Enum.NormalId.Front
	dust.Rate = 0
	dust.Parent = attachment
	emitter:Emit(count)
	dust:Emit(3)
	Debris:AddItem(holder, 1)
end

local function ejectCasing(state)
	if not state.ejection then
		return
	end
	local handleCF = state.handle.CFrame
	local casing = Instance.new("Part")
	casing.Shape = Enum.PartType.Cylinder
	casing.Size = Vector3.new(19 * MM, 9 * MM, 9 * MM)
	casing.Color = Color3.fromRGB(198, 160, 80)
	casing.Material = Enum.Material.Metal
	casing.Reflectance = 0.15
	casing.CanQuery = false
	casing.CanTouch = false
	casing.CFrame = CFrame.new(state.ejection.WorldPosition) * handleCF.Rotation * CFrame.Angles(0, math.pi / 2, 0)
	casing.Parent = effectsFolder
	casing.AssemblyLinearVelocity = handleCF.RightVector * (7 + math.random() * 3)
		+ handleCF.UpVector * (6 + math.random() * 3)
		+ handleCF.LookVector * -1.5
	casing.AssemblyAngularVelocity = Vector3.new(math.random(-30, 30), math.random(-30, 30), math.random(-30, 30))
	Debris:AddItem(casing, 3)
end

local function playShotEffects(state, hitPosition, hitNormal, hitCharacter)
	state.shotAt = os.clock()
	play(state, "Fire")

	-- Muzzle flash: light, sparks, smoke and the neon flash star.
	local light = state.muzzle:FindFirstChild("FlashLight")
	local sparks = state.muzzle:FindFirstChild("FlashParticles")
	local smoke = state.muzzle:FindFirstChild("SmokeParticles")
	if sparks then
		sparks:Emit(10)
	end
	if smoke then
		smoke:Emit(3)
	end
	if light then
		light.Enabled = true
	end
	for _, part in state.flashParts do
		part.Transparency = 0.1 + math.random() * 0.3
	end
	task.delay(0.045, function()
		if light then
			light.Enabled = false
		end
		for _, part in state.flashParts do
			part.Transparency = 1
		end
	end)

	ejectCasing(state)

	-- Tracer from the muzzle to the hit point.
	local origin = state.muzzle.WorldPosition
	local length = (hitPosition - origin).Magnitude
	if length > 1 then
		local tracer = effectPart(
			Vector3.new(0.035, 0.035, length),
			CFrame.lookAt(origin, hitPosition) * CFrame.new(0, 0, -length / 2),
			Color3.fromRGB(255, 226, 160),
			Enum.Material.Neon
		)
		tracer.Transparency = 0.35
		Debris:AddItem(tracer, 0.05)
	end

	-- Bullet hole and sparks on whatever was hit.
	if hitNormal then
		if hitCharacter then
			burst(hitPosition, hitNormal, Color3.fromRGB(255, 255, 255), 6, 8)
		else
			local hole = effectPart(
				Vector3.new(0.02, 0.13, 0.13),
				CFrame.lookAt(hitPosition, hitPosition + hitNormal) * CFrame.Angles(0, math.pi / 2, 0),
				Color3.fromRGB(14, 14, 14)
			)
			hole.Shape = Enum.PartType.Cylinder
			Debris:AddItem(hole, 12)
			burst(hitPosition, hitNormal, Color3.fromRGB(255, 200, 110), 10, 14)
		end
	end
end

--------------------------------------------------------------------------------
-- HUD: crosshair, hit marker, ammo counter, reload button
--------------------------------------------------------------------------------

local hud = Instance.new("ScreenGui")
hud.Name = "PistolHUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = 5
hud.Enabled = false
hud.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local crosshair = make("Frame", { Size = UDim2.fromOffset(60, 60), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 }, hud)
local crossBars = {}
for i, spec in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
	local bar = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = spec[1] == 0 and UDim2.fromOffset(2, 9) or UDim2.fromOffset(9, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, crosshair)
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.4 }, bar)
	crossBars[i] = { bar = bar, dir = Vector2.new(spec[1], spec[2]) }
end
make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, crosshair)

local hitMarker = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, crosshair)
for _, angle in { 45, 135, 225, 315 } do
	local r = math.rad(angle)
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.cos(r) * 13, 0.5, math.sin(r) * 13),
		Size = UDim2.fromOffset(2, 9),
		Rotation = angle + 90,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, hitMarker)
end

-- Ammo panel in the same dark-navy style as the game's other windows.
local panel = make("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -24),
	Size = UDim2.fromOffset(190, 84),
	BackgroundColor3 = Color3.new(1, 1, 1),
}, hud)
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(18, 30, 52), Color3.fromRGB(5, 9, 18)) }, panel)
make("UIStroke", { Color = Color3.fromRGB(40, 60, 94), Thickness = 2 }, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
local FONT_BOLD = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
local FONT_BODY = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)
make("TextLabel", {
	Text = string.upper(Config.ToolName),
	FontFace = FONT_BODY,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(196, 202, 214),
	TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.fromOffset(160, 16),
}, panel)
local ammoLabel = make("TextLabel", {
	Text = "17",
	FontFace = FONT_BOLD,
	TextSize = 38,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.4,
	TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 24),
	Size = UDim2.fromOffset(70, 40),
}, panel)
local magLabel = make("TextLabel", {
	Text = "/ " .. Config.MagazineSize,
	FontFace = FONT_BODY,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(196, 202, 214),
	TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(84, 36),
	Size = UDim2.fromOffset(90, 22),
}, panel)
local hintLabel = make("TextLabel", {
	Text = "",
	FontFace = FONT_BOLD,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(255, 222, 40),
	TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 62),
	Size = UDim2.fromOffset(160, 16),
}, panel)
local reloadTrack = make("Frame", {
	Position = UDim2.new(0, 14, 1, -10),
	Size = UDim2.new(1, -28, 0, 4),
	BackgroundColor3 = Color3.fromRGB(18, 20, 24),
	BorderSizePixel = 0,
	Visible = false,
}, panel)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, reloadTrack)
local reloadFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 222, 40), BorderSizePixel = 0 }, reloadTrack)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, reloadFill)

local reloadButton = make("TextButton", {
	Text = "RELOAD",
	FontFace = FONT_BOLD,
	TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -118),
	Size = UDim2.fromOffset(110, 44),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Visible = UserInputService.TouchEnabled,
}, hud)
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(36, 36, 40), Color3.fromRGB(14, 14, 16)) }, reloadButton)
make("UIStroke", { Color = Color3.fromRGB(64, 64, 70), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, reloadButton)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, reloadButton)

--------------------------------------------------------------------------------
-- Local player's gun handling
--------------------------------------------------------------------------------

local equipped = nil -- state of the gun the local player is holding
local localAmmo = 0
local triggerHeld = false
local lastShot = 0
local recoil, recoilTarget, recoilYaw = 0, 0, 0
local bloom = 0
local hitMarkerUntil = 0

local function updateAmmoUI()
	ammoLabel.Text = tostring(localAmmo)
	ammoLabel.TextColor3 = localAmmo == 0 and Color3.fromRGB(236, 22, 34) or Color3.new(1, 1, 1)
	if equipped and equipped.tool:GetAttribute("Reloading") then
		hintLabel.Text = "RELOADING..."
	elseif localAmmo == 0 then
		hintLabel.Text = UserInputService.TouchEnabled and "TAP RELOAD" or "PRESS R TO RELOAD"
	elseif localAmmo <= math.ceil(Config.MagazineSize * 0.25) then
		hintLabel.Text = "LOW AMMO"
	else
		hintLabel.Text = ""
	end
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

-- Where the crosshair is pointing in the world.
local function aimPoint(origin)
	local camera = Workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	aimParams.FilterDescendantsInstances = { player.Character, effectsFolder }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * Config.Range, aimParams)
	local point = result and result.Position or ray.Origin + ray.Direction * Config.Range
	-- Random spread around the line from the muzzle to that point.
	local spread = math.rad(Config.SpreadDegrees + bloom * 0.6)
	local dir = CFrame.lookAt(origin, point)
		* CFrame.Angles((math.random() - 0.5) * 2 * spread, (math.random() - 0.5) * 2 * spread, 0)
	return origin + dir.LookVector * math.max((point - origin).Magnitude, 1)
end

local function requestReload()
	if not equipped then
		return
	end
	local tool = equipped.tool
	if tool:GetAttribute("Reloading") or localAmmo >= Config.MagazineSize then
		return
	end
	play(equipped, "Reload")
	remote:FireServer("Reload", tool)
end

local function tryFire()
	local state = equipped
	if not state then
		return
	end
	local tool = state.tool
	local now = os.clock()
	if tool:GetAttribute("Reloading") or now - lastShot < Config.FireCooldown then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	lastShot = now
	if localAmmo <= 0 then
		play(state, "Empty")
		requestReload()
		return
	end
	localAmmo -= 1
	updateAmmoUI()

	local origin = state.muzzle.WorldPosition
	local target = aimPoint(origin)
	remote:FireServer("Fire", tool, target)

	-- Show the shot right away instead of waiting for the server.
	aimParams.FilterDescendantsInstances = { character, effectsFolder }
	local direction = (target - origin).Unit * Config.Range
	local result = Workspace:Raycast(origin, direction, aimParams)
	local hitCharacter = false
	if result then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		hitCharacter = model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
	end
	playShotEffects(state, result and result.Position or origin + direction, result and result.Normal, hitCharacter)

	recoilTarget += Config.RecoilKick
	recoilYaw = (math.random() - 0.5) * Config.RecoilKick * 0.5
	bloom = math.min(bloom + 1, 4)

	if localAmmo == 0 then
		task.delay(0.35, requestReload) -- auto reload once the magazine is empty
	end
end

local function setup(tool)
	if not tool:IsA("Tool") then
		return
	end
	tool.Equipped:Connect(function()
		if tool.Parent ~= player.Character then
			return
		end
		equipped = getState(tool)
		if not equipped then
			return
		end
		localAmmo = tool:GetAttribute("Ammo") or 0
		updateAmmoUI()
		hud.Enabled = true
		crosshair.Visible = UserInputService.MouseEnabled
		UserInputService.MouseIconEnabled = not UserInputService.MouseEnabled
	end)
	tool.Unequipped:Connect(function()
		if equipped and equipped.tool == tool then
			equipped = nil
			triggerHeld = false
			hud.Enabled = false
			UserInputService.MouseIconEnabled = true
		end
	end)
	tool.Activated:Connect(function()
		triggerHeld = true
		tryFire()
	end)
	tool.Deactivated:Connect(function()
		triggerHeld = false
	end)
	tool:GetAttributeChangedSignal("Ammo"):Connect(function()
		if equipped and equipped.tool == tool then
			-- Shots we predicted are already counted, so only ever go down here.
			localAmmo = math.min(localAmmo, tool:GetAttribute("Ammo") or 0)
			updateAmmoUI()
		end
	end)
	tool:GetAttributeChangedSignal("Reloading"):Connect(function()
		if equipped and equipped.tool == tool then
			if not tool:GetAttribute("Reloading") then
				localAmmo = tool:GetAttribute("Ammo") or 0
			end
			updateAmmoUI()
		end
	end)
end

CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(setup)
for _, tool in CollectionService:GetTagged(Config.Tag) do
	setup(tool)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.R then
		requestReload()
	end
end)
reloadButton.Activated:Connect(requestReload)

remote.OnClientEvent:Connect(function(kind, ...)
	if kind == "Shot" then
		local shooter, tool, hitPosition, hitNormal, hitCharacter = ...
		if shooter ~= player and typeof(tool) == "Instance" then
			local state = getState(tool)
			if state then
				playShotEffects(state, hitPosition, hitNormal, hitCharacter)
			end
		end
	elseif kind == "HitConfirm" then
		local headshot = ...
		hitMarkerUntil = os.clock() + 0.15
		for _, bar in hitMarker:GetChildren() do
			bar.BackgroundColor3 = headshot and Color3.fromRGB(236, 22, 34) or Color3.new(1, 1, 1)
		end
		if equipped then
			play(equipped, "Hit")
		end
	end
end)

--------------------------------------------------------------------------------
-- Per-frame: camera recoil, HUD, and gun part animation
--------------------------------------------------------------------------------

RunService:BindToRenderStep("PistolRecoil", Enum.RenderPriority.Camera.Value + 1, function(dt)
	recoilTarget *= math.exp(-Config.RecoilRecover * dt)
	recoil += (recoilTarget - recoil) * math.min(1, dt * 35)
	recoilYaw *= math.exp(-Config.RecoilRecover * dt)
	if math.abs(recoil) > 1e-3 then
		local camera = Workspace.CurrentCamera
		camera.CFrame *= CFrame.Angles(math.rad(recoil), math.rad(recoilYaw), 0)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	bloom = math.max(0, bloom - dt * 5)

	-- Dying or respawning doesn't always fire Unequipped, so clean up here too.
	if equipped and equipped.tool.Parent ~= player.Character then
		equipped = nil
		triggerHeld = false
		hud.Enabled = false
		UserInputService.MouseIconEnabled = true
	end

	if equipped then
		if Config.Automatic and triggerHeld then
			tryFire()
		end
		local mouse = UserInputService:GetMouseLocation()
		crosshair.Position = UDim2.fromOffset(mouse.X, mouse.Y)
		local gap = 7 + bloom * 3
		for _, item in crossBars do
			item.bar.Position = UDim2.new(0.5, item.dir.X * gap, 0.5, item.dir.Y * gap)
		end
		hitMarker.Visible = os.clock() < hitMarkerUntil
		local tool = equipped.tool
		if tool:GetAttribute("Reloading") then
			local u = (Workspace:GetServerTimeNow() - (tool:GetAttribute("ReloadStart") or 0)) / Config.ReloadTime
			reloadTrack.Visible = true
			reloadFill.Size = UDim2.fromScale(math.clamp(u, 0, 1), 1)
		else
			reloadTrack.Visible = false
		end
	end

	-- Animate every pistol currently held by someone.
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	for tool, state in states do
		local holder = tool.Parent
		if holder and holder:FindFirstChildOfClass("Humanoid") and state.slide then
			local age = now - state.shotAt
			local slide = 0
			if age < 0.03 then
				slide = age / 0.03
			elseif age < 0.1 then
				slide = 1 - (age - 0.03) / 0.07
			end
			local trigger = age < 0.09 and 0.3 or 0

			local ammo = (equipped == state) and localAmmo or (tool:GetAttribute("Ammo") or 0)
			local mag, magHidden = 0, false
			if tool:GetAttribute("Reloading") then
				local u = (serverNow - (tool:GetAttribute("ReloadStart") or 0)) / Config.ReloadTime
				if u < 0.2 then
					mag = smooth(u / 0.2) -- old magazine slides out
				elseif u < 0.45 then
					mag, magHidden = 1, true -- reaching for a new one
				elseif u < 0.7 then
					mag = 1 - smooth((u - 0.45) / 0.25) -- new magazine goes in
				end
				if state.emptyReload and u < 0.8 then
					slide = 1 -- slide stays locked back until it's released
				end
			elseif ammo <= 0 and age >= 0.03 then
				slide = 1 -- empty: slide locks back
			end

			state.slide.Transform = CFrame.new(0, 0, slide * SLIDE_TRAVEL * MM)
			if state.trigger then
				state.trigger.Transform = CFrame.Angles(-trigger, 0, 0)
			end
			if state.magazine then
				state.magazine.Transform = CFrame.new(0, -mag * MAG_DROP * MM, 0)
			end
			if magHidden ~= state.magHidden then
				state.magHidden = magHidden
				for _, part in state.magParts do
					part.Transparency = magHidden and 1 or 0
				end
			end
		end
	end
end)

-- Make sure guns that appear before anyone shoots still get a state.
for _, tool in CollectionService:GetTagged(Config.Tag) do
	getState(tool)
end
CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(getState)
