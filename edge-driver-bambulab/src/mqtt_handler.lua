local MqttHandler = {}
local log = require "log"
local mqtt = require "st.mqtt"

function MqttHandler.new(device, config)
  local self = {
    device = device,
    config = config,
    is_connected = false
  }

  setmetatable(self, {__index = MqttHandler})
  return self
end

function MqttHandler:connect()
  self.client = mqtt.Client({
    host = self.config.ip,
    port = self.config.port,
    tls = true,
    tls_insecure = not self.config.ca_cert,
    tls_ca_cert = self.config.ca_cert,
    username = self.config.username,
    password = self.config.password,
    client_id = "st-bambu-"..self.device.id:sub(-6)
  })

  self.client.on_message = function(_, topic, payload)
    log.debug("MQTT Message: "..topic)
    -- Implementar parser de mensagens
  end

  local ok, err = pcall(function()
    self.client:connect()
    self.is_connected = true
    return true
  end)

  if not ok then
    log.error("MQTT Connection failed: "..tostring(err))
    return false
  end
  return true
end

function MqttHandler:disconnect()
  if self.client then
    self.client:disconnect()
    self.is_connected = false
  end
end

function MqttHandler:publish(topic, payload)
  if self.is_connected then
    return self.client:publish(topic, payload, 0, 1)
  end
  return false
end

return MqttHandler