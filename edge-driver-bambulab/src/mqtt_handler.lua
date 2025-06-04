-- src/mqtt_handler.lua
local log = require "log"
-- IMPORTANTE: Substitua 'sua_biblioteca_mqtt' pela biblioteca MQTT que você está a usar.
-- Exemplo: local mqtt_core = require "mqtt.client" ou similar.
-- Para este exemplo, usaremos um placeholder que simula o comportamento básico.
local mqtt_core_placeholder = {} 

-- Função de placeholder para simular a biblioteca MQTT
-- Esta parte é apenas para que o código do handler funcione de forma isolada para demonstração.
-- Você DEVE substituir isto pela sua biblioteca MQTT real.
mqtt_core_placeholder.create_client = function()
    local fake_client = {}
    fake_client.connect = function(host, port, options, callback)
        log.info(string.format("MQTT_CORE_PLACEHOLDER: A tentar conectar a %s:%s com utilizador %s", host, port, options.username))
        log.info(string.format("MQTT_CORE_PLACEHOLDER: Usando Certificado CA: %s...", string.sub(options.tls.ca_data or "N/A", 1, 30)))
        log.info(string.format("MQTT_CORE_PLACEHOLDER: Tópico base seria: device/%s/", options.mqtt_serial or "N/A_SERIAL"))
        
        if host and options.tls.ca_data and options.tls.ca_data:find("BEGIN CERTIFICATE") and options.mqtt_serial ~= "" then
            log.info("MQTT_CORE_PLACEHOLDER: Conexão simulada com sucesso!")
            if callback then 
                local co = coroutine.create(function() coroutine.yield(); callback(true) end)
                coroutine.resume(co)
            end
            return true, nil
        else
            log.error("MQTT_CORE_PLACEHOLDER: Falha na conexão simulada (configurações incompletas).")
            if callback then 
                local co = coroutine.create(function() coroutine.yield(); callback(false) end)
                coroutine.resume(co)
            end
            return false, "Configuração simulada inválida"
        end
    end
    fake_client.on = function(event_name, callback_func)
        log.info(string.format("MQTT_CORE_PLACEHOLDER: Handler para evento '%s' registado.", event_name))
        if not fake_client.event_handlers then fake_client.event_handlers = {} end
        fake_client.event_handlers[event_name] = callback_func
    end
    fake_client.subscribe = function(topic, options, callback) 
        log.info(string.format("MQTT_CORE_PLACEHOLDER: Subscrito a %s com QoS %d", topic, options.qos or 0))
        if callback then 
            local co = coroutine.create(function() coroutine.yield(); callback(topic, options.qos or 0) end)
            coroutine.resume(co)
        end
    end
    fake_client.publish = function(topic, payload, options, callback) 
        log.info(string.format("MQTT_CORE_PLACEHOLDER: Publicado em %s: %s (QoS %d, Retain %s)", topic, payload, options.qos or 0, tostring(options.retain)))
        if callback then 
            local co = coroutine.create(function() coroutine.yield(); callback(nil) end)
            coroutine.resume(co)
        end
    end
    fake_client.disconnect = function() 
        log.info("MQTT_CORE_PLACEHOLDER: Desconectado.")
        if fake_client.event_handlers and fake_client.event_handlers.close then
            local co = coroutine.create(function() coroutine.yield(); fake_client.event_handlers.close() end)
            coroutine.resume(co)
        end
    end
    return fake_client
end


local MqttHandler = {}
MqttHandler.__index = MqttHandler

function MqttHandler.new(device, config)
    local self = setmetatable({}, MqttHandler)
    self.device = device
    self.config = config
    self.client = nil
    self.connected = false
    self.base_topic = string.format("device/%s/", self.config.mqttSerial)
    self.message_handlers = {}
    return self
end

function MqttHandler:connect()
    if self.connected then
        log.info(string.format("[%s] MQTT: Já conectado.", self.device.label or self.device.id))
        return true
    end

    log.info(string.format("[%s] MQTT: A tentar conectar ao broker: %s:%d", self.device.label or self.device.id, self.config.ipAddress, self.config.port))

    local tls_config = {
        ca_data = self.config.caCertificate,
        -- verify = "none", -- ou "peer"
    }

    local connect_options = {
        client_id = self.config.mqttClientId,
        username = self.config.username,
        password = self.config.accessToken,
        keepalive = 60,
        tls = tls_config,
        mqtt_serial = self.config.mqttSerial,
    }

    self.client = mqtt_core_placeholder.create_client()

    self.client:on('connect', function() self:_on_connect() end)
    self.client:on('message', function(topic, payload, packet) self:_on_message(topic, payload, packet) end)
    self.client:on('close', function() self:_on_close() end)
    self.client:on('error', function(err) self:_on_error(err) end)

    log.info(string.format("[%s] MQTT: A tentar conectar com o cliente...", self.device.label or self.device.id))
    
    local ok, err = self.client.connect(self.config.ipAddress, self.config.port, connect_options, function(success)
        -- Callback da simulação. Numa lib real, os eventos 'connect'/'error' seriam mais usados.
    end)

    if not ok then
        log.error(string.format("[%s] MQTT: Falha ao iniciar tentativa de conexão: %s", self.device.label or self.device.id, tostring(err)))
        self.device:offline()
        self.connected = false
        return false
    end
    return true
end

function MqttHandler:_on_connect()
    log.info(string.format("[%s] MQTT: Conectado com sucesso ao broker!", self.device.label or self.device.id))
    self.connected = true
    self.device:online()

    local report_topic = self.base_topic .. "report"
    self:subscribe(report_topic, 0, function(received_topic, payload_string)
        log.info(string.format("[%s] MQTT: Mensagem em REPORT via sub-handler: %s", self.device.label or self.device.id, payload_string))
        
        local data = require("dkjson").decode(payload_string) -- Certifique-se que dkjson está disponível ou use outra lib
        if not data then
            log.error(string.format("[%s] MQTT: Falha ao fazer parse do JSON do report: %s", self.device.label or self.device.id, payload_string))
            return
        end

        -- Atualizar capabilities com base nos dados recebidos
        -- Capability: bambuPrinterJobStatus.v1
        if data.print and data.print.gcode_state then
            self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].jobPhase(data.print.gcode_state))
        end
        if data.print and data.print.layer_num then
            self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].currentLayer(data.print.layer_num))
        end
        -- totalLayers pode não vir sempre, ou pode vir de outro campo/tópico
        -- if data.print and data.print.total_layer_num then
        --    self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].totalLayers(data.print.total_layer_num))
        -- end
        if data.print and data.print.mc_remaining_time then -- Tempo em minutos
            self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].remainingTime(data.print.mc_remaining_time))
        end
        -- HMS messages (pode precisar de um parse mais complexo se for uma lista/array)
        -- if data.hms then
        --    local hms_str = utils.stringify_table(data.hms) -- Exemplo, pode ser mais elaborado
        --    self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].hmsMessages(hms_str))
        -- end

        -- Capability: patchprepare64330.bedTemperature
        if data.print and data.print.bed_temper then
            self.device:emit_event(self.device.profile.capabilities["patchprepare64330.bedTemperature"].temperature({ 
                value = data.print.bed_temper, 
                unit = "C" -- Assumindo Celsius, ajuste se necessário
            }))
        end
        
        -- Capability: patchprepare64330.nozzleTemperature
        if data.print and data.print.nozzle_temper then
            self.device:emit_event(self.device.profile.capabilities["patchprepare64330.nozzleTemperature"].temperature({ 
                value = data.print.nozzle_temper, 
                unit = "C" -- Assumindo Celsius, ajuste se necessário
            }))
        end

        -- Capability: patchprepare64330.printProgress
        if data.print and data.print.mc_percent then
            self.device:emit_event(self.device.profile.capabilities["patchprepare64330.printProgress"].progress({
                value = data.print.mc_percent
            }))
        end
    end)
    
    self:request_status_update()
end

function MqttHandler:_on_message(topic, payload_bytes, packet)
    local payload_string = tostring(payload_bytes)
    log.debug(string.format("[%s] MQTT: Mensagem global recebida em '%s': %s", self.device.label or self.device.id, topic, payload_string))

    if self.message_handlers[topic] then
        self.message_handlers[topic](topic, payload_string)
    else
        log.warn(string.format("[%s] MQTT: Nenhum handler de mensagem global para o tópico: %s", self.device.label or self.device.id, topic))
    end
end

function MqttHandler:_on_close()
    log.info(string.format("[%s] MQTT: Conexão fechada.", self.device.label or self.device.id))
    if self.connected then
        self.connected = false
        self.device:offline()
    end
end

function MqttHandler:_on_error(err)
    log.error(string.format("[%s] MQTT: Erro na conexão: %s", self.device.label or self.device.id, tostring(err)))
    if self.connected then
      self.connected = false
      self.device:offline()
    end
end

function MqttHandler:disconnect()
    if self.client then
        log.info(string.format("[%s] MQTT: A desconectar...", self.device.label or self.device.id))
        self.client:disconnect()
    else
        self.connected = false
        self.device:offline()
    end
end

function MqttHandler:is_connected()
    return self.connected
end

function MqttHandler:subscribe(topic, qos_level, handler_func)
    if not self.client or not self.connected then
        log.warn(string.format("[%s] MQTT: Não conectado, não subscrever a %s", self.device.label or self.device.id, topic))
        return
    end
    local options = { qos = qos_level or 0 }
    self.client:subscribe(topic, options, function(granted_topic_or_err, granted_qos_or_nil) 
        if granted_topic_or_err and type(granted_topic_or_err) == "string" then
            log.info(string.format("[%s] MQTT: Subscrito a %s com QoS %d", self.device.label or self.device.id, granted_topic_or_err, granted_qos_or_nil or options.qos))
            if handler_func then
                self.message_handlers[topic] = handler_func
            end
        else
            log.error(string.format("[%s] MQTT: Falha ao subscrever a %s. Erro: %s", self.device.label or self.device.id, topic, tostring(granted_topic_or_err)))
        end
    end)
end

function MqttHandler:publish(sub_topic, payload, retain_flag)
    if not self.client or not self.connected then
        log.warn(string.format("[%s] MQTT: Não conectado, não publicar em %s", self.device.label or self.device.id, sub_topic))
        return
    end
    local full_topic = self.base_topic .. sub_topic
    local options = { qos = 0, retain = retain_flag or false }
    log.info(string.format("[%s] MQTT: A publicar em '%s': %s", self.device.label or self.device.id, full_topic, payload))
    self.client:publish(full_topic, payload, options, function(err)
        if err then
            log.error(string.format("[%s] MQTT: Falha ao publicar em %s: %s", self.device.label or self.device.id, full_topic, tostring(err)))
        else
            log.debug(string.format("[%s] MQTT: Publicado com sucesso em %s", self.device.label or self.device.id, full_topic))
        end
    end)
end

function MqttHandler:request_status_update()
    log.info(string.format("[%s] MQTT: (Simulado) A solicitar atualização de estado da impressora.", self.device.label or self.device.id))
    if self.client.event_handlers and self.client.event_handlers.message then
        local co = coroutine.create(function()
            coroutine.yield()
            local fake_report_topic = self.base_topic .. "report"
            -- Payload JSON de exemplo baseado na estrutura MQTT da Bambu Lab
            local fake_payload = [[
            {
                "print": {
                    "gcode_state": "IDLE",
                    "mc_percent": 0,
                    "mc_remaining_time": 0,
                    "bed_temper": 25.0,
                    "nozzle_temper": 26.1,
                    "layer_num": 0
                },
                "hms": [] 
            }
            ]]
            self.client.event_handlers.message(fake_report_topic, fake_payload, {})
        end)
        coroutine.resume(co)
    end
end

return MqttHandler