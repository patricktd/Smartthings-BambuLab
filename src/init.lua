-- require st provided libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

-- other libraries
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local https = cosock.asyncify "ssl.https"
local ltn12 = require "ltn12"
local json = require "dkjson"

-- require custom handlers from driver package
local discovery = require "discovery"

-- capabilities
local cap_status = capabilities["patchprepare64330.printerStatus"]

-- global variables
local refresh_timer                 -- timer object to refresh data and check online status
local printer_online = false        -- inernal printer online status: true=online, false=offline
local slicer_estimated_time = nil   -- estimated print time from gcode metadata: [int]=seconds, nil=no time (not tried), false=no time (tried)


-----------------------------------------------------------------
-- helper functions
-----------------------------------------------------------------

-- checks if a nested table key exists
-- params: table, "key", ["key", "key",...]
-- returns: boolean 
function isset(o, ...)

	local args = {...}
	local found = true

	for k, v in pairs(args) do
		if(found and o[v] ~= nil) then
			o = o[v]
		else
			found = false
		end
	end
	
	return found

end


function trim(s)

	return string.match(s, "^%s*(.-)%s*$")

end


-- format seconds to "1d 2h 3m" / "4s"
function to_string_time(s)

	seconds = math.floor(s % 60)
	minutes = math.floor((s % (60 * 60)) / 60)
	hours   = math.floor((s % (60 * 60 * 24)) / (60 * 60))
	days    = math.floor(s / (60 * 60 * 24))

	if(days > 0)        then return string.format("%dd %dh %dm", days, hours, minutes)
	elseif(hours > 0)   then return string.format("%dh %dm", hours, minutes)
	elseif(minutes > 0) then return string.format("%dm", minutes)
	else                     return string.format("%ds", seconds)
	end

end


-- escape non-word characters for adding to a url
function urlencode(s)

	return string.gsub(s, "%W", function(c) return string.format("%%%X", string.byte(c)) end)

end


-----------------------------------------------------------------
-- main functions
-----------------------------------------------------------------

-----------------------------------------------------------------
-- smartthings functions
-----------------------------------------------------------------

-- this is called once a device is added by the cloud and synchronized down to the hub
local function device_added(driver, device)
	log.info("[" .. device.id .. "] Adding new Bambulab printer")
end


-- this is called both when a device is added (but after `added`) and after a hub reboots.
local function device_init(driver, device)
	log.info("[" .. device.id .. "] Initializing Bambulab printer")

	-- mark device as online so it can be controlled from the app
	device:online()

	refresh_timer = driver:call_on_schedule(device.preferences.pollOffline, function() refresh_data(driver, device) end)
end


-- this is called when a device is removed by the cloud and synchronized down to the hub
local function device_removed(driver, device)
	log.info("[" .. device.id .. "] Removing Bambulab printer")
end


-- create the driver object
local bambulab_driver = Driver("bambulab", {
	discovery = discovery.handle_discovery,
	lifecycle_handlers = {
		added = device_added,
		init = device_init,
		removed = device_removed,
		infoChanged = handle_infochanged
	},
	capability_handlers = {
		[cap_status.ID] = {
			[cap_status.commands.sendCommand.NAME] = send_command,
		},
	}
})


-- run the driver
moonraker_driver:run()
