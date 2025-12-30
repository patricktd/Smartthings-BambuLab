local DRIVER_VERSION = "1.1.102"
local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local BambuDevice = require "bambu_device" -- O modulo que voce ja criou
local config = require "config"
local log = require "log"

-- Tabela para gerenciar dispositivos ativos
local active_devices = {}

-----------------------------------------------------------------------
-- LIFECYCLE HANDLERS
-----------------------------------------------------------------------

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
  local client = BambuDevice.new(device, ip, access_code, serial)
  
  active_devices[device.id] = client
  
  -- Inicia a conexao
  client:connect()
end

local function device_init(driver, device)
  print(string.format("DISPOSITIVO INICIADO: %s [ID: %s] (v%s)", device.label, device.id, DRIVER_VERSION))
  
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
  if device.profile.components.others and capabilities["schoolheart47510.printerControl"] then
      local printerControl = capabilities["schoolheart47510.printerControl"]
      pcall(function()
          if printerControl.state then
              device:emit_component_event(device.profile.components.others, printerControl.state("stop"))
          end
      end)
  end
  


  -- Initialize Extended Display
  if device.profile.components.main then
      pcall(function()
          device:emit_event({
                 attribute_id = "remainingTime",
                 capability_id = "schoolheart47510.printDisplayExtended",
                 component_id = "main",
                 state = { value = "--" }
            })
          device:emit_event({
                 attribute_id = "finishTime",
                 capability_id = "schoolheart47510.printDisplayExtended",
                 component_id = "main",
                 state = { value = "--" }
            })
          device:emit_event({
                 attribute_id = "printStatus",
                 capability_id = "schoolheart47510.printDisplayExtended",
                 component_id = "main",
                 state = { value = "--" }
            })
          device:emit_event({
                 attribute_id = "layerInfo",
                 capability_id = "schoolheart47510.printDisplayExtended",
                 component_id = "main",
                 state = { value = "--" }
            })
      end)
  end

  -- Initialize AMS Info
  if device.profile.components.others and capabilities["schoolheart47510.amsSlots"] then
      local cap = capabilities["schoolheart47510.amsSlots"]
      device:emit_component_event(device.profile.components.others, cap.slotA({value = "-"}))
      device:emit_component_event(device.profile.components.others, cap.slotB({value = "-"}))
      device:emit_component_event(device.profile.components.others, cap.slotC({value = "-"}))
      device:emit_component_event(device.profile.components.others, cap.slotD({value = "-"}))
  end

  if device.profile.components.others and capabilities["schoolheart47510.fansDisplayNum"] then
      local cap = capabilities["schoolheart47510.fansDisplayNum"]
      pcall(function()
          device:emit_component_event(device.profile.components.others, cap.coolingFanSpeed({value = 0}))
          device:emit_component_event(device.profile.components.others, cap.auxFanSpeed({value = 0}))
          device:emit_component_event(device.profile.components.others, cap.chamberFanSpeed({value = 0}))
      end)
  end
  
  -- Initialize Health Check
  if capabilities.healthCheck then
      device:emit_event(capabilities.healthCheck.checkInterval(60))
      device:emit_event(capabilities.healthCheck.healthStatus("online"))
  end

  -- CRITICAL FIX: Ensure connection is established on driver startup
  -- device_init is called for existing devices when driver starts.
  -- We must call device_added (or equivalent connection logic) here.
  device_added(driver, device)
end

local function device_removed(driver, device)
  local client = active_devices[device.id]
  if client then
    print("REMOVENDO DISPOSITIVO: " .. device.label)
    client:disconnect(true)
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

local function handle_refresh(driver, device, command)
  log.info("Executando Refresh manual...")
  local client = active_devices[device.id]
  if client then
    client:handle_refresh()
  end
end

-----------------------------------------------------------------------
-- DRIVER DEFINITION
-----------------------------------------------------------------------

local bambu_driver = Driver("bambu-lab-driver", {
  capability_handlers = {
    [capabilities.switch.ID] = {
      ["on"] = handle_switch,
      ["off"] = handle_switch
    },
    [capabilities["schoolheart47510.printerControl"].ID] = {
      ["setControl"] = handle_printer_control,
      ["resume"] = handle_printer_control,
      ["pause"] = handle_printer_control,
      ["stop"] = handle_printer_control
    },
    [capabilities.refresh.ID] = {
      ["refresh"] = handle_refresh
    },

  },
  discovery = function(driver, opts, cons)
    print(">>> DISCOVERY: Criando dispositivo Bambu Lab...")
    
    -- Check for existing devices to avoid duplicates
    -- REMOVED: Allow multiple devices to be created
    -- local existing_devices = driver:get_devices()
    -- for _, device in ipairs(existing_devices) do
    --   print("DEBUG: Found existing device: " .. device.label)
    --   if device.device_network_id:find("bambu_printer_") then
    --      print("DEBUG: Dispositivo Bambu Lab ja existe. Pulando criacao.")
    --      return
    --   end
    -- end
    
    local metadata = {
      type = "LAN",
      -- ID único baseado no tempo e random para evitar conflitos
      device_network_id = "bambu_printer_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
      label = "Bambu Lab Printer v" .. DRIVER_VERSION,
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

-- Periodic Connection Manager
local function check_connections()
    log.info("CONNECTION MANAGER: Checking all devices...")
    local device_list = bambu_driver:get_devices()
    for _, device in ipairs(device_list) do
        local client = active_devices[device.id]
        if client then
            -- Check if client is healthy
            pcall(function() client:check_connection() end)
        else
            -- If device exists but no client, try to add it (Recovery)
            log.warn("CONNECTION MANAGER: Device " .. device.label .. " has no active client. Re-initializing...")
            device_added(bambu_driver, device)
        end
    end
end

-- Schedule the check every 60 seconds
bambu_driver:call_on_schedule(60, check_connections)

bambu_driver:run()