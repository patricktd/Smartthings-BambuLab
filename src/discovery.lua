local log = require "log"
local discovery = {}

function discovery.handle_discovery(driver, _should_continue)
	log.info("Starting BambuLab Discovery")

	local metadata = {
		type = "LAN",
		device_network_id = "bambulab device",
		label = "BambuLab 3D Printer",
		profile = "bambulab.v1",
		manufacturer = "SmartThingsCommunity",
		model = "v1",
		vendor_provided_label = nil
	}

	driver:try_create_device(metadata)
end

return discovery
