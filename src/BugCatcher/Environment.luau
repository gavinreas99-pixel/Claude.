--[[
	Environment: the shared clock and weather.

	The server stores one number, the server time of a sunrise
	(attribute "SunriseTime" on the BugCatcher folder), and whether it's
	raining (attribute "Raining"). Everyone works out the time of day from
	that, so the sun moves smoothly on every screen without any network
	traffic, and the server and clients always agree on day and night.
]]

local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))

local DAY = Config.DayMinutes * 60
local NIGHT = Config.NightMinutes * 60
local CYCLE = DAY + NIGHT

local Environment = {}

-- How many real seconds after sunrise (6:00) a given clock time is.
function Environment.secondsAfterSunrise(clockTime)
	local hours = (clockTime - 6) % 24
	if hours < 12 then
		return hours / 12 * DAY
	end
	return DAY + (hours - 12) / 12 * NIGHT
end

-- The clock time (0-24) a number of real seconds after a sunrise.
function Environment.clockAt(seconds)
	local t = seconds % CYCLE
	if t < DAY then
		return 6 + 12 * t / DAY
	end
	return (18 + 12 * (t - DAY) / NIGHT) % 24
end

function Environment.getClockTime()
	local sunrise = folder:GetAttribute("SunriseTime")
	if type(sunrise) ~= "number" then
		return Config.StartClockTime
	end
	return Environment.clockAt(Workspace:GetServerTimeNow() - sunrise)
end

function Environment.isNight(clockTime)
	local clock = clockTime or Environment.getClockTime()
	return clock < 6 or clock >= 18
end

function Environment.isRaining()
	return folder:GetAttribute("Raining") == true
end

return Environment
