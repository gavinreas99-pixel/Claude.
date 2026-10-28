--[[
	Net client: swinging the bug net.

	Click (PC), tap (mobile) or press the trigger (gamepad) while holding the
	net. The swing plays right away on your screen, then the server checks
	what you caught. Other players' swings are animated here too, and
	catches play a sound.

	The swing moves the right shoulder joint locally, so it works on R15 and
	R6 characters without any uploaded animations.

	This is a Script with RunContext = Client, so it runs from ReplicatedStorage.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local Util = require(folder:WaitForChild("Util"))
local remote = folder:WaitForChild("BugRemote")

local player = Players.LocalPlayer

local SWING_TIME = 0.5

-- Shoulder angle (radians, + raises the arm) over the swing: wind up, sweep down, recover.
local function swingAngle(t)
	if t < 0.1 then
		local a = t / 0.1
		return 0.8 * (1 - (1 - a) ^ 2)
	elseif t < 0.24 then
		local a = (t - 0.1) / 0.14
		local eased = a < 0.5 and 2 * a * a or 1 - (-2 * a + 2) ^ 2 / 2
		return 0.8 - 1.95 * eased
	end
	local a = math.min((t - 0.24) / (SWING_TIME - 0.24), 1)
	return -1.15 * (1 - a) ^ 2
end

local swings = {} -- [character] = { motor, baseC0, axis, started, trail }

local function findShoulder(character)
	local arm = character:FindFirstChild("RightUpperArm")
	local motor = arm and arm:FindFirstChild("RightShoulder")
	if not motor then
		local torso = character:FindFirstChild("Torso")
		motor = torso and torso:FindFirstChild("Right Shoulder")
	end
	return motor and motor:IsA("Motor6D") and motor or nil
end

local function playSwing(character)
	local tool = character:FindFirstChild(Config.NetName)
	local motor = findShoulder(character)
	if not tool or not motor then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	local existing = swings[character]
	local baseC0 = existing and existing.baseC0 or motor.C0
	-- Pitch around the torso's sideways axis, expressed in the joint's own frame.
	local axis = baseC0.Rotation:VectorToObjectSpace(Vector3.xAxis)
	local trail = handle and handle:FindFirstChild("SwingTrail")
	swings[character] = { motor = motor, baseC0 = baseC0, axis = axis, started = os.clock(), trail = trail }

	local sound = handle and handle:FindFirstChild("SwingSound")
	if sound and sound:IsA("Sound") then
		sound.PlaybackSpeed = 1.15 + math.random() * 0.2
		sound:Play()
	end
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for character, swing in swings do
		local t = now - swing.started
		if t >= SWING_TIME or not swing.motor.Parent then
			swing.motor.C0 = swing.baseC0
			if swing.trail then
				swing.trail.Enabled = false
			end
			swings[character] = nil
		else
			swing.motor.C0 = swing.baseC0 * CFrame.fromAxisAngle(swing.axis, swingAngle(t))
			if swing.trail then
				swing.trail.Enabled = t > 0.08 and t < 0.3
			end
		end
	end
end)

-- ------------------------------------------------------------------ your own net

local lastSwing = 0

local function hookTool(tool)
	if not tool:IsA("Tool") or tool.Name ~= Config.NetName or tool:GetAttribute("Hooked") then
		return
	end
	tool:SetAttribute("Hooked", true)
	tool.Activated:Connect(function()
		local now = os.clock()
		local character = player.Character
		if now - lastSwing < Config.SwingCooldown or not character or tool.Parent ~= character then
			return
		end
		lastSwing = now
		playSwing(character)
		remote:FireServer("Swing")
	end)
end

local function onCharacter(character)
	character.ChildAdded:Connect(hookTool)
	for _, child in character:GetChildren() do
		hookTool(child)
	end
	-- Equip the net straight away so players can start catching.
	task.defer(function()
		local backpack = player:WaitForChild("Backpack", 10)
		local net = backpack and backpack:WaitForChild(Config.NetName, 10)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if net and humanoid and not character:FindFirstChildOfClass("Tool") and net.Parent == backpack then
			humanoid:EquipTool(net)
		end
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end

-- ------------------------------------------------------------------ server messages

remote.OnClientEvent:Connect(function(action, ...)
	if action == "Swing" then
		local swinger = ...
		if typeof(swinger) == "Instance" and swinger ~= player and swinger.Character then
			playSwing(swinger.Character)
		end
	elseif action == "Caught" then
		local _, isNew = ...
		Util.playSound(Config.Sounds.Catch, SoundService, 0.7, isNew and 1 or 1.15)
		if isNew then
			Util.playSound(Config.Sounds.NewBug, SoundService, 0.5)
		end
	end
end)
