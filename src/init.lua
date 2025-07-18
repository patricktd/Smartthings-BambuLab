local Driver = require('st.driver')
local log = require('log')
local capabilities = require('st.capabilities')

log.info(">>> Starting driver... <<<")

-- =================================================================
-- Handler that processes the printer's packet when it arrives
-- =================================================================
local function bambu_ssdp_handler(driver, ssdp_packet)
  log.info("[BAMBU LOG] >>> SSDP PACKET RECEIVED! Processing...")

  local serial_number = ssdp_packet.usn
  local device_label = ssdp_packet['DevName.bambu.com'] or ("Bambu Lab " .. serial_number)
  log.info(string.format("[BAMBU LOG] >>> PRINTER FOUND: %s (S/N: %s)", device_label, serial_number))

  local metadata = {
    profile = "bambulab.discovered-printer.v1",
    device_network_id = serial_number,
    label = device_label
  }
  -- Device creation happens here
  driver:try_create_device(metadata)
end

-- =================================================================
-- Generic Discovery Handler (Our Entry Point)
-- =================================================================
local function start_discovery(driver)
  log.info("[BAMBU LOG] >>> Generic 'discovery' handler called on startup.")
  
  -- Sets which function will handle SSDP packets when they arrive
  driver:set_ssdp_handler(bambu_ssdp_handler, "urn:bambulab-com:device:3dprinter:1")
  
  -- Starts listening on the network
  driver:discover()
  
  log.info("[BAMBU LOG] >>> SSDP listener started successfully. Awaiting printer packets...")
end

local bambu_driver = Driver("bambup", {

  -- The only thing we define in the constructor is our entry point.
  discovery = start_discovery
})

-- Run the driver
bambu_driver:run()