local log = require "log"
-- CORREÇÃO: Importa a biblioteca de mDNS diretamente
local dns = require "st.socket.dns"
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

  -- Define a função de callback para quando um dispositivo é encontrado
  local function on_found(device_info)
    -- device_info contém os dados do dispositivo descoberto (ip, porta, nome, etc.)
    log.info(string.format("Dispositivo Bambu Lab encontrado: %s", device_info.name))
    log.pretty_print(device_info)

    -- O número de série é geralmente a primeira parte do nome do serviço
    -- Ex: "00M00A000000000._bambulab-tool._tcp.local"
    local serial_number = string.match(device_info.name, "^[^.]+")
    if not serial_number then
      log.error("Não foi possível extrair o número de série do nome do dispositivo: " .. device_info.name)
      return
    end
    log.info(string.format("Número de série extraído: %s", serial_number))

    -- Analisa o registro TXT para obter mais informações, como o modelo
    local txt_data = parse_txt_record(device_info.txt)
    local model = txt_data.dev_product or "Bambu Lab Printer" -- Usa o nome do produto se disponível

    -- Monta os metadados para criar o dispositivo no SmartThings
    local metadata = {
      type = "LAN",
      -- Este é o ponto CRÍTICO: usamos um ID único!
      device_network_id = serial_number,
      label = string.format("Bambu Lab %s", model),
      profile = "bambulab.v1",
      manufacturer = "Bambu Lab",
      model = model,
      -- Precisamos salvar o IP e a porta para o driver usar depois
      ip_address = device_info.ip,
      port = device_info.port
    }

    log.info(string.format("Tentando criar dispositivo para a impressora %s", serial_number))
    log.pretty_print(metadata)
    
    -- Tenta criar o dispositivo. Se já existir com esse ID, não faz nada.
    driver:try_create_device(metadata)
  end

  -- Define a função de callback para quando a busca terminar
  local function on_done()
    log.info("Descoberta de impressoras Bambu Lab finalizada.")
  end

  -- Inicia a busca mDNS pelo serviço da Bambu Lab
  dns.query_mdns("_bambulab-tool._tcp.local", on_found, on_done)
end

return discovery
