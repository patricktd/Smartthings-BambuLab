-- Início do arquivo init.lua

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
YWxTaWduIG52LXNhMRAwDgYDVQQLEwdSb290IENBMRswGQYDVQQDExJHbG9iYWxT
aWduIFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDaDuaZ
jc6j40+Kfvvxi4Mla+pIH/EqsLmVEQS98GPR4mdmzxzdzxtIK+6NiY6arymAZavp
xy0Sy6scTHAHoT0KMM0VjU/43dSMUBUc71DuxC73/OlS8pF94G3VNTCOXkNz8kHp
1Wrjsok6Vjk4bwY8iGlbKk3Fp1S4bInMm/k8yuX9ifUSPJJ4ltbcdG6TRGHRjcdG
snUOhugZitVtbNV4FpWi6cgKOOvyJBNPc1STE4U6G7weNLWLBYy5d4ux2x8gkasJ
U26Qzns3dLlwR5EiUWMWea6xrkEmCMgZK9FGqkjWZCrXgzT/LCrBbBlDSgeF59N8
9iFo7+ryUp9/k5DPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8E
BTADAQH/MB0GA1UdDgQWBBRge2YaRQ2XyolQL30EzTSo//z9SzANBgkqhkiG9w0B
AQUFAAOCAQEA1nPnfE920I2/7LqivjTFKDK1fPxsnCwrvQmeU79rXqoRSLblCKOz
yj1hTdNGCbM+w6DjY1Ub8rrvrTnhQ7k4o+YviiY776BQVvnGCv04zcQLcFGUl5gE
38NflNUVyRRBnMRddWQVDf9VMOyGj/8N7yy5Y0b2qvzfvGn9LhJIZJrglfCm7ymP
AbEVtQwdpf5pLGkkeB6zpxxxYu7KyJesF12KwvhHhm4qxFYxldBniYUr+WymXUad
DKqC5JlR3XC321Y9YeRq4VzW9v493kHMB65jUr9TU/Qr6cf9tveCX4XSQRjbgbME
HMUfpIBvFSDJ3gyICh3WZlXi/EjJKSZp4A==
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
  local ip = device.preferences.printerIp:match("^%s*(.-)%s*$")
  local port = device.preferences.printerPort
  local pass = device.preferences.accessCode
  local serial = device.preferences.serialNumber

  if not (ip and port and pass and serial and ip ~= "" and ip ~= "192.168.1.x" and serial ~= "Serial") then
    device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("Config. Incompleta"))
    return
  end

  local client = mqtt.client({
    uri = string.format("mqtts://%s:%s", ip, port),
    clean = true,
    id = serial,
    username = "bblp",
    password = pass,
    secure = {
      mode = "client",
      protocol = "tlsv1_2",
      ca_data = BAMBU_CA_CERT,
      verify = "peer",
      options = "all",
    }
  })
  
  -- Lógica de conexão melhorada
  client:on("connect", function()
    log.info("MQTT conectado com sucesso!")
    -- Define o status como 'Idle' (Ocioso)
    device:emit_event(capabilities["patchprepare64330.printerStatus"].printer("Idle"))
    local topic = string.format("device/%s/report", serial)
    client:subscribe({topic = topic})
  end)

  client:on("message", function(msg)
    local payload = msg.payload
    local ok, data = pcall(json.decode, payload)
    if not ok or not data or not data.print then return end

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

-- Fim do arquivo init.lua