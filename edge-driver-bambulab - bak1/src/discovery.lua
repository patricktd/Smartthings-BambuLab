local Discovery = {}
local mqtt = require "st.mqtt"
local log = require "log"
local cosock = require "cosock"
local socket = require "cosock.socket"
local st_utils = require "st.utils"

local MQTT_PORT = 8883
local MQTT_TOPIC = "device/+/report"
local DEFAULT_USERNAME = "bblp"
local DISCOVERY_TIMEOUT = 7

function Discovery.discover_devices(driver, opts, cons)
  log.info("Iniciando descoberta BambuLab...")
  local network_ips = driver:get_network_ips() or {}
  local found_devices = {}

  for _, ip in ipairs(network_ips) do
    cosock.spawn(function()
      local client = mqtt.Client({
        host = ip,
        port = MQTT_PORT,
        tls = true,
        tls_insecure = not opts.use_ca_cert,
        username = DEFAULT_USERNAME,
        password = opts.default_access_code or "",
        client_id = "st-disc-"..st_utils.random_string(6)
      })

      client.on_message = function(_, topic, payload)
        if topic:match(MQTT_TOPIC) then
          table.insert(found_devices, {
            type = "EDGE_CHILD",
            label = "BambuLab Printer",
            profile = "bambulab",
            parent_assigned_child_key = ip,
            vendor_provided_label = "BambuLab_"..ip:gsub("%.", "_"),
            properties = {
              ip = ip,
              requires_access_code = true
            }
          })
          client:disconnect()
        end
      end

      local success, err = pcall(function()
        client:connect()
        client:subscribe(MQTT_TOPIC, 0)
        socket.sleep(DISCOVERY_TIMEOUT)
        client:disconnect()
      end)

      if not success then
        log.debug("Falha na descoberta: "..tostring(err))
      end
    end)
  end

  socket.sleep(DISCOVERY_TIMEOUT + 1)
  for _, dev in ipairs(found_devices) do cons.device_added(dev) end
  return found_devices
end

return Discovery