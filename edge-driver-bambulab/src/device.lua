-- src/device.lua
local log = require "log"
local MqttHandler = require "mqtt_handler"
local capabilities = require "st.capabilities"
local cosock = require "cosock" -- Se usar timers/spawn diretamente aqui

local device_handler = {}

-- Não mais PRINTER_CONFIG fixo aqui, será lido das preferências

-- Função auxiliar para obter configurações do dispositivo
local function get_printer_config_from_device(device)
  return {
    ip = device.preferences.printerIp,
    port = device.preferences.printerPort,
    username = device.preferences.mqttUsername,
    password = device.preferences.mqttPassword,
    ca_cert = device.preferences.caCertificate
  }
end

function device_handler.init(driver)
  log.info("Driver BambuLab MQTT inicializado.")
end

function device_handler.device_init(driver, device)
  log.info(string.format("Dispositivo %s (ID: %s) inicializado.", device.label, device.id))
  device:set_field("mqtt_handler", nil, {persist = false})
  -- Inicializar estados padrão
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.healthCheck.healthStatus.checking())
  -- As preferências são lidas em 'added' e 'infoChanged' / 'doConfigure'
end

local function setup_mqtt_connection(device)
  log.info(device.label .. ": Configurando conexão MQTT.")
  local current_mqtt_h = device:get_field("mqtt_handler")
  if current_mqtt_h then
    current_mqtt_h:disconnect() -- Desconecta o handler antigo, se houver
  end

  local config = get_printer_config_from_device(device)

  if not config.ip or config.ip == "" then
    log.error(device.label .. ": IP da impressora não configurado nas preferências.")
    device:emit_event(capabilities.healthCheck.healthStatus.offline({
      reason = "IP da impressora não configurado"
    }))
    return
  end

  log.info(string.format(device.label .. ": Configurações MQTT - IP: %s, Porta: %s, User: %s, CA Fornecido: %s",
    config.ip,
    tostring(config.port),
    config.username or "Nenhum",
    (config.ca_cert and config.ca_cert ~= "") and "Sim" or "Não"
  ))

  local mqtt_h = MqttHandler.new(
    device,
    config.ip,
    config.port,
    "st-bambulab-" .. device.id,
    config.username,
    config.password,
    config.ca_cert -- Passa o CA cert
  )
  device:set_field("mqtt_handler", mqtt_h, {persist = false})

  if mqtt_h:connect() then
    mqtt_h:subscribe_to_printer_topics()
  else
    log.error(device.label .. ": Falha ao conectar ao MQTT na configuração.")
    device:emit_event(capabilities.healthCheck.healthStatus.offline({
        reason = "Falha ao conectar ao broker MQTT"
    }))
  end
end

function device_handler.device_added(driver, device)
  log.info(string.format("Dispositivo %s (ID: %s) adicionado.", device.label, device.id))
  -- As preferências devem estar disponíveis aqui
  setup_mqtt_connection(device)
end

function device_handler.do_configure(driver, device)
  log.info(string.format("Configurando dispositivo %s (do_configure)...", device.label))
  -- Chamado após 'added' ou 'infoChanged' se as preferências mudarem
  setup_mqtt_connection(device)
end

function device_handler.info_changed(driver, device, event, args)
  log.info(string.format("Informações do dispositivo %s alteradas. Evento: %s", device.label, event))
  -- Se as preferências relevantes para a conexão mudarem, do_configure será chamado.
  -- args.old_st_store contém as preferências antigas.
  -- Podemos verificar especificamente se as preferências de conexão mudaram.
  local relevant_prefs_changed = false
  local old_prefs = args.old_st_store.preferences
  if old_prefs then
    if device.preferences.printerIp ~= old_prefs.printerIp or
       device.preferences.printerPort ~= old_prefs.printerPort or
       device.preferences.mqttUsername ~= old_prefs.mqttUsername or
       device.preferences.mqttPassword ~= old_prefs.mqttPassword or
       device.preferences.caCertificate ~= old_prefs.caCertificate then
      relevant_prefs_changed = true
    end
  end

  if relevant_prefs_changed then
    log.info(device.label .. ": Preferências de conexão MQTT alteradas. Reconfigurando...")
    -- do_configure será chamado pelo sistema, não precisa chamar setup_mqtt_connection diretamente aqui
    -- a menos que queira forçar uma ação imediata antes do ciclo de vida padrão.
  end
end

function device_handler.device_removed(driver, device)
  log.info(string.format("Dispositivo %s removido.", device.label))
  local mqtt_h = device:get_field("mqtt_handler")
  if mqtt_h then
    mqtt_h:disconnect()
  end
  device:set_field("mqtt_handler", nil)
end

function device_handler.driver_switched(driver, device)
    log.info(string.format("Driver trocado para o dispositivo %s.", device.label))
    setup_mqtt_connection(device)
end

--- Handlers de Capabilities ---
function device_handler.on_handler(driver, device, command)
  log.info(string.format("Comando ON recebido para %s", device.label))
  local mqtt_h = device:get_field("mqtt_handler")
  if mqtt_h and mqtt_h.is_connected then
    -- mqtt_h:publish("bambu/printer/command", { "action" = "power_on" }) -- Adapte
    device:emit_event(capabilities.switch.switch.on())
    log.info(device.label .. ": Comando 'ON' (simulado) executado.")
  else
    log.error(device.label .. ": Handler MQTT não encontrado ou não conectado para comando ON.")
    device:emit_event(capabilities.switch.switch.on()) -- Pode emitir o evento mesmo assim ou um erro
    device:emit_event(capabilities.healthCheck.healthStatus.offline({reason = "MQTT não conectado"}))
  end
end

function device_handler.off_handler(driver, device, command)
  log.info(string.format("Comando OFF recebido para %s", device.label))
  local mqtt_h = device:get_field("mqtt_handler")
  if mqtt_h and mqtt_h.is_connected then
    -- mqtt_h:publish("bambu/printer/command", { "action" = "power_off" }) -- Adapte
    device:emit_event(capabilities.switch.switch.off())
    log.info(device.label .. ": Comando 'OFF' (simulado) executado.")
  else
    log.error(device.label .. ": Handler MQTT não encontrado ou não conectado para comando OFF.")
    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.healthCheck.healthStatus.offline({reason = "MQTT não conectado"}))
  end
end

function device_handler.refresh_handler(driver, device, command)
  log.info(string.format("Comando REFRESH recebido para %s", device.label))
  local mqtt_h = device:get_field("mqtt_handler")
  if mqtt_h and mqtt_h.is_connected then
    mqtt_h:request_initial_status()
    log.info(device.label .. ": Solicitação de refresh enviada.")
  else
    log.error(device.label .. ": Handler MQTT não encontrado ou não conectado para comando REFRESH.")
     device:emit_event(capabilities.healthCheck.healthStatus.offline({reason = "MQTT não conectado"}))
  end
end

return device_handler