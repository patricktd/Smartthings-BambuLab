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
  print(string.format("DISPOSITIVO INICIADO: %s [ID: %s] (v1.1.1)", device.label, device.id))
  
  -- DEBUG: Print all capabilities in main component to verify profile loading
  if device.profile and device.profile.components and device.profile.components.main then
      log.info("DEBUG: Capabilities in MAIN component:")
      for id, cap in pairs(device.profile.components.main.capabilities) do
          log.info(" - " .. tostring(id) .. " (ID: " .. tostring(cap.id) .. ")")
      end
  else
      log.warn("DEBUG: Could not access main component capabilities")
  end

  -- DEBUG: List all keys in the capabilities table
  log.info("DEBUG: Available keys in capabilities table:")
  for key, _ in pairs(capabilities) do
      if type(key) == "string" and string.find(key, "schoolheart") then
          log.info(" - " .. key)
      end
  end
  
  -- Initialize default state for printerControl so buttons appear immediately
  -- Use pcall to avoid crashing if capability is not found
  local success, err = pcall(function()
      device:emit_event({
          attribute_id = "state",
          capability_id = "schoolheart47510.printerControl",
          component_id = "main",
          state = { value = "stop" }
      })
  end)
  
  if not success then
      print("WARN: Failed to emit default printerControl state:", err)
  end
  
  -- Initialize default state for printTimeDisplay
  pcall(function()
      -- Use raw event emission to avoid dependency on capability object
      device:emit_event({
          attribute_id = "totalTime",
          capability_id = "schoolheart47510.printTimeDisplay",
          component_id = "main",
          state = { value = "--" }
      })
      device:emit_event({
          attribute_id = "remainingTime",
          capability_id = "schoolheart47510.printTimeDisplay",
          component_id = "main",
          state = { value = "--" }
      })
  end)
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

local function handle_printer_control(driver, device, command)
  local client = active_devices[device.id]
  if client then
    client:handle_printer_control(command)
  end
end

-----------------------------------------------------------------------
-- DRIVER DEFINITION
-----------------------------------------------------------------------

local bambu_driver = Driver("bambu-lab-driver", {
  capability_handlers = {
    [capabilities["schoolheart47510.bambuChamberLight"].ID] = {
      ["on"] = handle_switch,
      ["off"] = handle_switch,
      ["setLight"] = handle_switch,
      ["toggle"] = handle_switch
    },
    [capabilities["schoolheart47510.printerControl"].ID] = {
      ["setControl"] = handle_printer_control,
      ["resume"] = handle_printer_control,
      ["pause"] = handle_printer_control,
      ["stop"] = handle_printer_control
    }
  },
  discovery = function(driver, opts, cons)
    print(">>> DISCOVERY: Criando dispositivo Bambu Lab...")
    
    local metadata = {
      type = "LAN",
      -- ID único baseado no tempo e random para evitar conflitos
      device_network_id = "bambu_printer_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
      label = "Bambu Lab Printer v1.1.1",
      profile = "BambuPrinterV2", -- Verificado no config.yaml
      manufacturer = "Bambu Lab",
      model = "Generic",
      vendor_provided_label = "BambuLab Printer"
    }
    
    local res, err = driver:try_create_device(metadata)
    print("DEBUG: try_create_device result:", res, err)
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