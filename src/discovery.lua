local cosock = require "cosock"
local json = require "dkjson"
local log = require "log"

local discovery = {}

function discovery.handle_discovery(driver, _should_continue)
  log.info("Iniciando descoberta LAN por UDP broadcast (whois)...")

  local udp = cosock.socket.udp()
  udp:setsockname("0.0.0.0", 0)
  udp:setoption("broadcast", true)
  udp:settimeout(2)

  -- Payload de descoberta
  local payload = "whois"

  -- Envia broadcast
  udp:sendto(payload, "255.255.255.255", 19099)

  -- Escuta respostas
  local start_time = os.time()
  while os.difftime(os.time(), start_time) < 2 do
    local data, ip, port = udp:receivefrom()
    if data then
      log.info(string.format("Resposta UDP de %s:%d", ip, port))
      log.debug("Payload bruto: " .. data)

      -- Tenta parsear JSON
      local info, pos, err = json.decode(data, 1, nil)
      if info then
        log.pretty_print(info)

        -- Extrai informações
        local serial = info.serial or "unknown"
        local product = info.product or "Bambu Lab"
        local fw = info.fw_ver or "unknown"
        local ip_addr = info.network and info.network.ip or ip
        local mac = info.network and info.network.mac or "unknown"

        -- Cria metadata do device
        local metadata = {
          type = "LAN",
          device_network_id = serial,
          label = string.format("Bambu Lab %s (%s)", product, serial),
          profile = "bambulab.v1",
          manufacturer = "Bambu Lab",
          model = product,
          vendor_provided_label = product,
          ip_address = ip_addr,
          port = 80
        }

        log.info("Criando device...")
        driver:try_create_device(metadata)
      else
        log.warn("Falha ao decodificar JSON: " .. (err or ""))
      end
    end
  end

  log.info("Descoberta UDP finalizada.")
end

return discovery
