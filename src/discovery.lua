local cosock = require "cosock"
local log = require "log"

local discovery = {}

function discovery.handle_discovery(driver, _should_continue)
  log.info("Iniciando descoberta SSDP para Bambu Lab (v2)...")

  local udp = cosock.socket.udp()
  if not udp then
    log.error("Falha ao criar socket UDP para descoberta.")
    return
  end

  udp:setsockname("*", 0)
  udp:setoption("reuseaddr", true)
  udp:settimeout(5)

  -- =================================================================
  --  NOVA LINHA ADICIONADA AQUI
  -- =================================================================
  -- Inscreve o socket no grupo multicast SSDP. Isso é crucial em algumas redes
  -- para garantir que as respostas multicast sejam recebidas.
  udp:setoption("ip-add-membership", { multi = "239.255.255.250", interface = "0.0.0.0" })
  log.info("Socket inscrito no grupo multicast SSDP.")
  -- =================================================================

  local payload = table.concat({
    "M-SEARCH * HTTP/1.1",
    "HOST: 239.255.255.250:1900",
    "MAN: \"ssdp:discover\"",
    "MX: 2",
    "ST: urn:bambulab-com:device:3dprinter:1",
    "",
    ""
  }, "\r\n")

  local ok, err = udp:sendto(payload, "239.255.255.250", 1900)
  if not ok then
    log.error("Falha ao enviar pacote M-SEARCH: " .. (err or "desconhecido"))
    udp:close()
    return
  end
  log.info("Pacote M-SEARCH enviado. Aguardando respostas...")

  local start_time = os.time()
  while os.difftime(os.time(), start_time) < 5 do
    local data, ip, port = udp:receivefrom()
    if data then
      log.info(string.format("Resposta SSDP recebida de %s:%d", ip, port))
      -- (O resto do código de parse continua o mesmo)
      local headers = {}
      for line in data:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w%-%.]+):%s*(.+)")
        if k and v then
          headers[string.upper(k)] = v
        end
      end

      local ip_addr = ip
      if headers.LOCATION then
        ip_addr = headers.LOCATION:match("https?://([%d%.]+)") or ip
      end

      local serial = headers.USN or tostring(os.time()) .. ip_addr
      if headers.USN and headers.USN:match("uuid:([^:]+)") then
          serial = headers.USN:match("uuid:([^:]+)")
      end

      local model = headers["DEVNAME.BAMBU.COM"] or "Bambu Lab Printer"

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

      log.info("Metadados extraídos para o dispositivo:")
      log.pretty_print(metadata)
      driver:try_create_device(metadata)
    end
  end

  udp:close()
  log.info("Descoberta SSDP finalizada.")
end

return discovery
