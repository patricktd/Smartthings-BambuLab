local cosock = require "cosock"
local log = require "log"

local discovery = {}

function discovery.handle_discovery(driver, _should_continue)
  log.info("Iniciando descoberta SSDP Bambu Lab...")

  local udp = cosock.socket.udp()
  udp:setsockname("*", 0)
  udp:setoption("reuseaddr", true)
  udp:settimeout(3)

  -- Payload M-SEARCH
  local payload = table.concat({
    "M-SEARCH * HTTP/1.1",
    "HOST:239.255.255.250:1900",
    "MAN:\"ssdp:discover\"",
    "MX:1",
    "ST:urn:bambulab-com:device:3dprinter:1",
    "",
    ""
  }, "\r\n")

  -- Envia multicast
  udp:sendto(payload, "239.255.255.250", 1900)

  -- Recebe respostas
  local start_time = os.time()
  while os.difftime(os.time(), start_time) < 3 do
    local data, ip, port = udp:receivefrom()
    if data then
      log.info(string.format("Resposta SSDP de %s:%d", ip, port))
      log.debug(data)

      -- Parseia cabeçalhos
      local headers = {}
      for line in data:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w%-%.]+):%s*(.+)")
        if k and v then
          headers[k] = v
        end
      end

      -- Monta metadata
      local serial = headers["USN"] or "unknown"
      local model = headers["DevName.bambu.com"] or "Bambu Lab"
      local ip_addr = headers["LOCATION"] or ip

      local metadata = {
        type = "LAN",
        device_network_id = serial,
        label = "Bambu Lab " .. model,
        profile = "bambulab.v1",
        manufacturer = "Bambu Lab",
        model = model,
        ip_address = ip_addr,
        port = 80
      }

      log.pretty_print(metadata)
      driver:try_create_device(metadata)
    end
  end

  log.info("Descoberta SSDP finalizada.")
end

return discovery
