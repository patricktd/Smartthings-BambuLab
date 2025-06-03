-- src/init.lua
local log = require "log"
local driver_template = require "st.driver"
local device_handler = require "device" -- Nosso módulo de lógica do dispositivo
local capabilities = require "st.capabilities" -- Adicionado para referência explícita se necessário

local driver = driver_template.Driver("BambuLab MQTT Driver", {
  discovery = function(self, opts, add_device_fn, ...)
    log.info("Iniciando descoberta para Bambu Lab Printer...")
  end,
  driver_lifecycle_handlers = {
    init = device_handler.init,
  },
  device_lifecycle_handlers = {
    init = device_handler.device_init,
    added = device_handler.device_added,
    doConfigure = device_handler.do_configure,
    infoChanged = device_handler.info_changed,
    removed = device_handler.device_removed,
    driverSwitched = device_handler.driver_switched
  },
  capability_handlers = {
    main = {
      [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = device_handler.on_handler,
        [capabilities.switch.commands.off.NAME] = device_handler.off_handler,
      },
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = device_handler.refresh_handler,
      },
      -- Adicione handlers para suas capabilities customizadas
    }
  }
})

driver:run()