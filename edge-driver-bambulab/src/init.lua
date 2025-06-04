-- src/init.lua

local driver_template = require "st.driver"
local log = require "log"
local MqttHandler = require "mqtt_handler" -- O nosso módulo MQTT
local utils = require "st.utils" -- Para deep_compare e stringify_table

-- Função para obter a configuração do dispositivo a partir das preferências
local function get_device_config(device)
    local prefs = device.preferences
    -- Validação básica para garantir que as preferências existem
    return {
        ipAddress = prefs.ipAddress or "",
        port = prefs.port or 8883,
        username = prefs.username or "bblp",
        accessToken = prefs.accessToken or "",
        caCertificate = prefs.caCertificate or "",
        mqttSerial = prefs.mqttSerial or "",
        mqttClientId = prefs.mqttClientId or device.id -- Usa o ID do dispositivo se não especificado
    }
end

-- Função para validar se a configuração essencial está presente
local function validate_config(config)
    if not config.ipAddress or config.ipAddress == "" then return false, "Endereço IP não configurado" end
    if not config.accessToken or config.accessToken == "" then return false, "Access Token não configurado" end
    if not config.caCertificate or not config.caCertificate:find("BEGIN CERTIFICATE") then return false, "Certificado CA inválido ou não configurado" end
    if not config.mqttSerial or config.mqttSerial == "" then return false, "Número de Série MQTT não configurado" end
    return true
end

-- Definição do driver
local driver = driver_template.Driver("BambuLabMQTT_Fresh_v2", { -- Nome do driver atualizado
    lifecycle_handlers = {
        init = function(self, device)
            log.info(string.format("[%s] Driver: Handler 'init' chamado", device.label or device.id))
            device:set_field("healthState", "UNKNOWN", {visibility = {display = true, ui = true}})
            -- Guarda a configuração inicial para comparação em infoChanged
            device:set_field("current_config_checksum", utils.stringify_table(get_device_config(device)))
        end,
        added = function(self, device)
            log.info(string.format("[%s] Driver: Handler 'added' chamado", device.label or device.id))
            local config = get_device_config(device)
            local is_valid, err_msg = validate_config(config)

            if not is_valid then
                log.warn(string.format("[%s] Driver: Configuração inicial incompleta ou inválida: %s. Aguardando preferências.", device.label or device.id, err_msg))
                device:offline()
                return
            end
            
            device.mqtt_client = MqttHandler.new(device, config)
            device.mqtt_client:connect() -- A conexão deve lidar com o estado online/offline
            device:set_field("current_config_checksum", utils.stringify_table(config))
        end,
        infoChanged = function(self, device, event, ...)
            log.info(string.format("[%s] Driver: Handler 'infoChanged' chamado", device.label or device.id))
            local new_config = get_device_config(device)
            local old_config_checksum = device:get_field("current_config_checksum")
            local new_config_checksum = utils.stringify_table(new_config)

            if old_config_checksum == new_config_checksum then
                log.info(string.format("[%s] Driver: Configuração não alterada, ignorando.", device.label or device.id))
                return
            end
            log.info(string.format("[%s] Driver: Configuração alterada. Tentando reconectar...", device.label or device.id))

            if device.mqtt_client then
                device.mqtt_client:disconnect()
            end

            local is_valid, err_msg = validate_config(new_config)
            if not is_valid then
                log.warn(string.format("[%s] Driver: Configuração atualizada está incompleta ou inválida: %s.", device.label or device.id, err_msg))
                device:offline()
                return
            end

            device.mqtt_client = MqttHandler.new(device, new_config)
            device.mqtt_client:connect()
            device:set_field("current_config_checksum", new_config_checksum)
        end,
        removed = function(self, device)
            log.info(string.format("[%s] Driver: Handler 'removed' chamado", device.label or device.id))
            if device.mqtt_client then
                device.mqtt_client:disconnect()
            end
        end
        -- Outros handlers como 'doConfigure' podem ser adicionados se necessário
    },
    capability_handlers = {
        refresh = {
            REFRESH = function(self, device, cmd)
                log.info(string.format("[%s] Driver: Comando Refresh recebido", device.label or device.id))
                if device.mqtt_client and device.mqtt_client:is_connected() then
                    log.info(string.format("[%s] Driver: Solicitando atualização de estado da impressora via MQTT.", device.label or device.id))
                    device.mqtt_client:request_status_update() -- Implementar esta função no mqtt_handler
                else
                    log.warn(string.format("[%s] Driver: Não é possível atualizar, MQTT não conectado.", device.label or device.id))
                    device:offline()
                end
                device:emit_event(cmd.capability.REFRESHED({})) -- Confirma que o refresh foi processado
            end
        },
        switch = {
            ON = function(self, device, cmd)
                log.info(string.format("[%s] Driver: Comando Switch ON recebido", device.label or device.id))
                if device.mqtt_client and device.mqtt_client:is_connected() then
                    -- Lógica para enviar comando ON via MQTT (ex: iniciar impressão)
                    -- device.mqtt_client:publish_command("print/start", "{}")
                    log.info(string.format("[%s] Driver: (Simulado) Enviando comando ON via MQTT.", device.label or device.id))
                    device:emit_event(cmd.capability.switch.on())
                else
                    log.warn(string.format("[%s] Driver: MQTT não conectado, comando ON ignorado.", device.label or device.id))
                end
            end,
            OFF = function(self, device, cmd)
                log.info(string.format("[%s] Driver: Comando Switch OFF recebido", device.label or device.id))
                if device.mqtt_client and device.mqtt_client:is_connected() then
                    -- Lógica para enviar comando OFF via MQTT (ex: parar impressão)
                    -- device.mqtt_client:publish_command("print/stop", "{}")
                    log.info(string.format("[%s] Driver: (Simulado) Enviando comando OFF via MQTT.", device.label or device.id))
                    device:emit_event(cmd.capability.switch.off())
                else
                    log.warn(string.format("[%s] Driver: MQTT não conectado, comando OFF ignorado.", device.label or device.id))
                end
            end
        }
        -- Adicione handlers para outras capabilities aqui
    }
})

driver:run()
