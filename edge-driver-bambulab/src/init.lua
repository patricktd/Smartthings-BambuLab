local driver_template = require "st.driver"
local MqttHandler = require "mqtt_handler" -- Seu módulo MQTT
local log = require "log"

local function get_device_config(device)
    return {
        ipAddress = device.preferences.ipAddress,
        port = device.preferences.port,
        username = device.preferences.username,
        accessToken = device.preferences.accessToken,
        caCertificate = device.preferences.caCertificate,
        mqttClientId = device.preferences.mqttClientId or device.id
    }
end

local driver = driver_template.Driver("BambuLabPrinterDriver", {
    lifecycle_handlers = {
        init = function(self, device)
            log.info("Handler 'init' chamado para o dispositivo: " .. device.id)
            device:set_field("healthState", "UNKNOWN", {visibility = {display = true, ui = true}})
            -- Não tente conectar aqui, pois as preferências podem não estar prontas.
        end,
        added = function(self, device)
            log.info("Handler 'added' chamado para o dispositivo: " .. device.id)
            -- As preferências devem estar disponíveis aqui após o usuário configurar.
            local config = get_device_config(device)
            if not config.ipAddress or config.ipAddress == "" or 
               not config.accessToken or config.accessToken == "" or
               not config.caCertificate or config.caCertificate == "" then
                log.warn("Configuração inicial incompleta. Aguardando preferências.")
                device:offline() -- Ou um estado de "configuração necessária"
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
        end,
        infoChanged = function(self, device, event, ...)
            log.info("Handler 'infoChanged' chamado para o dispositivo: " .. device.id)
            local new_config = get_device_config(device)

            -- Desconectar cliente MQTT existente se houver
            if device.mqtt_client then
                device.mqtt_client:disconnect()
            end

            if not new_config.ipAddress or new_config.ipAddress == "" or 
               not new_config.accessToken or new_config.accessToken == "" or
               not new_config.caCertificate or new_config.caCertificate == "" then
                log.warn("Configuração atualizada está incompleta.")
                device:offline()
                device:set_field("healthState", "OFFLINE", {visibility = {display = true, ui = true}})
                return
            end

            -- Criar e conectar com nova configuração
            device.mqtt_client = MqttHandler.new(device, new_config)
            local connected = device.mqtt_client:connect()
            if connected then
                 device:set_field("healthState", "ONLINE", {visibility = {display = true, ui = true}})
            else
                device:set_field("healthState", "OFFLINE", {visibility = {display = true, ui = true}})
            end
        end,
        removed = function(self, device)
            log.info("Handler 'removed' chamado para o dispositivo: " .. device.id)
            if device.mqtt_client then
                device.mqtt_client:disconnect()
            end
        end
        -- Outros handlers como 'doConfigure', 'driverSwitched' se necessário
    },
    capability_handlers = {
        -- Adicione handlers para os comandos das suas capabilities
        -- Ex: refresh, switch on/off
        refresh = {
            REFRESH = function(self, device, cmd)
                log.info("Comando Refresh recebido para " .. device.id)
                if device.mqtt_client and device.mqtt_client.connected then
                    -- Lógica para solicitar atualização de status via MQTT
                    -- Ex: device.mqtt_client:publish("bambu_lab/request/status", "")
                    log.info("Solicitando atualização de status da impressora.")
                else
                    log.warn("Não é possível atualizar, MQTT não conectado.")
                    device:offline()
                     device:set_field("healthState", "OFFLINE", {visibility = {display = true, ui = true}})
                end
            end
        }
    }
})

driver:run()
