local Driver = require('st.driver')
local capabilities = require('st.capabilities')

-- Função chamada quando o dispositivo é adicionado pela primeira vez
local function device_added_handler(driver, device)
  driver.log.info(string.format('Dispositivo %s adicionado. Aguardando configuração de IP.', device.id))
  
  -- Define o estado inicial para as capabilities padrão
  device:emit_event(capabilities.contactSensor.contact.closed()) -- "Fechado" = Não configurado/Idle
  device:emit_event(capabilities.switchLevel.level(0)) -- Progresso em 0%
  device:emit_component_event(device:get_component("hotend"), capabilities.temperatureMeasurement.temperature({ value = 0, unit = 'C' }))
  device:emit_component_event(device:get_component("bed"), capabilities.temperatureMeasurement.temperature({ value = 0, unit = 'C' }))
end

-- Função chamada quando o usuário salva as configurações do dispositivo
local function info_changed_handler(driver, device, event, args)
  driver.log.info(string.format('Configurações do dispositivo %s alteradas.', device.id))
  
  if device.preferences.printerIp and device.preferences.printerIp ~= "" then
    driver.log.info('Endereço IP configurado para: ' .. device.preferences.printerIp)
    
    -- Aqui futuramente você pode iniciar a conexão
    device:emit_event(capabilities.contactSensor.contact.closed()) -- "Fechado" = Configurado e Idle
  end
end

-- Função de discovery: cria o dispositivo automaticamente
local function discovery_handler(driver, opts, cont)
  driver.log.info('Discovery iniciado: criando dispositivo Bambu Lab...')

  local create_device_msg = {
    type = "LAN",
    device_network_id = "bambulab_manual_" .. os.time(),
    label = "Bambu Lab Printer",
    profile = "bambulab-printer-manual",
    manufacturer = "Bambu Lab",
    model = "Manual",
    vendor_provided_label = nil
  }

  driver:try_create_device(create_device_msg)
end

-- Cria o driver com os handlers
local driver = Driver('Bambu Lab Driver Funcional', {
  discovery = discovery_handler,
  device_added = device_added_handler,
  info_changed = info_changed_handler
})

driver:run()
