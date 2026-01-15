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

  if device.device_network_id == "BambuLab-Bridge-Main" then
      return
  end

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

local function handle_add_printer(driver, device, command)
  log.info("BRIDGE: Solicitacao para adicionar nova impressora recebida.")
  
  -- Lógica original de criação de impressora movida para cá
  local metadata = {
    type = "LAN",
    -- ID único baseado no tempo e random para evitar conflitos
    device_network_id = "bambu_printer_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    label = "Bambu Lab Printer v" .. DRIVER_VERSION,
    profile = "BambuPrinterV2", -- Certifique-se que este perfil existe
    manufacturer = "Bambu Lab",
    model = "Generic",
    vendor_provided_label = "BambuLab Printer"
  }
  
  local res, err = driver:try_create_device(metadata)
  if res then
      log.info("BRIDGE: Nova impressora criada com sucesso!")
  else
      log.error("BRIDGE: Falha ao criar impressora: " .. tostring(err))
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

    [capabilities.refresh.ID] = {
      ["refresh"] = handle_refresh
    },
    [capabilities.momentary.ID] = {
      ["push"] = handle_add_printer
    }
  },
  discovery = function(driver, opts, cons)
    print(">>> DISCOVERY: Verificando status do Bridge...")
    
    local bridge_id = "BambuLab-Bridge-Main"
    local found = false
    
    local device_list = driver:get_devices()
    for _, device in ipairs(device_list) do
        if device.device_network_id == bridge_id then
            found = true
            print("DEBUG: Bridge ja existe. Nenhuma acao necessaria.")
            break
        end
    end
    
    if not found then
        print("DEBUG: Criando dispositivo Bridge...")
        local metadata = {
            type = "LAN",
            device_network_id = bridge_id,
            label = "Bambu Lab Bridge",
            profile = "BambuBridge",
            manufacturer = "Bambu Lab",
            model = "Bridge",
            vendor_provided_label = "BambuLab Bridge"
        }
        local res, err = driver:try_create_device(metadata)
        print("DEBUG: try_create_device (Bridge) result:", res, err)
    end
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
        -- Skip Bridge device
        if device.device_network_id == "BambuLab-Bridge-Main" then
            goto continue
        end

        local client = active_devices[device.id]
        if client then
            -- Check if client is healthy
            pcall(function() client:check_connection() end)
        else
            -- If device exists but no client, try to add it (Recovery)
            log.warn("CONNECTION MANAGER: Device " .. device.label .. " has no active client. Re-initializing...")
            device_added(bambu_driver, device)
        end
        ::continue::
    end
end

-- Schedule the check every 60 seconds
bambu_driver:call_on_schedule(60, check_connections)

bambu_driver:run()