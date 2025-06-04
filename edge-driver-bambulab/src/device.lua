local device_handler = {}
local log = require "log"
local MqttHandler = require "mqtt_handler"
local capabilities = require "st.capabilities"
local cosock = require "cosock"
local socket = require "cosock.socket"

local MQTT_PORT = 8883
local DEFAULT_USERNAME = "bblp"

function device_handler.init(driver)
  log.info("Driver BambuLab inicializado")
end

function device_handler.device_init(driver, device)
  device:set_field("connection_attempts", 0, {persist=false})
  device:emit_event(capabilities.healthCheck.healthStatus.checking())
end

local function setup_mqtt(device)
  local config = {
    ip = device.preferences.printerIp,
    port = device.preferences.printerPort or MQTT_PORT,
    username = DEFAULT_USERNAME,
    password = device.preferences.mqttPassword,
    ca_cert = device.preferences.caCertificate ~= "" and device.preferences.caCertificate or nil
  }

  local mqtt_h = MqttHandler.new(device, config)
  device:set_field("mqtt_handler", mqtt_h, {persist=false})

  if mqtt_h:connect() then
    device:emit_event(capabilities.healthCheck.healthStatus.online())
  else
    device:emit_event(capabilities.healthCheck.healthStatus.offline())
    cosock.spawn(function()
      socket.sleep(30)
      if device:get_field("connection_attempts") < 3 then
        device:set_field("connection_attempts", device:get_field("connection_attempts") + 1)
        setup_mqtt(device)
      end
    end)
  end
end

function device_handler.device_added(driver, device)
  setup_mqtt(device)
end

function device_handler.info_changed(driver, device, event, args)
  if args.old_st_store.preferences.printerIp ~= device.preferences.printerIp or
     args.old_st_store.preferences.mqttPassword ~= device.preferences.mqttPassword then
    setup_mqtt(device)
  end
end

function device_handler.on_handler(driver, device, command)
  local mqtt_h = device:get_field("mqtt_handler")
  if mqtt_h then
    mqtt_h:publish("device/command", '{"command":"start"}')
  end
end

return device_handler