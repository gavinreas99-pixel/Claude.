--[[
	Pistol server: builds the tool, gives it to players, and handles shots
	and reloads. Ammo, fire rate and damage are all checked here so players
	can't cheat them. This is a Script with RunContext = Server, so it runs
	from ReplicatedStorage.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local GunBuilder = require(folder:WaitForChild("GunBuilder"))

local remote = folder:FindFirstChild("PistolRemote") or Instance.new("RemoteEvent")
remote.Name = "PistolRemote"
remote.Parent = folder

local template = GunBuilder.build(Config)
CollectionService:AddTag(template, Config.Tag)

if Config.GiveOnSpawn then
	template.Parent = StarterPack -- copied into each player's backpack when they spawn
	for _, player in Players:GetPlayers() do
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack and not backpack:FindFirstChild(template.Name) then
			template:Clone().Parent = backpack
		end
	end
else
	template.Parent = folder -- clone it from here yourself, e.g. for a shop
end

local lastFire = setmetatable({}, { __mode = "k" })
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function findHumanoid(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function canDamage(shooter, humanoid)
	local victim = Players:GetPlayerFromCharacter(humanoid.Parent)
	if victim == shooter then
		return false
	end
	if victim and not Config.TeamKill and not shooter.Neutral and shooter.Team ~= nil and victim.Team == shooter.Team then
		return false
	end
	return true
end

local function isFiniteVector(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function fire(player, character, tool, target)
	if not isFiniteVector(target) or tool:GetAttribute("Reloading") then
		return
	end
	local ammo = tool:GetAttribute("Ammo") or 0
	if ammo <= 0 then
		return
	end
	local now = os.clock()
	if now - (lastFire[tool] or 0) < Config.FireCooldown * 0.75 then
		return -- firing faster than the gun allows
	end
	lastFire[tool] = now
	tool:SetAttribute("Ammo", ammo - 1)

	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if not muzzle then
		return
	end
	local origin = muzzle.WorldPosition
	local offset = target - origin
	if offset.Magnitude < 0.01 then
		return
	end
	local direction = offset.Unit * Config.Range

	rayParams.FilterDescendantsInstances = { character }
	local result = Workspace:Raycast(origin, direction, rayParams)
	local hitPosition = result and result.Position or origin + direction
	local hitNormal = result and result.Normal
	local humanoid = result and findHumanoid(result.Instance)

	if humanoid and humanoid.Health > 0 and canDamage(player, humanoid) then
		local headshot = result.Instance.Name == "Head"
		humanoid:TakeDamage(Config.Damage * (headshot and Config.HeadshotMultiplier or 1))
		remote:FireClient(player, "HitConfirm", headshot, humanoid.Health <= 0)
	end

	-- Everyone draws the muzzle flash, tracer and impact (the shooter already did).
	remote:FireAllClients("Shot", player, tool, hitPosition, hitNormal, humanoid ~= nil)
end

local function reload(tool)
	if tool:GetAttribute("Reloading") or (tool:GetAttribute("Ammo") or 0) >= Config.MagazineSize then
		return
	end
	tool:SetAttribute("ReloadStart", Workspace:GetServerTimeNow())
	tool:SetAttribute("Reloading", true)
	task.delay(Config.ReloadTime, function()
		tool:SetAttribute("Ammo", Config.MagazineSize)
		tool:SetAttribute("Reloading", false)
	end)
end

remote.OnServerEvent:Connect(function(player, action, tool, target)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or not CollectionService:HasTag(tool, Config.Tag) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or tool.Parent ~= character then
		return
	end
	if action == "Fire" then
		fire(player, character, tool, target)
	elseif action == "Reload" then
		reload(tool)
	end
end)
