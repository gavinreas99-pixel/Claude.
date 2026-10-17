--[[
	Finds the player's level and reports when it changes. The level can be an
	attribute on the player, a value in leaderstats, or a value anywhere else
	under the player (e.g. a Data folder). Names come from Config.LevelNames.
]]

local PlayerStats = {}

local function matches(name, names)
	name = name:lower()
	for _, n in names do
		if name == n:lower() then
			return true
		end
	end
	return false
end

local function numberOf(value)
	if value:IsA("IntValue") or value:IsA("NumberValue") then
		return value.Value
	elseif value:IsA("StringValue") then
		return tonumber(value.Value)
	end
	return nil
end

-- Calls onChange(newLevel, oldLevel) every time the level changes. oldLevel is
-- nil the first time the level is found. Returns a function giving the
-- current level (nil until it's found).
function PlayerStats.watchLevel(player, names, onChange)
	local level = nil
	local found = false

	local function set(new)
		new = tonumber(new)
		if new == nil or new == level then
			return
		end
		local old = level
		level = new
		onChange(new, old)
	end

	local search

	local function useAttribute(name)
		found = true
		player:GetAttributeChangedSignal(name):Connect(function()
			set(player:GetAttribute(name))
		end)
		set(player:GetAttribute(name))
	end

	local function useValue(value)
		found = true
		local changed = value.Changed:Connect(function()
			set(numberOf(value))
		end)
		value.AncestryChanged:Connect(function()
			if not value:IsDescendantOf(player) then
				changed:Disconnect()
				found = false
				search()
			end
		end)
		set(numberOf(value))
	end

	function search()
		if found then
			return
		end
		for name, value in player:GetAttributes() do
			if matches(name, names) and tonumber(value) then
				useAttribute(name)
				return
			end
		end
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			for _, value in leaderstats:GetChildren() do
				if value:IsA("ValueBase") and matches(value.Name, names) and numberOf(value) then
					useValue(value)
					return
				end
			end
		end
		for _, value in player:GetDescendants() do
			if value:IsA("ValueBase") and matches(value.Name, names) and numberOf(value) and not value:FindFirstAncestorOfClass("PlayerGui") then
				useValue(value)
				return
			end
		end
	end

	player.AttributeChanged:Connect(function(name)
		if not found and matches(name, names) then
			search()
		end
	end)
	player.DescendantAdded:Connect(function(value)
		if not found and value:IsA("ValueBase") and matches(value.Name, names) and not value:FindFirstAncestorOfClass("PlayerGui") then
			task.defer(search) -- let the folder it's in finish replicating first
		end
	end)
	search()

	return function()
		return level
	end
end

return PlayerStats
