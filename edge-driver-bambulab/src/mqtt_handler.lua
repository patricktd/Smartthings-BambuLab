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
        
        -- Simular sucesso ou falha baseado em algo simples para teste
        if host and options.tls.ca_data and options.tls.ca_data:find("BEGIN CERTIFICATE") and options.mqtt_serial ~= "" then
            log.info("MQTT_CORE_PLACEHOLDER: Conexão simulada com sucesso!")
            if callback then 
                -- Simular chamada assíncrona do callback
                local co = coroutine.create(function() coroutine.yield(); callback(true) end)
                coroutine.resume(co)
            end
            return true, nil -- Indica que a tentativa de conexão foi iniciada
        else
            log.error("MQTT_CORE_PLACEHOLDER: Falha na conexão simulada (configurações incompletas).")
            if callback then 
                local co = coroutine.create(function() coroutine.yield(); callback(false) end)
                coroutine.resume(co)
            end
            return false, "Configuração simulada inválida"
        end
    end
    -- Simular métodos de registo de callbacks
    fake_client.on = function(event_name, callback_func)
        log.info(string.format("MQTT_CORE_PLACEHOLDER: Handler para evento '%s' registado.", event_name))
        -- Guardar callbacks para simulação (opcional, dependendo da complexidade da simulação)
        if not fake_client.event_handlers then fake_client.event_handlers = {} end
        fake_client.event_handlers[event_name] = callback_func
    end
    fake_client.subscribe = function(topic, options, callback) 
        log.info(string.format("MQTT_CORE_PLACEHOLDER: Subscrito a %s com QoS %d", topic, options.qos or 0))
        if callback then 
            local co = coroutine.create(function() coroutine.yield(); callback(topic, options.qos or 0) end) -- Simular sucesso na subscrição
            coroutine.resume(co)
        end
    end
    fake_client.publish = function(topic, payload, options, callback) 
        log.info(string.format("MQTT_CORE_PLACEHOLDER: Publicado em %s: %s (QoS %d, Retain %s)", topic, payload, options.qos or 0, tostring(options.retain)))
        if callback then 
            local co = coroutine.create(function() coroutine.yield(); callback(nil) end) -- Simular sucesso na publicação (sem erro)
            coroutine.resume(co)
        end
    end
    fake_client.disconnect = function() 
        log.info("MQTT_CORE_PLACEHOLDER: Desconectado.")
        -- Simular evento 'close' se houver um handler registado
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
    self.client = nil -- Será a instância do cliente MQTT da sua biblioteca
    self.connected = false
    self.base_topic = string.format("device/%s/", self.config.mqttSerial) -- Tópico base para esta impressora
    self.message_handlers = {} -- Para mapear tópicos a funções de tratamento
    return self
end

function MqttHandler:connect()
    if self.connected then
        log.info(string.format("[%s] MQTT: Já conectado.", self.device.label or self.device.id))
        return true
    end

    log.info(string.format("[%s] MQTT: A tentar conectar ao broker: %s:%d", self.device.label or self.device.id, self.config.ipAddress, self.config.port))

    -- Configuração TLS (ADAPTE À SUA BIBLIOTECA MQTT)
    -- O parâmetro 'verify' ou similar é crucial. "none" pode ser necessário se o certificado
    -- da impressora for auto-assinado (equivalente ao --insecure do mosquitto_sub).
    -- Tente "peer" primeiro se a sua biblioteca o suportar de forma robusta.
    local tls_config = {
        ca_data = self.config.caCertificate, -- A sua biblioteca pode usar um nome diferente para isto (ex: ca_pem)
        -- verify = "none", -- ou "peer", ou outro valor dependendo da sua lib (ex: true/false para verify_peer)
        -- servername = self.config.ipAddress -- Algumas bibliotecas podem precisar disto para SNI ou validação do certificado
    }

    -- Opções de conexão (ADAPTE À SUA BIBLIOTECA MQTT)
    local connect_options = {
        client_id = self.config.mqttClientId,
        username = self.config.username,
        password = self.config.accessToken,
        keepalive = 60,
        tls = tls_config, -- Passa a configuração TLS
        mqtt_serial = self.config.mqttSerial, -- Para log no placeholder, não é um parâmetro MQTT padrão
        -- Adicione aqui outros parâmetros específicos da sua biblioteca (ex: protocol_version, clean_session)
    }

    -- SUBSTITUA ESTA LINHA pela criação real do cliente da sua biblioteca MQTT
    self.client = mqtt_core_placeholder.create_client() -- Ex: mqtt_core.client() ou similar

    -- Registar handlers de eventos ANTES de conectar (ADAPTE À SUA BIBLIOTECA)
    -- A sintaxe exata para registar handlers (ex: client:on('event', func) ou client.on_event = func) varia.
    self.client:on('connect', function() self:_on_connect() end)
    self.client:on('message', function(topic, payload, packet) self:_on_message(topic, payload, packet) end)
    self.client:on('close', function() self:_on_close() end)
    self.client:on('error', function(err) self:_on_error(err) end)

    log.info(string.format("[%s] MQTT: A tentar conectar com o cliente...", self.device.label or self.device.id))
    -- Conectar (ADAPTE À SUA BIBLIOTECA - pode ser síncrono ou assíncrono)
    -- Exemplo para uma biblioteca que usa um callback para o resultado da conexão:
    -- self.client:connect(self.config.ipAddress, self.config.port, connect_options, function(success, err_msg)
    --     if success then
    --         self:_on_connect() -- Chamado aqui se a biblioteca não tiver um evento 'connect' separado
    --     else
    --         self:_on_error(err_msg or "Falha na conexão (callback)")
    --     end
    -- end)
    
    -- Para o nosso placeholder, a conexão é simulada e o callback é chamado dentro do método .connect do placeholder
    local ok, err = self.client.connect(self.config.ipAddress, self.config.port, connect_options, function(success)
        -- Este callback é específico da simulação do placeholder.
        -- Numa biblioteca real, o evento 'connect' ou 'error' seria acionado.
        if success and not self.connected then -- Evitar chamar _on_connect múltiplas vezes se o evento 'connect' também for acionado
            -- _on_connect() -- Normalmente, o evento 'connect' da biblioteca trataria disto.
        elseif not success then
            -- _on_error(err or "Falha na conexão (callback simulado)") -- O evento 'error' trataria disto.
        end
    end)


    if not ok then
        log.error(string.format("[%s] MQTT: Falha ao iniciar tentativa de conexão: %s", self.device.label or self.device.id, tostring(err)))
        self.device:offline()
        self.connected = false
        return false
    end
    -- Se a conexão for assíncrona, o estado 'connected' e 'online' será definido no callback _on_connect
    -- Se for síncrona e 'ok' for true, pode definir aqui (mas o placeholder é assíncrono via callback)
    return true -- Indica que a tentativa de conexão foi iniciada
end

function MqttHandler:_on_connect()
    log.info(string.format("[%s] MQTT: Conectado com sucesso ao broker!", self.device.label or self.device.id))
    self.connected = true
    self.device:online()

    -- Subscrever aos tópicos relevantes após a conexão
    -- Exemplo: Tópico de estado da impressora
    local report_topic = self.base_topic .. "report"
    self:subscribe(report_topic, 0, function(received_topic, payload_string)
        log.info(string.format("[%s] MQTT: Mensagem recebida em REPORT via handler de subscrição: %s", self.device.label or self.device.id, payload_string))
        -- TODO: Parsear o payload JSON e atualizar as capabilities do dispositivo
        -- Exemplo: local data = require("dkjson").decode(payload_string)
        -- if data and data.print and data.print.mc_print_percent then
        --   self.device:emit_event(self.device.profile.capabilities.progressReferenceTime.progress(data.print.mc_print_percent))
        -- end
        -- if data and data.temperature and data.temperature.bed_temp then
        --   self.device:emit_event(self.device.profile.capabilities.temperatureMeasurement.temperature({value = data.temperature.bed_temp, unit = "C"}))
        -- end
    end)
    
    -- Solicitar um estado inicial
    self:request_status_update()
end

-- Este handler de mensagem genérico pode ser usado se a sua biblioteca MQTT emitir um evento 'message' global.
-- Se a sua biblioteca permitir callbacks por subscrição (como no exemplo acima), este pode não ser tão necessário.
function MqttHandler:_on_message(topic, payload_bytes, packet)
    local payload_string = tostring(payload_bytes) -- Converter payload para string
    log.debug(string.format("[%s] MQTT: Mensagem global recebida em '%s': %s", self.device.label or self.device.id, topic, payload_string))

    -- Chamar o handler específico para este tópico, se existir e se não foi tratado pelo callback da subscrição
    if self.message_handlers[topic] then
        self.message_handlers[topic](topic, payload_string)
    else
        log.warn(string.format("[%s] MQTT: Nenhum handler de mensagem global para o tópico: %s", self.device.label or self.device.id, topic))
    end
end

function MqttHandler:_on_close()
    log.info(string.format("[%s] MQTT: Conexão fechada.", self.device.label or self.device.id))
    if self.connected then -- Só atualiza se estava previamente conectado
        self.connected = false
        self.device:offline()
        -- TODO: Implementar lógica de reconexão se desejado (com backoff)
        -- Ex: self.device:timer_event(10, function() self:connect() end) -- Tentar reconectar após 10s
    end
end

function MqttHandler:_on_error(err)
    log.error(string.format("[%s] MQTT: Erro na conexão: %s", self.device.label or self.device.id, tostring(err)))
    if self.connected then -- Só atualiza se estava previamente conectado
      self.connected = false
      self.device:offline()
    end
    -- TODO: Implementar lógica de reconexão
end

function MqttHandler:disconnect()
    if self.client then -- Verifica se o cliente existe antes de tentar desconectar
        log.info(string.format("[%s] MQTT: A desconectar...", self.device.label or self.device.id))
        self.client:disconnect() -- ADAPTE À SUA BIBLIOTECA
        -- O evento 'close' deve tratar de self.connected = false e device:offline()
    else
        self.connected = false -- Garante que o estado é falso se não houver cliente
        self.device:offline()
    end
end

function MqttHandler:is_connected()
    return self.connected
end

-- Função para subscrever a um tópico e associar um handler
function MqttHandler:subscribe(topic, qos_level, handler_func)
    if not self.client or not self.connected then
        log.warn(string.format("[%s] MQTT: Não conectado, não é possível subscrever a %s", self.device.label or self.device.id, topic))
        return
    end
    local options = { qos = qos_level or 0 }
    -- O callback da subscrição pode variar muito entre bibliotecas.
    -- Algumas podem não ter um callback por subscrição e depender de um evento 'message' global.
    self.client:subscribe(topic, options, function(granted_topic_or_err, granted_qos_or_nil) 
        -- Adapte este callback à sua biblioteca.
        -- Algumas podem passar um erro como primeiro argumento se a subscrição falhar.
        -- Outras podem passar o tópico subscrito e o QoS concedido.
        if granted_topic_or_err and type(granted_topic_or_err) == "string" then -- Assumindo sucesso se o tópico for uma string
            log.info(string.format("[%s] MQTT: Subscrito com sucesso a %s com QoS %d", self.device.label or self.device.id, granted_topic_or_err, granted_qos_or_nil or options.qos))
            if handler_func then
                self.message_handlers[topic] = handler_func -- Guardar o handler para este tópico
            end
        else
            log.error(string.format("[%s] MQTT: Falha ao subscrever a %s. Erro/Detalhe: %s", self.device.label or self.device.id, topic, tostring(granted_topic_or_err)))
        end
    end)
end

-- Função para publicar uma mensagem
function MqttHandler:publish(sub_topic, payload, retain_flag)
    if not self.client or not self.connected then
        log.warn(string.format("[%s] MQTT: Não conectado, não é possível publicar em %s", self.device.label or self.device.id, sub_topic))
        return
    end
    local full_topic = self.base_topic .. sub_topic
    local options = { qos = 0, retain = retain_flag or false }
    log.info(string.format("[%s] MQTT: A publicar em '%s': %s", self.device.label or self.device.id, full_topic, payload))
    self.client:publish(full_topic, payload, options, function(err) -- Adapte o callback
        if err then
            log.error(string.format("[%s] MQTT: Falha ao publicar em %s: %s", self.device.label or self.device.id, full_topic, tostring(err)))
        else
            log.debug(string.format("[%s] MQTT: Publicado com sucesso em %s", self.device.label or self.device.id, full_topic))
        end
    end)
end

-- Função para solicitar uma atualização de estado da impressora
function MqttHandler:request_status_update()
    -- O tópico e payload para solicitar atualização de estado dependem da API MQTT da Bambu Lab
    -- Exemplo: pode ser um tópico específico ou um payload para um tópico de comando.
    -- self:publish("command", '{"action": "get_status"}', false)
    log.info(string.format("[%s] MQTT: (Simulado) A solicitar atualização de estado da impressora.", self.device.label or self.device.id))
    -- Para fins de teste com o placeholder, podemos simular uma mensagem de resposta:
    if self.client.event_handlers and self.client.event_handlers.message then
        local co = coroutine.create(function()
            coroutine.yield()
            -- Simular uma mensagem de estado após o pedido
            local fake_report_topic = self.base_topic .. "report"
            local fake_payload = '{"simulated_status": "idle", "temperature": 25, "progress": 0}'
            self.client.event_handlers.message(fake_report_topic, fake_payload, {})
        end)
        coroutine.resume(co)
    end
end

return MqttHandler
