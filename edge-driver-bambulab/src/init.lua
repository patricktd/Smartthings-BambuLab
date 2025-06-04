-- src/init.lua

local driver_template = require "st.driver"
local log = require "log"
local MqttHandler = require "mqtt_handler"
local utils = require "st.utils"

local function get_device_config(device)
    local prefs = device.preferences
    return {
        ipAddress = prefs.ipAddress or "",
        port = prefs.port or 8883,
        username = prefs.username or "bblp",
        accessToken = prefs.accessToken or "",
        caCertificate = prefs.caCertificate or "",
        mqttSerial = prefs.mqttSerial or "",
        mqttClientId = prefs.mqttClientId or device.id
    }
end

local function validate_config(config)
    if not config.ipAddress or config.ipAddress == "" then return false, "Endereço IP não configurado" end
    if not config.accessToken or config.accessToken == "" then return false, "Access Token não configurado" end
    if not config.caCertificate or not config.caCertificate:find("BEGIN CERTIFICATE") then return false, "Certificado CA inválido ou não configurado" end
    if not config.mqttSerial or config.mqttSerial == "" then return false, "Número de Série MQTT não configurado" end
    return true
end

local driver = driver_template.Driver("BambuLabMQTT_Driver_v3", {
    lifecycle_handlers = {
        init = function(self, device)
            log.info(string.format("[%s] Driver: Handler 'init' chamado", device.label or device.id))
            device:set_field("healthState", "UNKNOWN", {visibility = {display = true, ui = true}})
            device:set_field("current_config_checksum", utils.stringify_table(get_device_config(device)))
        end,
        added = function(self, device)
            log.info(string.format("[%s] Driver: Handler 'added' chamado", device.label or device.id))
            local config = get_device_config(device)
            local is_valid, err_msg = validate_config(config)

            if not is_valid then
                log.warn(string.format("[%s] Driver: Configuração inicial incompleta: %s.", device.label or device.id, err_msg))
                device:offline()
                return
            end
            
            device.mqtt_client = MqttHandler.new(device, config)
            device.mqtt_client:connect()
            device:set_field("current_config_checksum", utils.stringify_table(config))
        end,
        infoChanged = function(self, device, event, ...)
            log.info(string.format("[%s] Driver: Handler 'infoChanged' chamado", device.label or device.id))
            local new_config = get_device_config(device)
            local old_config_checksum = device:get_field("current_config_checksum")
            local new_config_checksum = utils.stringify_table(new_config)

            if old_config_checksum == new_config_checksum then
                log.info(string.format("[%s] Driver: Configuração não alterada.", device.label or device.id))
                return
            end
            log.info(string.format("[%s] Driver: Configuração alterada. Reconectando...", device.label or device.id))

            if device.mqtt_client then
                device.mqtt_client:disconnect()
            end

            local is_valid, err_msg = validate_config(new_config)
            if not is_valid then
                log.warn(string.format("[%s] Driver: Configuração atualizada incompleta: %s.", device.label or device.id, err_msg))
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
    },
    capability_handlers = {
        refresh = {
            REFRESH = function(self, device, cmd)
                log.info(string.format("[%s] Driver: Comando Refresh recebido", device.label or device.id))
                if device.mqtt_client and device.mqtt_client:is_connected() then
                    device.mqtt_client:request_status_update()
                else
                    log.warn(string.format("[%s] Driver: MQTT não conectado, refresh ignorado.", device.label or device.id))
                    device:offline()
                end
                device:emit_event(cmd.capability.REFRESHED({}))
            end
        },
        switch = {
            ON = function(self, device, cmd)
                log.info(string.format("[%s] Driver: Comando Switch ON recebido", device.label or device.id))
                if device.mqtt_client and device.mqtt_client:is_connected() then
                    log.info(string.format("[%s] Driver: (Simulado) Enviando comando ON via MQTT.", device.label or device.id))
                    -- device.mqtt_client:publish("comando_para_ligar", "payload")
                    device:emit_event(cmd.capability.switch.on())
                else
                    log.warn(string.format("[%s] Driver: MQTT não conectado, comando ON ignorado.", device.label or device.id))
                end
            end,
            OFF = function(self, device, cmd)
                log.info(string.format("[%s] Driver: Comando Switch OFF recebido", device.label or device.id))
                if device.mqtt_client and device.mqtt_client:is_connected() then
                    log.info(string.format("[%s] Driver: (Simulado) Enviando comando OFF via MQTT.", device.label or device.id))
                    -- device.mqtt_client:publish("comando_para_desligar", "payload")
                    device:emit_event(cmd.capability.switch.off())
                else
                    log.warn(string.format("[%s] Driver: MQTT não conectado, comando OFF ignorado.", device.label or device.id))
                end
            end
        },
        -- Handler para o comando da capability personalizada (se houver)
        ["bambuPrinterJobStatus.v1"] = {
            setJobPhase = function(self, device, cmd)
                local phase_to_set = cmd.args.phase
                log.info(string.format("[%s] Comando setJobPhase recebido: %s", device.label or device.id, phase_to_set))
                if device.mqtt_client and device.mqtt_client:is_connected() then
                    -- Lógica para enviar comando MQTT para alterar a fase da impressora
                    -- device.mqtt_client:publish("printer/set_phase_command", '{ "target_phase": "' .. phase_to_set .. '" }')
                    log.info(string.format("[%s] (Simulado) Enviando comando setJobPhase via MQTT: %s", device.label or device.id, phase_to_set))
                    -- Opcionalmente, atualizar o atributo localmente de forma otimista ou esperar confirmação
                    -- device:emit_event(device.profile.capabilities["bambuPrinterJobStatus.v1"].jobPhase(phase_to_set))
                else
                    log.warn(string.format("[%s] MQTT não conectado, comando setJobPhase ignorado.", device.label or device.id))
                end
            end
        }
    }
})

driver:run()