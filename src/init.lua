local Driver = require('st.driver')
local log = require('log')

log.info(">>> Driver Edge BambuLab foi carregado e está aguardando discovery...")

local function discovery(driver, opts, continue)
  log.info(">>> Discovery foi chamado!")
  driver:try_create_device({
    type = "LAN",
    device_network_id = "bambu-single-device",
    label = "Bambu Printer Manual",
    profile = "singleBambuPrinter",
    manufacturer = "Bambu",
    model = "Manual",
    vendor_provided_label = "Bambu Printer Manual"
  })
  log.info(">>> Dispositivo Bambu Printer Manual criado!")
end

local function added_handler(driver, device)
  log.info(">>> Handler ADDED chamado! Device: " .. device.id)
end

local driver = Driver("bambu-printer-simple", {
  discovery = discovery,
  lifecycle_handlers = {
    added = added_handler
  },
})

driver:run()
