local Driver = require('st.driver')
local log = require('log')
local capabilities = require('st.capabilities')

log.info(">>> Driver Edge BambuLab foi carregado e está aguardando discovery...")

local function discovery(driver, opts, continue)
  log.info(">>> Discovery foi chamado!")

  -- =================================================================
  -- >> A MÁGICA ACONTECE AQUI <<
  -- Em vez de um ID fixo, geramos um ID de rede (DNI) único usando a hora atual.
  local new_dni = string.format("bambulab-printer-%s", os.time())
  log.info(">>> Gerando DNI único: " .. new_dni)
  -- =================================================================

  driver:try_create_device({
    type = "LAN",
    device_network_id = new_dni, -- Usamos o DNI único aqui
    label = "Bambulab Printer",
    profile = "BambuPrinter",
    manufacturer = "Bambulab",
    model = "Manual",
    vendor_provided_label = "Bambu Printer PATTETECH"
  })
  log.info(">>> Tentativa de criação do dispositivo Bambu Printer Manual enviada!")
end

-- Este handler é chamado uma vez quando o dispositivo é adicionado ao hub
local function added_handler(driver, device)
  log.info(">>> Handler ADDED chamado! Device: " .. device.id)
  
  -- Inicializa campos persistentes
  local status = device:get_field("status") or "desconhecido"
  local ip = device:get_field("ip") or device.preferences["printerIp"] or "0.0.0.0"

  device:set_field("status", status, {persist = true})
  device:set_field("ip", ip, {persist = true})

  log.info(string.format(">>> Campos iniciais setados: status=%s, ip=%s", status, ip))

  device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("desconhecido"))
  device:emit_event(capabilities["patchprepare64330.printerProgress"].percentComplete(0))

  log.info(">>> Estado inicial da capability 'printerStatus' foi definido.")
end

-- Cria a instância do driver com os handlers
local driver = Driver("bambu-printer", {
  discovery = discovery,
  lifecycle_handlers = {
    added = added_handler
  },
})

-- Inicia o driver
driver:run()