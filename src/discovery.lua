local log = require "log"
local mdns = require "st.mdns"

local discovery = {}

--- Tenta analisar o registro TXT de uma resposta mDNS.
-- O registro TXT da Bambu Lab é uma string como "dev_name=Bambu Lab X1 Carbon;dev_ip=192.168.1.100;..."
-- @param txt_record A string do registro TXT.
-- @return Uma tabela com os pares chave-valor.
local function parse_txt_record(txt_record)
  local result = {}
  if txt_record == nil then
    return result
  end

  for part in string.gmatch(txt_record, "([^;]+)") do
    local key, value = string.match(part, "([^=]+)=(.*)")
    if key and value then
      result[key] = value
    end
  end
  return result
end

function discovery.handle_discovery(driver, _should_continue)
  log.info("Iniciando descoberta de impressoras Bambu Lab via mDNS...")

  -- Função chamada sempre que um dispositivo é encontrado
  local function on_found(device_info)
    log.info(string.format("Dispositivo Bambu Lab encontrado: %s", device_info.name))
    log.pretty_print(device_info)

    -- O número de série é geralmente a primeira parte do nome
    local serial_number = string.match(device_info.name, "^[^.]+")
    if not serial_number then
      log.error("Não foi possível extrair o número de série do nome do dispositivo: " .. device_info.name)
      return
    end
    log.info(string.format("Número de série extraído: %s", serial_number))

    -- Analisa o registro TXT para obter mais informações
    local txt_data = parse_txt_record(device_info.txt)
    local model = txt_data.dev_product or "Bambu Lab Printer"

    -- Monta os metadados
    local metadata = {
      type = "LAN",
      device_network_id = serial_number,
      label = string.format("Bambu Lab %s", model),
      profile = "bambulab.v1",
      manufacturer = "Bambu Lab",
      model = model,
      ip_address = device_info.ip,
      port = device_info.port
    }

    log.info(string.format("Tentando criar dispositivo para a impressora %s", serial_number))
    log.pretty_print(metadata)

    driver:try_create_device(metadata)
  end

  -- Função chamada ao término da descoberta
  local function on_done()
    log.info("Descoberta de impressoras Bambu Lab finalizada.")
  end

  -- Inicia descoberta mDNS com o módulo correto
  mdns.discover("_bambulab-tool._tcp.local", on_found, on_done)
end

return discovery
