local log = require 'log'
local driver = require 'st.driver'
local discovery = require 'st.discovery'
local capabilities = require 'st.capabilities'

-- [[ DOCS ]]
-- Esta função é chamada automaticamente pelo Hub quando um dispositivo 
-- que corresponde ao nosso termo SSDP é encontrado.
-- @param self O nosso objeto do driver.
-- @param ssdp_args Uma tabela com toda a informação do anúncio SSDP da impressora.
local function device_discovered(self, ssdp_args)
  log.info("SSDP Discovery: Dispositivo encontrado! A processar...")

  -- [[ MUDANÇA #1 ]]
  -- O USN já é o número de série. Não precisamos de extrair nada.
  local serial_number = ssdp_args.usn
  if not serial_number then
    log.error("Pacote de descoberta recebido sem um USN (número de série). A ignorar.")
    return
  end
  
  -- [[ MUDANÇA #2 ]]
  -- Vamos usar o nome amigável que a impressora nos fornece!
  -- As chaves com pontos são acedidas com ['...'].
  local device_label = ssdp_args['DevName.bambu.com'] or ("Bambu Lab " .. serial_number)

  log.info(string.format("Impressora encontrada: %s (S/N: %s) no IP: %s", device_label, serial_number, ssdp_args.ip))

  local device_metadata = {
    profile = "bambulab-printer.v1",
    device_network_id = serial_number,
    label = device_label,
    vendor_provided_label = "Bambu Lab Discovery"
  }

  -- Tentamos criar o dispositivo. Se já existir, não fará nada.
  local did_create, new_device = driver:try_create_device(device_metadata)
  if did_create then
    log.info(string.format("Dispositivo da impressora criado com sucesso: %s", device_label))
    -- Assim que é criado, podemos definir o seu estado para "ligado" para indicar que está online.
    new_device:emit_event(capabilities.switch.on())
  else
    log.warn(string.format("A criação do dispositivo falhou ou ele já existe: %s", device_label))
  end
end


-- [[ DOCS ]]
-- Esta função é chamada quando um dispositivo já existente é "redescoberto",
-- o que é útil para atualizar o seu endereço IP se ele mudar.
local function device_rediscovered(self, device, new_ip)
  log.info(string.format("Dispositivo redescoberto: %s. IP antigo: %s, IP novo: %s", device.label, device.device_network_address, new_ip))
  -- Atualiza o endereço de rede do dispositivo.
  device:set_device_network_address(new_ip)
  -- Indica que o dispositivo está online.
  device:emit_event(capabilities.switch.on())
end


local bambu_driver = {
  device_profiles = {
    ["bambulab-printer.v1"] = {},
    ["bambulab.discovery.v1"] = {}
  },
  lifecycle_handlers = {
    discovery = {
      ["ssdp:urn:bambulab-com:device:3dprinter:1"] = {
        added = device_discovered,
        rediscovered = device_rediscovered
      }
    }
  },
  NAME = "Bambu Lab Driver with Discovery"
}

driver:run(bambu_driver)