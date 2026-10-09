--[[
	Animates every Jade Jungle goblin on this client.
	This is a Script with RunContext = Client, so it runs from ReplicatedStorage.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local GoblinAnimator = require(folder:WaitForChild("GoblinAnimator"))

local rigs = {}

local function track(model)
	if rigs[model] or not model:IsA("Model") then
		return
	end
	-- Goblins stream in atomically, but wait briefly in case parts arrive late.
	if not model:FindFirstChild("HumanoidRootPart") then
		model:WaitForChild("HumanoidRootPart", 5)
	end
	local rig = GoblinAnimator.new(model, Config)
	if rig and model.Parent and CollectionService:HasTag(model, Config.Tag) then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		params.IgnoreWater = true
		rig.groundParams = params
		-- Root centre is 2 units above the feet; allow a little slack for slopes.
		rig.groundRay = Vector3.new(0, -2.6 * rig.scale, 0)
		rigs[model] = rig
	end
end

CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(function(model)
	task.spawn(track, model)
end)
CollectionService:GetInstanceRemovedSignal(Config.Tag):Connect(function(model)
	rigs[model] = nil
end)
for _, model in CollectionService:GetTagged(Config.Tag) do
	task.spawn(track, model)
end

RunService.PreSimulation:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local now = Workspace:GetServerTimeNow()
	for model, rig in rigs do
		if not model.Parent or model:GetAttribute("Dead") then
			rigs[model] = nil
		elseif not eye or (rig.root.Position - eye).Magnitude <= Config.AnimateDistance then
			local grounded = Workspace:Raycast(rig.root.Position, rig.groundRay, rig.groundParams) ~= nil
			GoblinAnimator.step(rig, dt, now, grounded)
		end
	end
end)
