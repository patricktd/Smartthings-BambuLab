local Driver = require('st.driver')
local log = require('log')

local function do_poll(device)
  -- Pega as preferências do usuário
local name = device.preferences["printerName"]
local ip = device.preferences["printerIp"]
  
  log.info("Nome da impressora: " .. name)
  log.info("IP da impressora: " .. ip)
  
  -- Aqui você faz a requisição HTTP pro IP configurado para buscar status da impressora
  -- Exemplo:
  -- local http = require("socket.http")
  -- local body, code, headers, status = http.request("http://"..ip.."/api/status")
  -- (implemente conforme API da Bambu)
end

local function added_handler(driver, device)
  log.info("Dispositivo BambuLab adicionado.")
  do_poll(device)  -- Faz o primeiro poll logo após adicionar
end

local driver = Driver("bambu-printer-simple", {
  discovery = nil, -- remove discovery!
  lifecycle_handlers = {
    added = added_handler,
    -- Inclua outros handlers conforme necessário
  },
})

driver:run()
