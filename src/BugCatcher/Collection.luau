--[[
	Collection (server only): which bugs each player has caught.

	The server is the only one that changes it. Each player's collection is
	shared with clients as a JSON attribute on the Player ("BugCollection"),
	which the collection book reads, and as a "Bugs" leaderboard stat
	(how many different bugs they've found).
]]

local HttpService = game:GetService("HttpService")

local folder = script.Parent
local BugData = require(folder:WaitForChild("BugData"))
local Util = require(folder:WaitForChild("Util"))
local create = Util.create

local Collection = {}

local profiles = {} -- [player] = { caught = { [bugId] = timesCaught } }

local function uniqueCount(caught)
	local count = 0
	for bugId in caught do
		if BugData.ById[bugId] then
			count += 1
		end
	end
	return count
end

-- Sends the collection to clients and updates the leaderboard.
local function publish(player, profile)
	player:SetAttribute("BugCollection", HttpService:JSONEncode(profile.caught))
	local stats = player:FindFirstChild("leaderstats")
	local found = stats and stats:FindFirstChild("Bugs")
	if found then
		found.Value = uniqueCount(profile.caught)
	end
end

function Collection.setup(player)
	if profiles[player] then
		return profiles[player]
	end
	local profile = { caught = {} }
	profiles[player] = profile
	local stats = player:FindFirstChild("leaderstats") or create("Folder", { Name = "leaderstats", Parent = player })
	if not stats:FindFirstChild("Bugs") then
		create("IntValue", { Name = "Bugs", Parent = stats })
	end
	publish(player, profile)
	return profile
end

function Collection.get(player)
	return profiles[player]
end

-- Records a catch. Returns whether it's a new bug for this player and how many they've caught.
function Collection.add(player, bugId)
	local profile = profiles[player] or Collection.setup(player)
	local count = (profile.caught[bugId] or 0) + 1
	profile.caught[bugId] = count
	profile.dirty = true
	publish(player, profile)
	return count == 1, count
end

function Collection.remove(player)
	profiles[player] = nil
end

return Collection
