local cosock = require "cosock"
local log = require "log"

local discovery = {}

function discovery.handle_discovery(driver, _should_continue)
  log.info("Iniciando descoberta SSDP para Bambu Lab...")

  local udp = cosock.socket.udp()
  if not udp then
    log.error("Falha ao criar socket UDP para descoberta.")
    return
  end

  udp:setsockname("*", 0)
  udp:setoption("reuseaddr", true)
  udp:settimeout(5) -- Aumentado para 5 segundos para dar mais tempo para respostas

  -- Payload M-SEARCH para o serviço específico da Bambu Lab
  local payload = table.concat({
    "M-SEARCH * HTTP/1.1",
    "HOST: 239.255.255.250:1900",
    "MAN: \"ssdp:discover\"",
    "MX: 2",
    "ST: urn:bambulab-com:device:3dprinter:1",
    "",
    ""
  }, "\r\n")

  -- Envia o pacote de descoberta multicast
  local ok, err = udp:sendto(payload, "239.255.255.250", 1900)
  if not ok then
    log.error("Falha ao enviar pacote M-SEARCH: " .. (err or "desconhecido"))
    udp:close()
    return
  end
  log.info("Pacote M-SEARCH enviado. Aguardando respostas...")

  -- Loop para receber múltiplas respostas
  local start_time = os.time()
  while os.difftime(os.time(), start_time) < 5 do
    local data, ip, port = udp:receivefrom()
    if data then
      log.info(string.format("Resposta SSDP recebida de %s:%d", ip, port))
      log.debug(data)

      -- Parseia os cabeçalhos da resposta
      local headers = {}
      for line in data:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w%-%.]+):%s*(.+)")
        if k and v then
          headers[string.upper(k)] = v -- Usa caixa alta para consistência
        end
      end

      -- Extração CORRIGIDA dos metadados
      -- CORREÇÃO 1: Extrai o IP da URL do LOCATION
      local ip_addr = ip -- Usa o IP de origem como padrão
      if headers.LOCATION then
        -- Tenta extrair o IP de uma URL como http://192.168.1.55/description.xml
        ip_addr = headers.LOCATION:match("https?://([%d%.]+)") or ip
      end

      -- CORREÇÃO 2: Extrai um ID único e limpo do USN
      -- Ex: "uuid:00S00A2C3005221::urn:bambulab-com:device:3dprinter:1" -> extrai "00S00A2C3005221"
      local serial = headers.USN or tostring(os.time()) .. ip_addr -- Fallback para ID único
      if headers.USN and headers.USN:match("uuid:([^:]+)") then
          serial = headers.USN:match("uuid:([^:]+)")
      end

      local model = headers["DEVNAME.BAMBU.COM"] or "Bambu Lab Printer"

      local metadata = {
        type = "LAN",
        device_network_id = serial, -- Agora usa um serial limpo
        label = "Bambu Lab " .. model,
        profile = "bambulab.v1",
        manufacturer = "Bambu Lab",
        model = model,
        ip_address = ip_addr, -- Agora usa o IP limpo
        port = 80 -- A porta pode ser diferente, mas 80 é um bom padrão para HTTP
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
