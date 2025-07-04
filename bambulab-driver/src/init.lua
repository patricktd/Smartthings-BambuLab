local Driver = require('st.driver')
local log = require('st.log')
local capabilities = require('st.capabilities')

-- Definimos uma variável para o nosso driver
local BambuLabPrinterDriver = {}

-- Esta tabela define o perfil da nossa impressora. O driver a usará para criar o dispositivo.
local bambu_printer_profile = {
  name = 'bambulab-printer',
  components = {
    main = {
      id = 'main',
      capabilities = {
        { id = 'pattetech.printStatus', version = 1 },
        { id = 'pattetech.printProgress', version = 1 },
        { id = 'refresh', version = 1 }
      }
    },
    hotend = {
      id = 'hotend',
      label = 'Hotend',
      capabilities = {
        { id = 'temperatureMeasurement', version = 1 }
      }
    },
    bed = {
      id = 'bed',
      label = 'Bed',
      capabilities = {
        { id = 'temperatureMeasurement', version = 1 }
      }
    }
  }
}

-- Função que é chamada quando o botão do "Instalador" é acionado
function create_printer_handler(driver, device, command)
  log.info('Comando para criar a impressora recebido!')

  -- Usamos o perfil que definimos acima para criar o dispositivo da impressora
  driver:try_create_device(bambu_printer_profile)

  log.info('Tentativa de criação do dispositivo da impressora enviada.')
  -- Opcional: Desligar o botão após o uso para que ele possa ser usado novamente
  device:emit_event(capabilities.switch.switch.off())
end

-- Função chamada quando um dispositivo é adicionado
function BambuLabPrinterDriver.device_added(driver, device)
  log.info('Dispositivo adicionado. Perfil: ' .. device.profile.name)
  -- Lógica para quando o dispositivo da IMPRESSORA é adicionado
  if device.profile.name == 'bambulab-printer' then
    log.info('Dispositivo Bambu Lab (criado) adicionado! ID: ' .. device.id)
    -- Emitir os valores iniciais para o dispositivo da impressora
    device:emit_event({ component = 'main', capability = 'pattetech.printStatus', attribute = 'status', value = 'Pronto'})
    device:emit_event({ component = 'main', capability = 'pattetech.printProgress', attribute = 'progress', value = 0})
    device:emit_component_event(device.profile.components.hotend, { capability = 'temperatureMeasurement', attribute = 'temperature', value = 0, unit = 'C' })
    device:emit_component_event(device.profile.components.bed, { capability = 'temperatureMeasurement', attribute = 'temperature', value = 0, unit = 'C' })
  end
end

-- Esta função é chamada quando o "Instalador" é criado pela primeira vez
function BambuLabPrinterDriver.init(driver)
  log.info('Driver Bambu Lab inicializado. Criando o dispositivo Instalador se necessário.')
  -- Criamos o dispositivo "Instalador" automaticamente na primeira vez que o driver roda
  driver:try_create_device({
    profile = 'bambulab-creator.v1',
    label = 'Bambu Lab Creator'
  })
end


-- Aqui definimos que a função 'create_printer_handler' deve ser chamada
-- quando o comando 'on' do 'switch' for recebido.
BambuLabPrinterDriver.capability_handlers = {
  [capabilities.switch.ID] = {
    [capabilities.switch.commands.on.NAME] = create_printer_handler
  }
}

-- Cria a instância do driver e o executa
local driver = Driver('Bambu Lab Printer Driver', BambuLabPrinterDriver)
driver:run()