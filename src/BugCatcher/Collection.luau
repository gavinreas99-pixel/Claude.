--[[
	Collection (server only): which bugs each player has caught, saved with
	DataStoreService.

	The server is the only one that changes it. Each player's collection is
	shared with clients as a JSON attribute on the Player ("BugCollection"),
	which the Bug Book reads, and as a "Bugs" leaderboard stat (how many
	different bugs they've found).

	Saving is merge-safe: a save only ever raises catch counts (UpdateAsync
	keeps the bigger number for each bug), so a failed load, two servers or
	a save racing a load can never wipe out earlier catches.

	Saved data, key "player_<UserId>":  { Version = 1, Caught = { [bugId] = timesCaught } }
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local BugData = require(folder:WaitForChild("BugData"))
local Util = require(folder:WaitForChild("Util"))
local create = Util.create

local Collection = {}

-- Set by BugServer to show players a message: notify(player, title, text).
Collection.notify = nil

local profiles = {} -- [player] = { caught = { [bugId] = count }, dirty, saving, loaded }

local store = nil
local storeError = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		storeError = tostring(result)
	end
end

local studioWarned = false
local toldPlayer = setmetatable({}, { __mode = "k" })

-- Data stores are switched off in Studio until the place allows API access.
local function isAccessError(message)
	return string.find(message, "StudioAccessToApis", 1, true) ~= nil
		or string.find(message, "API access", 1, true) ~= nil
		or string.find(message, "publish this place", 1, true) ~= nil
end

local function warnNoAccess(player)
	if not studioWarned then
		studioWarned = true
		warn("[BugCatcher] Saving is off: publish the place and turn on Game Settings > Security > "
			.. "Enable Studio Access to API Services to test saving in Studio.")
	end
	if Collection.notify and player.Parent and not toldPlayer[player] then
		toldPlayer[player] = true
		Collection.notify(player, "Saving is off", "Enable Studio Access to API Services to save.")
	end
end

-- Runs a data store call, retrying a couple of times. Returns ok, result.
local function attempt(label, player, fn)
	if not store then
		warnNoAccess(player)
		return false, storeError
	end
	local lastError = nil
	for try = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if isAccessError(lastError) then
			warnNoAccess(player)
			return false, lastError
		end
		warn(string.format("[BugCatcher] %s for %s failed (try %d of 3): %s", label, player.Name, try, lastError))
		if try < 3 then
			task.wait(try * 2)
		end
	end
	return false, lastError
end

local function keyFor(player)
	return "player_" .. player.UserId
end

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

-- Keeps the bigger count for every bug in `from`.
local function mergeInto(caught, from)
	if type(from) ~= "table" then
		return
	end
	for bugId, count in from do
		count = tonumber(count)
		if type(bugId) == "string" and count and count > 0 then
			caught[bugId] = math.max(caught[bugId] or 0, math.floor(count))
		end
	end
end

local function load(player, profile)
	local ok, data = attempt("Loading", player, function()
		return store:GetAsync(keyFor(player))
	end)
	if not player.Parent or profiles[player] ~= profile then
		return -- left while loading
	end
	if ok then
		if type(data) == "table" then
			mergeInto(profile.caught, data.Caught)
		end
		profile.loaded = true
		publish(player, profile)
	elseif store and not isAccessError(tostring(data)) and Collection.notify then
		Collection.notify(player, "Couldn't load your Bug Book", "New catches still save. Rejoin to see older ones.")
	end
end

local function save(player, profile)
	if not store or not profile.dirty or profile.saving then
		return
	end
	profile.saving = true
	profile.dirty = false
	local snapshot = table.clone(profile.caught)
	local ok = attempt("Saving", player, function()
		store:UpdateAsync(keyFor(player), function(old)
			local data = type(old) == "table" and old or {}
			local caught = type(data.Caught) == "table" and data.Caught or {}
			mergeInto(caught, snapshot)
			data.Caught = caught
			data.Version = 1
			return data
		end)
	end)
	if not ok then
		profile.dirty = true -- try again on the next autosave
	end
	profile.saving = false
end

function Collection.setup(player)
	if profiles[player] then
		return profiles[player]
	end
	local profile = { caught = {}, dirty = false, saving = false, loaded = false }
	profiles[player] = profile
	local stats = player:FindFirstChild("leaderstats") or create("Folder", { Name = "leaderstats", Parent = player })
	if not stats:FindFirstChild("Bugs") then
		create("IntValue", { Name = "Bugs", Parent = stats })
	end
	publish(player, profile)
	task.spawn(load, player, profile)
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

-- Saves a leaving player and forgets them. Yields until the save is done.
function Collection.release(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	while profile.saving do
		task.wait(0.1)
	end
	save(player, profile)
	if profiles[player] == profile then
		profiles[player] = nil
	end
end

function Collection.saveAll()
	for player, profile in profiles do
		task.spawn(save, player, profile)
	end
end

-- Autosave, and save everyone when the server shuts down.
task.spawn(function()
	while true do
		task.wait(Config.AutosaveSeconds)
		Collection.saveAll()
	end
end)

game:BindToClose(function()
	local pending = 0
	for player in profiles do
		pending += 1
		task.spawn(function()
			Collection.release(player)
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.1)
	end
end)

return Collection
