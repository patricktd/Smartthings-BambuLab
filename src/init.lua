local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local BambuDevice = require "bambu_device" -- O modulo que voce ja criou
local config = require "config"

-- Tabela para gerenciar dispositivos ativos
local active_devices = {}

-----------------------------------------------------------------------
-- LIFECYCLE HANDLERS
-----------------------------------------------------------------------

local function device_init(driver, device)
  print(string.format("DISPOSITIVO INICIADO: %s [ID: %s]", device.label, device.id))
end

local function device_added(driver, device)
  local ip = device.preferences.printerIp
  local access_code = device.preferences.accessCode
  local serial = device.preferences.serialNumber

  if not (ip and access_code and serial) then
    print("AVISO: Credenciais incompletas nas configuracoes do dispositivo.")
    return
  end

  print("CRIANDO CONEXAO PARA: " .. serial)
  
  -- Instancia a conexao usando seu modulo novo
  -- OBS: Ajuste aqui se o seu bambu_device usar .new() ou outra sintaxe
  local client = BambuDevice.new(device, ip, access_code, serial)
  
  active_devices[device.id] = client
  
  -- Inicia a conexao
  client:connect()
end

local function device_removed(driver, device)
  local client = active_devices[device.id]
  if client then
    print("REMOVENDO DISPOSITIVO: " .. device.label)
    client:disconnect()
    active_devices[device.id] = nil
  end
end

local function device_info_changed(driver, device, event, args)
  print("CONFIGURACOES ALTERADAS: " .. device.label)
  -- Desconecta o cliente antigo se existir
  if active_devices[device.id] then
    active_devices[device.id]:disconnect()
    active_devices[device.id] = nil
  end
  
  -- Recria a conexão com os novos dados
  device_added(driver, device)
end

local function device_doconfigure(driver, device)
  -- Apenas garante que estamos conectados
  if not active_devices[device.id] then
    device_added(driver, device)
  end
end

local function handle_switch(driver, device, command)
  local client = active_devices[device.id]
  if client then
    client:handle_switch(command)
  end
end

-----------------------------------------------------------------------
-- DRIVER DEFINITION
-----------------------------------------------------------------------

local bambu_driver = Driver("bambu-lab-driver", {
  capability_handlers = {
    [capabilities["schoolheart47510.bambuLightV2"].ID] = {
      ["on"] = handle_switch,
      ["off"] = handle_switch,
      ["setLight"] = handle_switch,
      ["toggle"] = handle_switch,
    }
  },
  discovery = function(driver, opts, cons)
    print(">>> DISCOVERY: Criando dispositivo Bambu Lab...")
    
    local metadata = {
      type = "LAN",
      -- ID único baseado no tempo para evitar conflitos em testes
      device_network_id = "bambu_printer_" .. tostring(os.time()),
      label = "Bambu Lab Printer",
      profile = "BambuPrinter", -- Verificado no config.yaml
      manufacturer = "Bambu Lab",
      model = "Generic",
      vendor_provided_label = "BambuLab Printer"
    }
    
    driver:try_create_device(metadata)
  end,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    removed = device_removed,
    deleted = device_removed,
    infoChanged = device_info_changed,
    doConfigure = device_doconfigure
  }
})

bambu_driver:run()