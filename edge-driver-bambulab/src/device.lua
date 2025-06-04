-- src/device.lua
local log = require "log"
local MqttHandler = require "mqtt_handler"
local capabilities = require "st.capabilities"
local cosock = require "cosock"
local socket = require "cosock.socket" -- Para timers
local st_utils = require "st.utils"

local device_handler = {}

-- Configurações padrão MQTT para BambuLab
local DEFAULT_MQTT_PORT = 8883
local DEFAULT_MQTT_USERNAME = "bblp"
local DISCOVERY_TOPIC = "device/+/report"
local STATUS_TOPIC = "device/status"
local COMMAND_TOPIC = "device/command"

-- Função auxiliar melhorada com fallbacks
local function get_printer_config(device)
  return {
    ip = device.preferences.printerIp or device:get_field("last_known_ip"),
    port = device.preferences.printerPort or DEFAULT_MQTT_PORT,
    username = device.preferences.mqttUsername or DEFAULT_MQTT_USERNAME,
    password = device.preferences.mqttPassword,
    ca_cert = device.preferences.caCertificate,
    discovery_timeout = device.preferences.discoveryTimeout or 5
  }
end

-- Handler de mensagens MQTT genérico
local function handle_mqtt_message(device, topic, payload)
  log.debug(string.format("%s: Mensagem MQTT recebida - Tópico: %s", device.label, topic))
  
  if topic:match(DISCOVERY_TOPIC) then
    -- Processar mensagem de descoberta
    device:set_field("last_seen", os.time(), {persist=true})
    device:emit_event(capabilities.healthCheck.healthStatus.online())
    
  elseif topic == STATUS_TOPIC then
    -- Atualizar status da impressora (exemplo)
    local status = payload:match('"status":"(%w+)"')
    if status then
      device:emit_event(capabilities.printingStatus.printingStatus(status))
    end
  end
end

-- Conexão MQTT com reconexão automática
function device_handler.setup_mqtt(device, initial)
  local config = get_printer_config(device)
  
  -- Validação de IP
  if not config.ip or config.ip == "" then
    log.warn(device.label .. ": IP não configurado - tentando autodetecção")
    device_handler.attempt_discovery(device)
    return false
  end

  -- Gerenciador de conexão existente
  local current_mqtt = device:get_field("mqtt_handler")
  if current_mqtt then
    current_mqtt:disconnect()
  end

  -- Nova conexão
  local mqtt_h = MqttHandler.new(
    device,
    config.ip,
    config.port,
    "st-"..device.id:sub(-6),
    config.username,
    config.password,
    config.ca_cert
  )

  -- Callbacks
  mqtt_h.on_message = handle_mqtt_message
  mqtt_h.on_connect = function()
    log.info(device.label .. ": Conectado ao broker MQTT")
    device:emit_event(capabilities.healthCheck.healthStatus.online())
    mqtt_h:subscribe({DISCOVERY_TOPIC, STATUS_TOPIC})
  end

  mqtt_h.on_disconnect = function()
    log.warn(device.label .. ": Desconectado do MQTT")
    device:emit_event(capabilities.healthCheck.healthStatus.offline())
    
    -- Tentar reconectar após delay
    cosock.spawn(function()
      socket.sleep(30)
      if device:get_field("mqtt_handler") == mqtt_h then
        device_handler.setup_mqtt(device)
      end
    end, "mqtt_reconnect")
  end

  device:set_field("mqtt_handler", mqtt_h, {persist=false})
  
  if not mqtt_h:connect() then
    if initial then
      device_handler.attempt_discovery(device)
    end
    return false
  end
  return true
end

-- Autodetecção MQTT ativa
function device_handler.attempt_discovery(device)
  cosock.spawn(function()
    local config = get_printer_config(device)
    local timeout = config.discovery_timeout
    local found = false
    
    log.info(device.label .. ": Iniciando descoberta MQTT...")
    device:emit_event(capabilities.healthCheck.healthStatus.checking())

    -- Varredura simplificada (substitua por implementação real)
    local ips_to_try = {
      "192.168.1.100", 
      "192.168.1.150",
      device:get_field("last_known_ip")
    }

    for _, ip in ipairs(ips_to_try) do
      if ip and not found then
        local test_client = MqttHandler.new(
          device,
          ip,
          config.port,
          "st-disc-"..st_utils.random_string(4),
          config.username,
          config.password,
          config.ca_cert
        )

        test_client.on_message = function(_, topic, payload)
          if topic:match(DISCOVERY_TOPIC) then
            found = true
            device:set_field("last_known_ip", ip, {persist=true})
            device.preferences.printerIp = ip -- Atualiza preferência
            log.info(device.label .. ": Impressora encontrada em " .. ip)
            test_client:disconnect()
          end
        end

        if test_client:connect(timeout) then
          test_client:subscribe(DISCOVERY_TOPIC)
          socket.sleep(timeout)
          test_client:disconnect()
        end
      end
    end

    if found then
      device_handler.setup_mqtt(device, true)
    else
      log.warn(device.label .. ": Nenhuma impressora encontrada na rede")
      device:emit_event(capabilities.healthCheck.healthStatus.offline({
        reason = "Impressora não encontrada"
      }))
    end
  end, "mqtt_discovery")
end

-- Handlers de ciclo de vida atualizados
function device_handler.init(driver)
  log.info("Driver BambuLab inicializado")
  driver:register_channel_handler("mqtt", function() end) -- Registra canal MQTT
end

function device_handler.device_init(driver, device)
  device:set_field("mqtt_handler", nil, {persist=false})
  device:emit_event(capabilities.healthCheck.healthStatus.checking())
end

function device_handler.device_added(driver, device)
  log.info(device.label .. ": Dispositivo adicionado")
  device_handler.setup_mqtt(device, true)
end

function device_handler.do_configure(driver, device)
  log.info(device.label .. ": Configurando...")
  device_handler.setup_mqtt(device, false)
end

function device_handler.info_changed(driver, device, event, args)
  local old_prefs = args.old_st_store.preferences or {}
  local new_prefs = device.preferences
  
  if new_prefs.printerIp ~= old_prefs.printerIp or
     new_prefs.printerPort ~= old_prefs.printerPort or
     new_prefs.mqttUsername ~= old_prefs.mqttUsername or
     new_prefs.mqttPassword ~= old_prefs.mqttPassword then
    log.info(device.label .. ": Preferências MQTT alteradas - Reconfigurando...")
    device_handler.setup_mqtt(device, false)
  end
end

-- Handlers de comandos atualizados
function device_handler.on_handler(driver, device, command)
  local mqtt_h = device:get_field("mqtt_handler")
  if mqtt_h and mqtt_h.is_connected then
    local success = mqtt_h:publish(COMMAND_TOPIC, '{"command":"start"}')
    if success then
      device:emit_event(capabilities.switch.switch.on())
    end
  else
    device:emit_event(capabilities.healthCheck.healthStatus.offline())
  end
end

function device_handler.refresh_handler(driver, device, command)
  local mqtt_h = device:get_field("mqtt_handler")
  if mqtt_h then
    mqtt_h:publish(COMMAND_TOPIC, '{"command":"status_update"}')
  end
end

return device_handler