local Driver = require('st.driver')
local log = require('st.log')
local capabilities = require('st.capabilities')

local BambuLabPrinter = {
  driver_template_name = 'bambulab-driver',

  -- Esta função é chamada quando um dispositivo é adicionado ao SmartThings
  device_added = function(self, driver, device)
    log.info('Dispositivo Bambu Lab (simplificado) adicionado! ID: ' .. device.id)
    
    -- Emitir valores iniciais para as capabilities
    
    -- Componente Principal ('main')
    device:emit_event(capabilities.execution.execution.ready()) -- Estado, começa como 'pronto'
    device:emit_event(capabilities.progressMeter.progress(0)) -- Barra de progresso, começa em 0%
    
    -- Componente Hotend
    device:emit_component_event(
      device.profile.components.hotend,
      capabilities.temperatureMeasurement.temperature({ value = 0, unit = 'C' })
    )
    
    -- Componente Bed (Mesa)
    device:emit_component_event(
      device.profile.components.bed,
      capabilities.temperatureMeasurement.temperature({ value = 0, unit = 'C' })
    )
  end
}

local driver = Driver('BambuLabPrinterDriver', BambuLabPrinter)
driver:run()