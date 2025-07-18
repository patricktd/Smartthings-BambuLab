local Driver = require('st.driver')
local log = require('log')
local capabilities = require('st.capabilities')
local mqtt = require('st.mqtt')
local json = require('dkjson')

-- Certificado CA da Bambu Lab
local BAMBU_CA_CERT = [[
-----BEGIN CERTIFICATE-----
MIIDdTCCAl2gAwIBAgILBAAAAAABFUtaw5QwDQYJKoZIhvcNAQEFBQAwVzELMAkG
A1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZG4gbnYtc2ExEDAOBgNVBAsTB1Jv
b3QgQ0ExGzAZBgNVBAMTEkdsb2JhbFNpZ24gUm9vdCBDQTAeFw05ODA5MDExMjAw
MDBaFw0yODAxMjgxMjAwMDBaMFcxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9i
YWxTaWduIG52LXNhMRAwDgNVQQLEwdSb290IENBMRswGQYDVQQDExJHbG9iYWxT
aWduIFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDaDuaZ
jc6j40+Kfvvxi4Mla+pIH/EqsLmVEQS98GPR4mdmzssCoZdQXzXdPDjq/iTxGVG/
kMCdpA4bn1dMC6UPhhdOBSuToIhsNrWCFktUfROQE5/GhDsspe56CFxvLtpVb28T
aFt6LDU20Gmm57ZCrFzfrE7DoAIM8P4JCI5c3sIj3xNIHsyZjXpLtRma+wbcDH8p
OdbpGvMsIydIDgCesTbfPbDNAoEJASF2LBHJZUhsEffT79/wG9V91ejf7SMsNTxJ
sS6yYUD3YOGAaob3fVLevajgcyz3TgTxGD6d6lOoGMSDXvLeGXkFk+IHCyJSoJ2o
+6GtawW6f8i9AgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTAD
AQH/MB0GA1UdDgQWBBRge2YaAo5iSir3C63shDxD5GmdXjANBgkqhkiGമൂഹAAOCAQEAMFZo+uIP7/M6RoGU2AFec7/TE5DBHnaUjGUX3XPta7lqAfYVNbATo031
i2bQMeUR/djOc774T1C52jGv6IRTClBtIsoTaj1Vrb2omQv10p9sB3EMLkFaaO3E
aGSfbnlSDe+gHwvBf1uKmIQqqzVhfchxSZEjAGR+hMvctAQjsUu9lYEEvVyBdvacc
wIOxej2Sk3OonDbn+0A+Sj8ppim5oo+QXvK0LcpINF+gh9klVFuWebG/C4FmrIeY
2VEciE2j9ESvsun8AakKvHZzNch5+Dir+jZYsX邱/iMHMeonJgUHvy
-----END CERTIFICATE-----
]]

log.info(">>> Driver Edge BambuLab foi carregado...")

local function discovery(driver, opts, continue)
  local new_dni = string.format("bambulab-manual-%s", os.time())
  driver:try_create_device({
    type = "LAN",
    device_network_id = new_dni,
    label = "Bambulab Printer",
    profile = "BambuPrinter"
  })
end

local function added_handler(driver, device)
  log.info(">>> Handler ADDED chamado! Device: " .. device.id)
  device:emit_event(capabilities["patchprepare64330.printerStatus"].printerStatus("Offline: Configure"))
  device:emit_event(capabilities["patchprepare64330.printerProgress"].progress(0))
end

-- =================================================================
-- >> LÓGICA DE CONEXÃO MQTT COMPLETA <<
-- =================================================================
local function connect_mqtt(driver, device)
  local ip = device.preferences.printerIp
  local port = device.preferences.printerPort
  local pass = device.preferences.accessCode
  local serial = device.preferences.serialNumber

  if not (ip and port and pass and serial and ip ~= "192.168.1.x" and serial ~= "Serial") then
    log.warn(">>> MQTT: Configurações incompletas. A aguardar.")
    device:emit_event(capabilities["patchprepare64330.printerStatus"].printerStatus("Config. Incompleta"))
    return
  end

  -- O Client ID deve ser o número de série da impressora
  local client = mqtt.new(ip, port, serial)
  
  client:on("connect", function()
    log.info(string.format(">>> MQTT: Conexão estabelecida com sucesso para %s!", device.label))
    device:emit_event(capabilities["patchprepare64330.printerStatus"].printerStatus("Conectado"))
    
    local topic = string.format("device/%s/report", serial)
    client:subscribe(topic)
    log.info(">>> MQTT: Subscrito ao tópico: " .. topic)
  end)

  client:on("message", function(topic, payload)
    log.info(">>> MQTT: Mensagem recebida: " .. payload)
    
    local data, pos, err = json.decode(payload)
    if err or not data.print then return end

    local print_data = data.print
    if print_data.gcode_state then
      device:emit_event(capabilities["patchprepare64330.printerStatus"].printerStatus(print_data.gcode_state))
    end
    if print_data.mc_percent then
      device:emit_event(capabilities["patchprepare64330.printerProgress"].progress(print_data.mc_percent))
    end
  end)
  
  client:on("error", function(_, err)
      log.error(">>> MQTT Erro: " .. err)
      device:emit_event(capabilities["patchprepare64330.printerStatus"].printerStatus("Erro de Conexão"))
  end)

  log.info(string.format(">>> MQTT: A tentar conectar ao broker MQTTS em %s:%d", ip, port))
  device:emit_event(capabilities["patchprepare64330.printerStatus"].printerStatus("Conectando..."))
  
  -- Inicia a tentativa de conexão segura (MQTTS)
  client:start({
    username = "bblp",
    password = pass,
    tls = {
      ca = BAMBU_CA_CERT
    }
  })
end

local function info_changed_handler(driver, device, event, args)
  log.info(string.format(">>> INFO_CHANGED chamado para o dispositivo: %s", device.label))
  connect_mqtt(driver, device)
end

-- Cria a instância do driver
local driver = Driver("bambu-printer", {
  discovery = discovery,
  lifecycle_handlers = {
    added = added_handler,
    infoChanged = info_changed_handler
  },
})

driver:run()