--[[
	Tutorial server: remembers which players have finished the tutorial (so it
	only opens on their first visit) and sets up the notification remote.
	This is a Script with RunContext = Server, so it runs from ReplicatedStorage.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local Notify = require(folder:WaitForChild("Notify")) -- creates the remotes

local DONE = "TutorialDone" -- player attribute the client reads

local store = nil
if Config.Tutorial.SaveProgress then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Tutorial.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[TutorialAndAlerts] can't save tutorial progress: " .. tostring(result))
	end
end

local warned = false
local function storeWarn(err)
	if not warned then
		warned = true
		-- In Studio this usually means "Enable Studio Access to API Services" is off.
		warn("[TutorialAndAlerts] DataStore error, the tutorial will show every visit: " .. tostring(err))
	end
end

local function key(player)
	return "u" .. player.UserId
end

local function onPlayerAdded(player)
	local done = false
	if store then
		local ok, result = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			done = result == true
		else
			storeWarn(result)
		end
	end
	if player.Parent then
		player:SetAttribute(DONE, done)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Notify.Remote.OnServerEvent:Connect(function(player, kind)
	if kind ~= "TutorialDone" or player:GetAttribute(DONE) == true then
		return
	end
	player:SetAttribute(DONE, true)
	if store then
		local ok, err = pcall(function()
			store:SetAsync(key(player), true)
		end)
		if not ok then
			storeWarn(err)
		end
	end
end)
