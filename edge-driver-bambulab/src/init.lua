-- src/init.lua
local log = require "log"
local driver_template = require "st.driver"
local capabilities = require "st.capabilities"
local device_handler = require "device"
local cosock = require "cosock"
local socket = require "cosock.socket"

local driver = driver_template.Driver("BambuLab MQTT Driver", {
  discovery = function(driver, opts, cons)
    local Discovery = require "discovery"
    
    -- Obter preferências globais do driver (se houver)
    local default_prefs = {
      discovery_timeout = 7,               -- Tempo padrão para descoberta
      mqtt_username = "bblp",             -- Usuário padrão BambuLab
      allow_insecure_tls = false,          -- Segurança padrão
      default_ca_cert = ""                -- Certificado CA padrão vazio
    }
    
    return Discovery.discover_devices(driver, {
      discovery_timeout = default_prefs.discovery_timeout,
      default_access_code = "",            -- Inicia vazio para usuário preencher
      use_ca_cert = not default_prefs.allow_insecure_tls,
      ca_cert_data = default_prefs.default_ca_cert
    }, cons)
  end,

  lifecycle_handlers = {
    init = device_handler.init,
    added = device_handler.device_added,
    infoChanged = device_handler.info_changed
  },

  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = device_handler.on_handler,
      [capabilities.switch.commands.off.NAME] = device_handler.off_handler,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = device_handler.refresh_handler,
    }
  },

  -- Configuração de preferências globais
  driver_lifecycle = {
    added = function(driver, device)
      -- Configura preferências iniciais
      device:update_preferences({
        printerIp = "",
        printerPort = 8883,
        mqttUsername = "bblp",
        mqttPassword = "",                 -- Acesso código vazio inicialmente
        useTLS = true,
        caCertificate = ""                 -- Certificado vazio inicialmente
      })
    end
  }
})

-- Função para tratamento de preferências
function driver:update_preferences(device, args)
  if args.old_st_store.preferences ~= device.preferences then
    -- Reconectar se configurações MQTT mudaram
    if device.preferences.printerIp ~= args.old_st_store.preferences.printerIp or
       device.preferences.mqttPassword ~= args.old_st_store.preferences.mqttPassword or
       device.preferences.caCertificate ~= args.old_st_store.preferences.caCertificate then
      device_handler.setup_mqtt(device, false)
    end
  end
end

-- Inicialização do driver
cosock.spawn(function()
  socket.sleep(1)
  log.info("Driver BambuLab MQTT inicializado")
  driver:run()
end, "driver_init")

return driver