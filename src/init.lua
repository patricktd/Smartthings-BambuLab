local Driver = require('st.driver')
local log = require('log')
local capabilities = require('st.capabilities')

-- Certificado CA da Bambu Lab (versão verificada)
local BAMBU_CA_CERT = [[
-----BEGIN CERTIFICATE-----
MIIDdTCCAl2gAwIBAgILBAAAAAABFUtaw5QwDQYJKoZIhvcNAQEFBQAwVzELMAkG
A1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZG4gbnYtc2ExEDAOBgNVBAsTB1Jv
b3QgQ0ExGzAZBgNVBAMTEkdsb2JhbFNpZG4gUm9vdCBDQTAeFw05ODA5MDExMjAw
MDBaFw0yODAxMjgxMjAwMDBaMFcxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9i
YWxTaWduIG52LXNhMRAwDgNVQQLEwdSb290IENBMRswGQYDVQQDExJHbG9iYWxT
aWduIFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDaDuaZ
jc6j40+Kfvvxi4Mla+pIH/EqsLmVEQS98GPR4mdmzssCoZdQXzXdPDjq/iTxGVG/
kMCdpA4bn1dMC6UPhhdOBSuToIhsNrWCFktUfROQE5/GhDsspe56CFxvLtpVb28T
aFt6LDU20Gmm57ZCrFzfrE7DoAIM8P4JCI5c3sIj3xNIHsyZjXpLtRma+wbcDH8p
OdbpGvMsIydIDgCesTbfPbDNAoEJASF2LBHJZUhsEffT79/wG9V91ejf7SMsNTxJ
sS6yYUD3YOGAaob3fVLevajgcyz3TgTxGD6d6lOoGMSDXvLeGXkFk+IHCyJSoJ2o
+6GtawW6f8i9AgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTAD
AQH/MB0GA1UdDgQWBBRge2YaAo5iSir3C63shDxD5GmdXjANBgkqhkiG9w0BAQUF
AAOCAQEAMFZo+uIP7/M6RoGU2AFec7/TE5DBHnaUjGUX3XPta7lqAfYVNbATo031
i2bQMeUR/djOc774T1C52jGv6IRTClBtIsoTaj1Vrb2omQv10p9sB3EMLkFaaO3E
aGSfbnlSDe+gHwvBf1uKmIQqqzVhfchxSZEjAGR+hMvctAQjsUu9lYEEvVyBdvacc
wIOxej2Sk3OonDbn+0A+Sj8ppim5oo+QXvK0LcpINF+gh9klVFuWebG/C4FmrIeY
2VEciE2j9ESvsun8AakKvHZzNch5+Dir+jZYsX邱/iMHMeonJgUHvy
-----END CERTIFICATE-----
]]

log.info(">>> Driver Edge BambuLab foi carregado e está aguardando discovery...")

local function discovery(driver, opts, continue)
  log.info(">>> Discovery foi chamado!")
  local new_dni = string.format("bambulab-manual-%s", os.time())
  log.info(">>> Gerando novo ID único para o dispositivo: " .. new_dni)
  
  driver:try_create_device({
    type = "LAN",
    device_network_id = new_dni,
    label = "Bambulab Printer",
    profile = "BambuPrinter"
  })
  log.info(">>> Tentativa de criação do dispositivo Bambu Printer Manual enviada!")
end

local function added_handler(driver, device)
  log.info(">>> Handler ADDED chamado! Device: " .. device.id)
  
  local status = device:get_field("status") or "desconhecido"
  local ip = device:get_field("ip") or device.preferences["printerIp"] or "0.0.0.0"

  device:set_field("status", status, {persist = true})
  device:set_field("ip", ip, {persist = true})

  log.info(string.format(">>> Campos iniciais setados: status=%s, ip=%s", status, ip))

  device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("desconhecido"))
  device:emit_event(capabilities["patchprepare64330.printerProgress"].percentComplete(0))

  log.info(">>> Estado inicial da capability 'printerStatus' foi definido.")
end

local function info_changed_handler(driver, device, event, args)
  log.info(string.format(">>> INFO_CHANGED chamado para o dispositivo: %s", device.label))
  
  -- Imprime todas as configurações para depuração
  for name, value in pairs(device.preferences) do
    log.info(string.format("    - Pref: %s = %s", name, tostring(value)))
  end

  -- No futuro, a chamada para a função de conexão MQTT virá aqui.
end

local driver = Driver("bambu-printer", {
  discovery = discovery,
  lifecycle_handlers = {
    added = added_handler,
    infoChanged = info_changed_handler
  },
})

driver:run()