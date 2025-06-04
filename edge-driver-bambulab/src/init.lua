local driver = require "st.driver"
local capabilities = require "st.capabilities"
local device_handler = require "device"
local Discovery = require "discovery"

local bambu_driver = driver.Driver("BambuLab", {
  discovery = Discovery.discover_devices,
  lifecycle_handlers = {
    init = device_handler.init,
    added = device_handler.device_added,
    infoChanged = device_handler.info_changed
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = device_handler.on_handler
    }
  }
})

bambu_driver:run()