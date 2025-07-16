local Driver = require('st.driver')
local log = require('log')
local capabilities = require('st.capabilities')

log.info(">>> Driver Edge BambuLab foi carregado e está aguardando discovery...")

local function discovery(driver, opts, continue)
  log.info(">>> Discovery foi chamado!")
  driver:try_create_device({
    type = "LAN",
    device_network_id = "bambu-device",
    label = "Bambulab Printer",
    profile = "BambuPrinter",
    manufacturer = "Bambulab",
    model = "Manual",
    vendor_provided_label = "Bambu Printer PATTETECH"
  })
  log.info(">>> Dispositivo Bambu Printer Manual criado!")
end

local function added_handler(driver, device)
  log.info(">>> Handler ADDED chamado! Device: " .. device.id)
  -- initialize persistent fields so the driver has default values
  local status = device:get_field("status") or "desconhecido"
  local ip = device:get_field("ip") or device.preferences["printerIp"] or "0.0.0.0"

  device:set_field("status", status, {persist = true})
  device:set_field("ip", ip, {persist = true})

  log.info(string.format(">>> Campos iniciais setados: status=%s, ip=%s", status, ip))

  -- initialize capability values
  device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("stop"))
  device:emit_event(capabilities["patchprepare64330.printerProgress"].percentComplete(0))

end

local driver = Driver("bambu-printer", {
  discovery = discovery,
  lifecycle_handlers = {
    added = added_handler
  },
})

if os.getenv("UNIT_TEST") then
  return {
    driver = driver,
    added_handler = added_handler,
  }
else
  driver:run()
end
