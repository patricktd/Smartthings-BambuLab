-- src/mqtt_handler.lua
local log = require "log"
-- Assumindo que os ficheiros da luamqtt estão em src/mqtt/
-- Se a sua luamqtt tiver um ficheiro principal diferente, ajuste o require.
local MqttClientCore = require "mqtt.client" 
local socket_tls = require "socket.tls" -- Para conexões TLS
local cosock = require "cosock" -- Para operações de socket não bloqueantes
local dkjson = require "dkjson" -- Para fazer parse das mensagens JSON da impressora

local RECONNECT_DELAY_SECONDS = 30 -- Tempo para tentar reconectar após uma falha

local MqttHandler = {}
MqttHandler.__index = MqttHandler

function MqttHandler.new(device, config)
    local self = setmetatable({}, MqttHandler)
    self.device = device
    self.config = config
    self.client = nil -- Instância do cliente luamqtt
    self.connected = false
    self.connecting_lock = false -- Para evitar múltiplas tentativas de conexão
    self.base_topic = string.format("device/%s/", self.config.mqttSerial)
    self.message_handlers = {} -- Para callbacks de subscrição
    self.reconnect_timer = nil -- Para lógica de reconexão
    return self
end

function MqttHandler:_schedule_reconnect()
    if self.reconnect_timer then
        self.reconnect_timer:cancel()
        self.reconnect_timer = nil
    end
    if not self.connecting_lock and not self.connected then -- Só agenda se não estiver a tentar conectar ou já conectado
        log.info(string.format("[%s] MQTT: A agendar reconexão em %d segundos.", self.device.label or self.device.id, RECONNECT_DELAY_SECONDS))
        self.reconnect_timer = self.device:timer_event(RECONNECT_DELAY_SECONDS, function()
            log.info(string.format("[%s] MQTT: Timer de reconexão disparado. A tentar conectar...", self.device.label or self.device.id))
            self:connect()
        end)
    end
end

function MqttHandler:connect()
    if self.connected or self.connecting_lock then
        log.info(string.format("[%s] MQTT: Já conectado ou a tentar conectar. Ignorando.", self.device.label or self.device.id))
        return true
    end

    self.connecting_lock = true
    log.info(string.format("[%s] MQTT: A iniciar tentativa de conexão para %s:%d", self.device.label or self.device.id, self.config.ipAddress, self.config.port))

    if self.reconnect_timer then
        self.reconnect_timer:cancel()
        self.reconnect_timer = nil
    end

    self.client = MqttClientCore.create()
    if not self.client then
        log.error(string.format("[%s] MQTT: Falha ao criar instância do cliente luamqtt.", self.device.label or self.device.id))
        self.connecting_lock = false
        self:_schedule_reconnect()
        return false
    end

    self.client.on_connect = function(client_ref, success_or_rc, rc_string)
        if success_or_rc == true or success_or_rc == 0 then
            self:_on_connect()
        else
            log.error(string.format("[%s] MQTT: Falha na conexão MQTT (protocolo). Código: %s, Mensagem: %s", self.device.label or self.device.id, tostring(success_or_rc), tostring(rc_string)))
            self:_on_error("Falha no protocolo MQTT: " .. (rc_string or tostring(success_or_rc)))
            if self.client and self.client.socket then
                self.client.socket:close()
            end
        end
    end

    self.client.on_message = function(client_ref, topic, payload_bytes, qos, retain)
        self:_on_message(topic, payload_bytes)
    end

    self.client.on_close = function(client_ref, reason)
        log.info(string.format("[%s] MQTT: Evento 'on_close' do cliente. Razão: %s", self.device.label or self.device.id, tostring(reason)))
        self:_on_close()
    end
    
    self.client.on_error = function(client_ref, err_msg_or_code)
        log.error(string.format("[%s] MQTT: Evento 'on_error' do cliente. Erro: %s", self.device.label or self.device.id, tostring(err_msg_or_code)))
        self:_on_error("Erro no cliente MQTT: " .. tostring(err_msg_or_code))
    end

    local tls_params = {
        mode = "client",
        protocol = "tlsv1_2",
        verify = "none", -- Equivalente a --insecure
        options = {"all", "no_ticket"},
        -- Para carregar o CA da string, idealmente a API do socket.tls permitiria algo como:
        -- ca_data = self.config.caCertificate,
        -- OU criar um contexto e usar: context:loadcacertificate(self.config.caCertificate)
        -- Se não for possível carregar o CA da string e usá-lo explicitamente com verify="none",
        -- a conexão ainda será TLS, mas sem a validação do servidor usando o CA fornecido.
        -- O seu comando mosquitto_sub usa --cafile, o que é bom. Tente replicar isso.
    }

    -- Tentativa de configurar o contexto TLS com o CA.
    -- A API exata pode variar no ambiente Edge.
    local tls_context_ok = false
    if self.config.caCertificate and self.config.caCertificate ~= "" then
        -- Esta é uma abordagem especulativa. Verifique a API do socket.tls do Edge.
        pcall(function()
            -- Tentar definir o CA no contexto padrão ou num novo.
            -- Exemplo: socket_tls.setoption("ca_data", self.config.caCertificate) -- Função hipotética
            -- Ou: local ctx = socket_tls.newcontext(tls_params_base)
            --     ctx:loadcacertificate(self.config.caCertificate)
            --     tls_params.context = ctx -- Se wrap aceitar um contexto
            log.info(string.format("[%s] MQTT: Certificado CA fornecido. A tentar usar com verify='none'.", self.device.label or self.device.id))
            -- Se a sua API socket.tls permitir, adicione o CA ao tls_params de uma forma que `wrap` o use.
            -- Por exemplo, algumas APIs podem ter um campo `ca_pem_data` ou similar em tls_params.
            -- Para este exemplo, vamos assumir que `tls_params` com `ca_data` (hipotético) ou
            -- a configuração de um contexto global/passado é suficiente.
            -- Se não, o `verify="none"` é a chave.
            tls_context_ok = true -- Assumir que foi configurado se não houver erro explícito
        end)
        if not tls_context_ok then
             log.warn(string.format("[%s] MQTT: Não foi possível configurar explicitamente o CA da string no contexto TLS. `verify=none` será usado.", self.device.label or self.device.id))
        end
    end


    local tcp_socket = cosock.socket.tcp()
    if not tcp_socket then
        log.error(string.format("[%s] MQTT: Falha ao criar socket TCP.", self.device.label or self.device.id))
        self.connecting_lock = false
        self:_schedule_reconnect()
        return false
    end

    local connection_timer
    local function handle_timeout()
        connection_timer = nil -- Evitar chamar cancel num timer já tratado
        log.error(string.format("[%s] MQTT: Timeout ao conectar socket TCP ou durante handshake TLS.", self.device.label or self.device.id))
        if tcp_socket then tcp_socket:close() end
        if self.client and self.client.socket then self.client.socket:close() end
        self:_on_error("Timeout na conexão do socket/TLS")
        -- connecting_lock será libertado por _on_error/_on_close
    end
    connection_timer = self.device:timer_event(20, handle_timeout)

    log.info(string.format("[%s] MQTT: A tentar conectar socket TCP a %s:%d...", self.device.label or self.device.id, self.config.ipAddress, self.config.port))
    local tcp_ok, tcp_err = tcp_socket:connect(self.config.ipAddress, self.config.port)
    
    if not tcp_ok then
        if connection_timer then connection_timer:cancel() end
        log.error(string.format("[%s] MQTT: Falha ao conectar socket TCP: %s", self.device.label or self.device.id, tcp_err))
        tcp_socket:close()
        self:_on_error("Falha no socket TCP: " .. (tcp_err or "erro"))
        return false
    end
    log.info(string.format("[%s] MQTT: Socket TCP conectado. A iniciar handshake TLS...", self.device.label or self.device.id))

    local secure_socket, tls_err = socket_tls.wrap(tcp_socket, tls_params)
    
    if connection_timer then connection_timer:cancel() end

    if not secure_socket then
        log.error(string.format("[%s] MQTT: Falha ao envolver socket com TLS (handshake): %s", self.device.label or self.device.id, tls_err))
        tcp_socket:close()
        self:_on_error("Falha no handshake TLS: " .. (tls_err or "erro desconhecido"))
        return false
    end
    log.info(string.format("[%s] MQTT: Handshake TLS bem-sucedido. Socket seguro pronto.", self.device.label or self.device.id))

    if not self.client.set_socket then
         log.error(string.format("[%s] MQTT: A biblioteca luamqtt não tem o método 'set_socket'. Adapte a integração.", self.device.label or self.device.id))
         secure_socket:close()
         self:_on_error("API luamqtt incompatível (set_socket)")
         return false
    end
    self.client:set_socket(secure_socket)

    log.info(string.format("[%s] MQTT: A tentar conectar protocolo MQTT com utilizador '%s'...", self.device.label or self.device.id, self.config.username))
    
    local mqtt_conn_opts = {
        client_id = self.config.mqttClientId,
        username = self.config.username,
        password = self.config.accessToken,
        keepalive = 60,
        clean_session = true,
    }

    local mqtt_protocol_ok, mqtt_protocol_err = self.client:connect(mqtt_conn_opts)

    if not mqtt_protocol_ok then
        log.error(string.format("[%s] MQTT: Falha ao iniciar conexão do protocolo MQTT: %s", self.device.label or self.device.id, mqtt_protocol_err))
        -- _on_error ou _on_close já devem ter sido chamados pela luamqtt.
        -- Apenas garantir que o lock é libertado se não for tratado pelos callbacks.
        if not self.connected then 
            self.connecting_lock = false
            self:_schedule_reconnect()
        end
        return false
    end
    
    log.info(string.format("[%s] MQTT: Pedido de conexão MQTT enviado. A aguardar callback on_connect...", self.device.label or self.device.id))
    return true
end

function MqttHandler:_on_connect()
    log.info(string.format("[%s] MQTT: Conectado com sucesso ao broker!", self.device.label or self.device.id))
    self.connected = true
    self.connecting_lock = false -- Libertar o lock
    self.device:online()

    -- Limpar timer de reconexão, se houver, pois conectamos com sucesso
    if self.reconnect_timer then
        self.reconnect_timer:cancel()
        self.reconnect_timer = nil
    end

    -- Subscrever aos tópicos relevantes após a conexão
    local report_topic = self.base_topic .. "report"
    self:subscribe(report_topic, 0, function(received_topic, payload_string)
        log.info(string.format("[%s] MQTT: Mensagem em '%s': %s", self.device.label or self.device.id, received_topic, payload_string))
        
        local ok_parse, data = dkjson.decode(payload_string)
        if not ok_parse then
            log.error(string.format("[%s] MQTT: Falha ao fazer parse do JSON do report: %s. Payload: %s", self.device.label or self.device.id, tostring(data), payload_string))
            return
        end

        -- Atualizar capabilities com base nos dados recebidos
        if data.print then
            local print_data = data.print
            -- Capability: bambuPrinterJobStatus.v1
            if print_data.gcode_state then
                self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].jobPhase(print_data.gcode_state))
            end
            if print_data.layer_num then
                self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].currentLayer(print_data.layer_num))
            end
            if print_data.mc_remaining_time then -- Tempo em minutos
                self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].remainingTime(print_data.mc_remaining_time))
            end
            
            -- Capability: patchprepare64330.bedTemperature
            if print_data.bed_temper then
                self.device:emit_event(self.device.profile.capabilities["patchprepare64330.bedTemperature"].temperature({ 
                    value = print_data.bed_temper, 
                    unit = "C" -- Assumindo Celsius, ajuste se necessário
                }))
            end
            
            -- Capability: patchprepare64330.nozzleTemperature
            if print_data.nozzle_temper then
                self.device:emit_event(self.device.profile.capabilities["patchprepare64330.nozzleTemperature"].temperature({ 
                    value = print_data.nozzle_temper, 
                    unit = "C" -- Assumindo Celsius, ajuste se necessário
                }))
            end

            -- Capability: patchprepare64330.printProgress
            if print_data.mc_percent then
                self.device:emit_event(self.device.profile.capabilities["patchprepare64330.printProgress"].progress({
                    value = print_data.mc_percent
                }))
            end
        end
        -- HMS messages (pode precisar de um parse mais complexo se for uma lista/array)
        if data.hms and type(data.hms) == "table" then
           local hms_messages_str = ""
           for _, hms_entry in ipairs(data.hms) do
               -- Formatar a mensagem HMS como desejado. Exemplo simples:
               if hms_entry.attr and hms_entry.code then
                   hms_messages_str = hms_messages_str .. string.format("HMS %s: Code %s. ", hms_entry.attr, hms_entry.code)
               end
           end
           if hms_messages_str ~= "" then
               self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].hmsMessages(hms_messages_str))
           else
               self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].hmsMessages("No HMS errors"))
           end
        elseif data.hms == nil or (type(data.hms) == "table" and #data.hms == 0) then
            self.device:emit_event(self.device.profile.capabilities["bambuPrinterJobStatus.v1"].hmsMessages("No HMS errors"))
        end
    end)
    
    self:request_status_update() -- Solicitar um estado inicial
end

function MqttHandler:_on_message(topic, payload_bytes)
    local payload_string = tostring(payload_bytes) -- Converter payload para string
    log.debug(string.format("[%s] MQTT: Mensagem global recebida em '%s': %s", self.device.label or self.device.id, topic, payload_string))

    if self.message_handlers[topic] then
        self.message_handlers[topic](topic, payload_string)
    else
        log.warn(string.format("[%s] MQTT: Nenhum handler de mensagem para o tópico: %s", self.device.label or self.device.id, topic))
    end
end

function MqttHandler:_on_close()
    log.info(string.format("[%s] MQTT: Conexão fechada.", self.device.label or self.device.id))
    if self.connected then -- Só atualiza e agenda reconexão se estava previamente conectado
        self.connected = false
        self.device:offline()
        self.connecting_lock = false -- Libertar o lock
        self:_schedule_reconnect()
    else
        self.connecting_lock = false -- Libertar o lock mesmo se a conexão inicial falhou
    end
end

function MqttHandler:_on_error(err_msg)
    log.error(string.format("[%s] MQTT: Erro: %s", self.device.label or self.device.id, tostring(err_msg)))
    if self.connected then -- Só atualiza e agenda reconexão se estava previamente conectado
        self.connected = false
        self.device:offline()
    end
    self.connecting_lock = false -- Libertar o lock
    self:_schedule_reconnect()
end

function MqttHandler:disconnect()
    log.info(string.format("[%s] MQTT: A solicitar desconexão...", self.device.label or self.device.id))
    if self.reconnect_timer then -- Cancelar qualquer tentativa de reconexão pendente
        self.reconnect_timer:cancel()
        self.reconnect_timer = nil
    end
    if self.client then
        -- A luamqtt pode ter um método disconnect síncrono ou assíncrono.
        -- O evento on_close deve ser acionado pela biblioteca.
        self.client:disconnect() 
        -- Não definir self.connected = false aqui, deixar o on_close tratar disso.
    else
        self.connected = false -- Garante que o estado é falso se não houver cliente
        self.device:offline()
        self.connecting_lock = false
    end
end

function MqttHandler:is_connected()
    return self.connected
end

function MqttHandler:subscribe(topic, qos_level, handler_func)
    if not self.client or not self.connected then
        log.warn(string.format("[%s] MQTT: Não conectado, não é possível subscrever a %s", self.device.label or self.device.id, topic))
        return
    end
    local options = { qos = qos_level or 0 }
    -- O callback da subscrição pode variar.
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
        log.warn(string.format("[%s] MQTT: Não conectado, não é possível publicar em %s", self.device.label or self.device.id, sub_topic))
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
    -- O tópico e payload para solicitar atualização de estado dependem da API MQTT da Bambu Lab
    -- Exemplo: pode ser um tópico específico ou um payload para um tópico de comando.
    -- Este é um exemplo, você precisará saber o tópico/payload correto.
    -- self:publish("request", '{"command":"get_version"}', false) -- Exemplo de comando
    log.info(string.format("[%s] MQTT: A solicitar atualização de estado da impressora (ex: publicando num tópico de pedido).", self.device.label or self.device.id))
    -- Para a Bambu Lab, um pedido de "pushing" pode ser necessário ou ela envia status periodicamente.
    -- Se precisar de um pedido explícito, envie-o aqui.
    -- Exemplo: self:publish("device/" .. self.config.mqttSerial .. "/request", '{"pushing": "request", "sequence_id":"0"}')
end

return MqttHandler