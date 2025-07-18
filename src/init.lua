-- src/init.lua - A NOSSA BASE DE TRABALHO FINAL
local Driver = require('st.driver')
local log = require('log')
local capabilities = require('st.capabilities')

log.info(">>> Driver Edge BambuLab foi carregado e está aguardando discovery...")

-- CRIA OS DISPOSITIVOS
local function discovery(driver, opts, continue)
  log.info(">>> Discovery foi chamado!")
  local new_dni = string.format("bambulab-manual-%s", os.time())
  log.info(">>> Gerando novo ID único para o dispositivo: " .. new_dni)
  
  driver:try_create_device({
    type = "LAN",
    device_network_id = new_dni,
    label = "Bambulab Printer",
    profile = "BambuPrinter"
  })
end

-- CONFIGURA OS DISPOSITIVOS CRIADOS
local function added_handler(driver, device)
  log.info(">>> Handler ADDED chamado! Device: " .. device.id)
  device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("Offline: Configure"))
  device:emit_event(capabilities["patchprepare64330.printerProgress"].percentComplete(0))
end

-- CONSTRÓI O DRIVER
local driver = Driver("bambu-printer", {
  discovery = discovery,
  lifecycle_handlers = {
    added = added_handler
  },
})

-- INICIA O DRIVER
driver:run()