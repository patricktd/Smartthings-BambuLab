local Driver = require('st.driver')
local log = require('log')
local capabilities = require('st.capabilities')
local mqtt = require('mqtt')
local cosock = require('cosock')
local json = require('dkjson')

local BAMBU_CA_CERT = [[
-----BEGIN CERTIFICATE-----
MIIDdTCCAl2gAwIBAgILBAAAAAABFUtaw5QwDQYJKoZIhvcNAQEFBQAwVzELMAkG
A1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExEDAOBgNVBAsTB1Jv
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
AQH/MB0GA1UdDgQWBBRge2YaAo5iSir3C63shDxD5GmdXjANBgkqhkiG9w0BAQUF
AAOCAQEAMFZo+uIP7/M6RoGU2AFec7/TE5DBHnaUjGUX3XPta7lqAfYVNbATo031
i2bQMeUR/djOc774T1C52jGv6IRTClBtIsoTaj1Vrb2omQv10p9sB3EMLkFaaO3E
aGSfbnlSDe+gHwvBf1uKmIQqqzVhfchxSZEjAGR+hMvctAQjsUu9lYEEvVyBdvacc
wIOxej2Sk3OonDbn+0A+Sj8ppim5oo+QXvK0LcpINF+gh9klVFuWebG/C4FmrIeY
2VEciE2j9ESvsun8AakKvHZzNch5+Dir+jZYsX邱/iMHMeonJgUHvy
-----END CERTIFICATE-----
]]

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
  device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("Offline: Configure"))
  device:emit_event(capabilities["patchprepare64330.printerProgress"].percentComplete(0))
end

local function connect_mqtt(driver, device)
  local ip = device.preferences.printerIp
  local port = device.preferences.printerPort
  local pass = device.preferences.accessCode
  local serial = device.preferences.serialNumber

  if not (ip and port and pass and serial and ip ~= "192.168.1.x" and serial ~= "Serial") then
    device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("Config. Incompleta"))
    return
  end


  local client = mqtt.client({
    uri = string.format("%s:%s", ip, port),
    clean = true,
    id = serial,
    username = "bblp",
    password = pass,
    secure = true
  })
  
  client:on("connect", function()
    device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("Conectado"))
    local topic = string.format("device/%s/report", serial)
    client:subscribe({topic = topic})
  end)

  client:on("message", function(msg)
    local payload = msg.payload
    local data, pos, err = json.decode(payload)
    if err or not data.print then return end

    local print_data = data.print
    if print_data.gcode_state then
      device:emit_event(capabilities["patchprepare64330.printerStatus"].printer(print_data.gcode_state))
    end
    if print_data.mc_percent then
        device:emit_event(capabilities["patchprepare64330.printerProgress"].percentComplete(print_data.mc_percent))
    end
  end)
  
  client:on("error", function(err)
    device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("Erro de Conexão"))
    log.error("MQTT error", err)
  end)

  device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("Conectando..."))

  cosock.spawn(function()
    local ok, err = mqtt.run_sync(client)
    if not ok then
      log.error("MQTT loop stopped", err)
    end
  end, "mqtt-loop")
end

local function info_changed_handler(driver, device, event, args)
  connect_mqtt(driver, device)
end

local driver = Driver("bambu-printer-novo-id", {
  discovery = discovery,
  lifecycle_handlers = {
    added = added_handler,
    infoChanged = info_changed_handler
  },
})

driver:run()
