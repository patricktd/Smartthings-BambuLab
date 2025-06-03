-- src/mqtt_handler.lua
local log = require "log"
local mqtt = require "st.net.mqtt"
local dkjson = require "dkjson"
local cosock = require "cosock"
local capabilities = require "st.capabilities" -- Para healthCheck

local MqttHandler = {}
MqttHandler.__index = MqttHandler

-- Modificado para aceitar ca_cert_string
function MqttHandler.new(device, printer_ip, printer_port, client_id, username, password, ca_cert_string)
  local self = setmetatable({}, MqttHandler)
  self.device = device
  self.printer_ip = printer_ip
  self.printer_port = printer_port or 8883
  self.client_id = client_id or ("st-hub-" .. device.id)
  self.username = username
  self.password = password
  self.ca_cert_string = ca_cert_string -- Armazena o CA cert
  self.mqtt_client = nil
  self.is_connected = false
  self.subscriptions = {}
  return self
end

function MqttHandler:connect()
  if self.mqtt_client and self.is_connected then
    log.info(self.device.label .. ": Já conectado ao MQTT.")
    return true
  end

  log.info(self.device.label .. ": Tentando conectar ao MQTT Broker em " .. self.printer_ip .. ":" .. self.printer_port)

  local mqtt_opts = {}
  if self.ca_cert_string and self.ca_cert_string ~= "" then
    log.info(self.device.label .. ": Usando certificado CA customizado para conexão TLS.")
    mqtt_opts.tls = {
      ca = self.ca_cert_string,
      -- servername = self.printer_ip -- Opcional: se o servername for diferente do IP/host
                                    -- e necessário para validação do certificado do servidor.
                                    -- Geralmente não é necessário se o CA customizado for para
                                    -- um broker auto-assinado ou com CA privada.
    }
    -- Se a porta for 8883 (comum para MQTTS), mas não explicitamente definida como TLS,
    -- o SDK pode inferir. Caso contrário, pode ser necessário `tls = true` ou similar
    -- dependendo da biblioteca MQTT subjacente que o SDK do SmartThings usa,
    -- mas geralmente fornecer `opts.tls.ca` é suficiente para habilitar TLS.
  end

  self.mqtt_client = mqtt.new(self.printer_ip, self.printer_port, self.client_id, mqtt_opts) -- Passa as opções MQTT

  self.mqtt_client:set_connect_fn(function(cli)
    log.info(self.device.label .. ": Conectado ao MQTT Broker!")
    self.is_connected = true
    self.device:emit_event(capabilities.healthCheck.healthStatus.healthy())

    for topic, _ in pairs(self.subscriptions) do
      log.info(self.device.label .. ": Subscrevendo ao tópico: " .. topic)
      cli:subscribe(topic)
    end
    self:request_initial_status()
  end)

  self.mqtt_client:set_message_fn(function(cli, topic, payload)
    log.debug(self.device.label .. ": Mensagem MQTT recebida - Tópico: " .. topic .. ", Payload: " .. payload)
    self:handle_message(topic, payload)
  end)

  self.mqtt_client:set_disconnect_fn(function(cli, reason)
    log.warn(self.device.label .. ": Desconectado do MQTT Broker. Razão: " .. tostring(reason))
    self.is_connected = false
    self.device:emit_event(capabilities.healthCheck.healthStatus.unhealthy())
    cosock.spawn(function()
      cosock.sleep(10)
      if not self.is_connected then
        self:connect()
      end
    end)
  end)

  local ok, err = self.mqtt_client:start(self.username, self.password)
  if not ok then
    log.error(self.device.label .. ": Falha ao iniciar cliente MQTT: " .. tostring(err))
    self.is_connected = false
    self.device:emit_event(capabilities.healthCheck.healthStatus.unhealthy())
    return false
  end
  return true
end

function MqttHandler:subscribe_to_printer_topics()
    local topics_to_subscribe = {
        "bambu/printer/status",
        "bambu/printer/temperature/nozzle",
        "bambu/printer/temperature/bed",
        "bambu/printer/print_progress"
        -- Adicione outros tópicos relevantes para sua impressora
    }
    for _, topic in ipairs(topics_to_subscribe) do
        if self.mqtt_client and self.is_connected then
            log.info(self.device.label .. ": Subscrevendo ao tópico: " .. topic)
            self.mqtt_client:subscribe(topic)
        end
        self.subscriptions[topic] = true
    end
end

function MqttHandler:handle_message(topic, payload_str)
  local status, payload_data = dkjson.decode(payload_str)
  if not status then
    log.error(self.device.label .. ": Falha ao decodificar JSON do payload MQTT: " .. tostring(payload_data))
    return
  end

  if topic == "bambu/printer/status" then
    if payload_data.state then
        -- self.device:emit_event(capabilities["namespace.printerStatus"].status(payload_data.state))
        log.info("Printer status: " .. payload_data.state)
    end
  elseif topic == "bambu/printer/temperature/nozzle" then
    if payload_data.temperature then
        self.device:emit_event(capabilities.temperatureMeasurement.temperature({value = payload_data.temperature, unit = "C"}))
        -- self.device:emit_event(capabilities["namespace.nozzleTemperature"].temperature({value = payload_data.temperature, unit = "C"}))
    end
  elseif topic == "bambu/printer/print_progress" then
    if payload_data.progress then
        -- self.device:emit_event(capabilities["namespace.printProgress"].progress(payload_data.progress))
        log.info("Print progress: " .. payload_data.progress .. "%")
    end
  else
    log.warn(self.device.label .. ": Tópico MQTT não tratado: " .. topic)
  end
end

function MqttHandler:publish(topic, message, retain)
  if not self.mqtt_client or not self.is_connected then
    log.error(self.device.label .. ": Não conectado ao MQTT. Não é possível publicar.")
    return false
  end
  local payload_str
  if type(message) == "table" then
    local status_enc, json_str = dkjson.encode(message)
    if not status_enc then
      log.error(self.device.label .. ": Falha ao codificar mensagem para JSON: " .. tostring(json_str))
      return false
    end
    payload_str = json_str
  else
    payload_str = tostring(message)
  end
  log.debug(self.device.label .. ": Publicando MQTT - Tópico: " .. topic .. ", Payload: " .. payload_str)
  local ok, err = self.mqtt_client:publish(topic, payload_str, mqtt.QOS_AT_LEAST_ONCE, retain or false)
  if not ok then
    log.error(self.device.label .. ": Falha ao publicar MQTT: " .. tostring(err))
    return false
  end
  return true
end

function MqttHandler:request_initial_status()
    log.info(self.device.label .. ": Solicitando status inicial da impressora.")
    -- self:publish("bambu/printer/request_status", "1") -- Adapte conforme a API da sua impressora
end

function MqttHandler:disconnect()
  if self.mqtt_client then
    log.info(self.device.label .. ": Desconectando do MQTT Broker.")
    self.mqtt_client:stop()
    self.mqtt_client = nil
    self.is_connected = false
  end
end

return MqttHandler

4.3. src/device.lua
Contém a lógica principal do dispositivo, agora lendo as preferências para a configuração MQTT.

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
