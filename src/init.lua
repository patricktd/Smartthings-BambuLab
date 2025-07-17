local log = require 'log'
local driver = require 'st.driver'

-- DOCS: Função chamada quando uma impressora é descoberta via SSDP.
local function device_discovered(self, ssdp_args)
  log.info("SSDP Discovery: Dispositivo encontrado! A processar...")

  local serial_number = ssdp_args.usn
  local device_label = ssdp_args['DevName.bambu.com'] or ("Bambu Lab " .. serial_number)
  local device_ip = ssdp_args.ip

  log.info(string.format("Impressora encontrada: %s (S/N: %s) no IP: %s", device_label, serial_number, device_ip))

  local device_metadata = {
    -- Usamos o nosso novo perfil detalhado.
    profile = "bambulab.discovered-printer.v1",
    device_network_id = serial_number,
    label = device_label,
    -- O 'parent_device_id' ajuda a associar a impressora ao nosso dispositivo de descoberta.
    parent_device_id = ssdp_args.driver_parent_device_id
  }

  local did_create, new_device = self:try_create_device(device_metadata)
  if did_create then
    log.info(string.format("Dispositivo da impressora criado com sucesso: %s", device_label))
    
    -- [[ LÓGICA DE CONEXÃO ]]
    -- Agora que o dispositivo foi criado, podemos usar o 'device_ip' para conectar.
    -- O 'device' pode guardar informação para uso futuro, se necessário.
    -- Exemplo: device.info.ip = device_ip
    
    log.info(string.format("Iniciando conexão MQTT para %s em %s:8883...", device_label, device_ip))
    -- (Aqui entraria o código real de conexão MQTT)

    -- Vamos emitir um estado inicial para dar feedback ao utilizador.
    new_device:emit_event(self.capabilities['patchprepare64330.printerStatus'].printerStatus("Online, Descoberto"))
    new_device:emit_event(self.capabilities['patchprepare64330.printerProgress'].progress(0))
    
  else
    log.warn(string.format("A criação do dispositivo falhou ou ele já existe: %s", device_label))
  end
end

-- DOCS: Função chamada quando um dispositivo já existente é redescoberto.
local function device_rediscovered(self, device, new_ip)
  log.info(string.format("Dispositivo redescoberto: %s. IP novo: %s", device.label, new_ip))
  device:set_device_network_address(new_ip)
  -- Podemos assumir que está online se foi redescoberto.
  device:emit_event(self.capabilities['patchprepare64330.printerStatus'].printerStatus("Online, Redescoberto"))
end


-- Definição principal do nosso driver
local bambu_driver = {
  -- É importante declarar as capacidades, especialmente as customizadas, que o driver suporta.
  supported_capabilities = {
    "patchprepare64330.printerStatus",
    "patchprepare64330.printerProgress",
    "refresh"
  },
  lifecycle_handlers = {
    discovery = {
      ["ssdp:urn:bambulab-com:device:3dprinter:1"] = {
        added = device_discovered,
        rediscovered = device_rediscovered
      }
    }
  },
  NAME = "Bambu Lab Discovery Driver"
}

driver:run(bambu_driver)