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
local cap_status = capabilities["pattetech.status"]

-----------------------------------------------------------------
-- main functions
-----------------------------------------------------------------

-- log to the console if the verbose log setting is switced on
function console_log(device, message, log_level)

	if(device.preferences.verboseLog == true) then

		if(log_level == nil) then log_level = 'debug' end
		log.log({}, log_level, message)

	end
	
end
