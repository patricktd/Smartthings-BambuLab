local driver_template = require "st.driver"
local MqttHandler = require "mqtt_handler" -- Seu módulo MQTT
local log = require "log"
local utils = require "st.utils" -- Para deep_compare

local function get_device_config(device)
    local prefs = device.preferences
    return {
        ipAddress = prefs.ipAddress,
        port = prefs.port,
        username = prefs.username,
        accessToken = prefs.accessToken,
        caCertificate = prefs.caCertificate,
        mqttSerial = prefs.mqttSerial,
        mqttClientId = prefs.mqttClientId or device.id
    }
end

local function validate_config(config)
    if not config.ipAddress or config.ipAddress == "" then return false, "IP não configurado" end
    if not config.accessToken or config.accessToken == "" then return false, "Access Token não configurado" end
    if not config.caCertificate or not config.caCertificate:find("BEGIN CERTIFICATE") then return false, "Certificado CA inválido ou não configurado" end
    if not config.mqttSerial or config.mqttSerial == "" then return false, "Número de Série MQTT não configurado" end
    return true
end

local driver = driver_template.Driver("BambuLabPrinterDriver_v2", { -- Nome do driver atualizado
    lifecycle_handlers = {
        init = function(self, device)
            log.info(string.format("[%s] Handler 'init' chamado", device.label or device.id))
            device:set_field("healthState", "UNKNOWN", {visibility = {display = true, ui = true}})
            -- Guardar a configuração inicial para comparação em infoChanged
            device:set_field("current_config_checksum", utils.stringify_table(get_device_config(device)))
        end,
        added = function(self, device)
            log.info(string.format("[%s] Handler 'added' chamado", device.label or device.id))
            local config = get_device_config(device)
            local is_valid, err_msg = validate_config(config)

            if not is_valid then
                log.warn(string.format("[%s] Configuração inicial incompleta ou inválida: %s. Aguardando preferências.", device.label or device.id, err_msg))
                device:offline()
                device:set_field("healthState", "OFFLINE", {visibility = {display = true, ui = true}})
                return
            end

            device.mqtt_client = MqttHandler.new(device, config)
            local connected = device.mqtt_client:connect()
            if connected then
                device:set_field("healthState", "ONLINE", {visibility = {display = true, ui = true}})
            else
                device:set_field("healthState", "OFFLINE", {visibility = {display = true, ui = true}})
            end
            device:set_field("current_config_checksum", utils.stringify_table(config))
        end,
        infoChanged = function(self, device, event, ...)
            log.info(string.format("[%s] Handler 'infoChanged' chamado", device.label or device.id))
            local new_config = get_device_config(device)
            local old_config_checksum = device:get_field("current_config_checksum")
            local new_config_checksum = utils.stringify_table(new_config)

            if old_config_checksum == new_config_checksum then
                log.info(string.format("[%s] Configuração não alterada, ignorando.", device.label or device.id))
                return
            end
            log.info(string.format("[%s] Configuração alterada. Reconectando...", device.label or device.id))

            if device.mqtt_client then
                device.mqtt_client:disconnect()
            end

            local is_valid, err_msg = validate_config(new_config)
            if not is_valid then
                log.warn(string.format("[%s] Configuração atualizada está incompleta ou inválida: %s.", device.label or device.id, err_msg))
                device:offline()
                device:set_field("healthState", "OFFLINE", {visibility = {display = true, ui = true}})
                return
            end

            device.mqtt_client = MqttHandler.new(device, new_config)
            local connected = device.mqtt_client:connect()
            if connected then
                 device:set_field("healthState", "ONLINE", {visibility = {display = true, ui = true}})
            else
                device:set_field("healthState", "OFFLINE", {visibility = {display = true, ui = true}})
            end
            device:set_field("current_config_checksum", new_config_checksum)
        end,
        removed = function(self, device)
            log.info(string.format("[%s] Handler 'removed' chamado", device.label or device.id))
            if device.mqtt_client then
                device.mqtt_client:disconnect()
            end
        end
    },
    capability_handlers = {
        refresh = {
            REFRESH = function(self, device, cmd)
                log.info(string.format("[%s] Comando Refresh recebido", device.label or device.id))
                if device.mqtt_client and device.mqtt_client.connected then
                    log.info(string.format("[%s] Solicitando atualização de status da impressora.", device.label or device.id))
                    -- Ex: device.mqtt_client:publish_message("request/status", "{}", false)
                else
                    log.warn(string.format("[%s] Não é possível atualizar, MQTT não conectado.", device.label or device.id))
                    device:offline()
                    device:set_field("healthState", "OFFLINE", {visibility = {display = true, ui = true}})
                end
                device:emit_event(cmd.capability.REFRESHED({})) -- Confirma que o refresh foi processado
            end
        }
        -- Adicione handlers para os comandos das suas outras capabilities
    }
})

driver:run()
