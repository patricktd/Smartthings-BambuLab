local Driver = require('st.driver')
local log = require('log')
local capabilities = require('st.capabilities')

log.info(">>> Driver Bambu Printer carregado...")

local function discovery(driver, opts, continue)
  log.info(">>> Discovery chamado!")
  local new_dni = string.format("bambulab-manual-%s", os.time())
  log.info(">>> Gerando novo DNI: " .. new_dni)
  
  driver:try_create_device({
    type = "LAN",
    device_network_id = new_dni,
    label = "Bambulab Printer",
    profile = "BambuPrinter.v1" -- <--- NOME ALINHADO COM O PERFIL
  })
end

local function added_handler(driver, device)
  log.info(string.format(">>> Handler ADDED chamado para o dispositivo: %s", device.id))
  device:emit_event(capabilities["patchprepare64330.printerStatus"].printerStatus("Offline: Configure"))
  device:emit_event(capabilities["patchprepare64330.printerProgress"].percentComplete(0))
end

-- Usa o packageKey definido no config.yaml
local driver = Driver("bambu-printer-patricktd", { -- <--- NOME ALINHADO COM O packageKey
  discovery = discovery,
  lifecycle_handlers = {
    added = added_handler,
    -- Vamos adicionar o infoChanged aqui para o futuro
    infoChanged = function(driver, device)
      log.info(string.format(">>> Configurações alteradas para: %s", device.label))
      -- A lógica MQTT virá aqui
    end
  },
})

driver:run()