--[[
	Show notifications from your own scripts.

	From a server Script:
		local Notify = require(game.ReplicatedStorage.TutorialAndAlerts.Notify)

		Notify.IslandUnlocked(player, "Frost Peaks")               -- island banner; details come from Config.Islands
		Notify.IslandUnlocked(player, "Frost Peaks", "Icy cliffs")  -- or give your own description
		Notify.LevelUp(player, 12)                                   -- level-up banner (normally automatic)
		Notify.Toast(player, "Quest complete", "+50 XP")             -- small pop-up in the corner
		Notify.ToastAll("Double XP", "For the next 10 minutes!")     -- small pop-up for everyone
		Notify.ShowTutorial(player)                                  -- open the tutorial from the start

	From a LocalScript the same calls work for the local player.
	The same banner never shows twice, so it's safe to call these even when
	the automatic level / island detection also spots the change.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local folder = script.Parent
local remote, localEvent

if RunService:IsServer() then
	remote = folder:FindFirstChild("AlertRemote") or Instance.new("RemoteEvent")
	remote.Name = "AlertRemote"
	remote.Parent = folder
	localEvent = folder:FindFirstChild("LocalAlert") or Instance.new("BindableEvent")
	localEvent.Name = "LocalAlert"
	localEvent.Parent = folder
else
	remote = folder:WaitForChild("AlertRemote")
	localEvent = folder:WaitForChild("LocalAlert")
end

local function send(player, kind, ...)
	if RunService:IsServer() then
		remote:FireClient(player, kind, ...)
	elseif player == Players.LocalPlayer then
		localEvent:Fire(kind, ...)
	end
end

local Notify = {}

Notify.Remote = remote
Notify.LocalEvent = localEvent

function Notify.LevelUp(player, level)
	send(player, "LevelUp", level)
end

function Notify.IslandUnlocked(player, islandName, description)
	send(player, "Island", islandName, description)
end

function Notify.Toast(player, title, text)
	send(player, "Toast", title, text)
end

function Notify.ToastAll(title, text)
	if RunService:IsServer() then
		remote:FireAllClients("Toast", title, text)
	else
		localEvent:Fire("Toast", title, text)
	end
end

function Notify.ShowTutorial(player)
	send(player, "ShowTutorial")
end

return Notify
