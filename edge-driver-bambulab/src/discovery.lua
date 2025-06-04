local Discovery = {}
local mqtt = require "st.mqtt"
local log = require "log"
local st_utils = require "st.utils"
local cosock = require "cosock"
local socket = require "cosock.socket"

-- Configurações MQTT padrão da BambuLab
local MQTT_PORT = 8883
local MQTT_TOPIC = "device/+/report"
local DEFAULT_USERNAME = "bblp"

function Discovery.discover_devices(driver, opts, cons)
  log.info("Iniciando descoberta de impressoras BambuLab...")
  
  -- Obter preferências padrão do driver
  local discovery_timeout = opts.discovery_timeout or 5
  local default_access_code = opts.default_access_code or ""
  local use_ca_cert = opts.use_ca_cert or false
  local ca_cert_data = opts.ca_cert_data or ""

  -- Varredura de rede melhorada
  local network_ips = driver:get_network_ips() or {}
  local found_devices = {}

  for _, ip in ipairs(network_ips) do
    cosock.spawn(function()
      local client_id = "st-disc-"..st_utils.random_string(6)
      local client = mqtt.Client({
        host = ip,
        port = MQTT_PORT,
        tls = true,
        tls_insecure = not use_ca_cert,  -- Ignorar verificação cert se não fornecido
        tls_ca_cert = use_ca_cert and ca_cert_data or nil,
        username = DEFAULT_USERNAME,
        password = default_access_code,
        client_id = client_id,
        keepalive = 60,
        clean_session = true
      })

      -- Configurar callbacks
      client.on_connect = function()
        log.debug(string.format("Conectado ao broker em %s", ip))
        client:subscribe(MQTT_TOPIC, 0)
      end

      client.on_message = function(_, topic, payload)
        if topic:match(MQTT_TOPIC) then
          log.info(string.format("Dispositivo BambuLab detectado em %s", ip))
          table.insert(found_devices, {
            type = "EDGE_CHILD",
            label = "BambuLab Printer",
            profile = "bambulab",
            parent_assigned_child_key = ip,
            vendor_provided_label = "BambuLab_"..ip:gsub("%.", "_"),
            properties = {
              ip = ip,
              requires_access_code = true  -- Flag para solicitar access code
            }
          })
          client:disconnect()
        end
      end

      client.on_error = function(err)
        log.warn(string.format("Erro MQTT em %s: %s", ip, err))
      end

      -- Tentar conexão com timeout
      local ok, err = pcall(function()
        client:connect()
        socket.sleep(discovery_timeout)
        if client.connected then
          client:disconnect()
        end
      end)

      if not ok then
        log.debug(string.format("Conexão falhou em %s: %s", ip, err))
      end
    end, "mqtt_discovery_"..ip)
  end

  -- Esperar pela conclusão das tarefas
  socket.sleep(discovery_timeout + 1)  -- Buffer adicional

  -- Processar dispositivos encontrados
  for _, dev in ipairs(found_devices) do
    cons.device_added(dev)
  end

  return found_devices
end

return Discovery