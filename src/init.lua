local Driver = require('st.driver')
local log = require('log')
local capabilities = require('st.capabilities')

-- =================================================================
-- Handler que processa o pacote da impressora quando ele chega
-- =================================================================
local function bambu_ssdp_handler(driver, ssdp_packet)
  log.info("[BAMBU LOG] >>> PACOTE SSDP RECEBIDO! Processando...")

  local serial_number = ssdp_packet.usn
  local device_label = ssdp_packet['DevName.bambu.com'] or ("Bambu Lab " .. serial_number)
  log.info(string.format("[BAMBU LOG] >>> IMPRESSORA ENCONTRADA: %s (S/N: %s)", device_label, serial_number))

  local metadata = {
    profile = "bambulab.discovered-printer.v1",
    device_network_id = serial_number,
    label = device_label
  }
  -- A criação do dispositivo é feita aqui
  driver:try_create_device(metadata)
end

-- =================================================================
-- Handler de Descoberta Genérico (Ponto de Entrada)
-- =================================================================
local function start_discovery(driver)
  log.info("[BAMBU LOG] >>> Handler 'discovery' GENÉRICO chamado no arranque.")
  
  -- Define qual função irá tratar os pacotes SSDP quando eles chegarem
  driver:set_ssdp_handler(bambu_ssdp_handler, "urn:bambulab-com:device:3dprinter:1")
  
  -- Inicia a escuta na rede
  driver:discover()
  
  log.info("[BAMBU LOG] >>> Escuta SSDP iniciada com sucesso. Aguardando pacotes das impressoras...")
end

-- =================================================================
-- Construção do Driver (Usando a estrutura que funciona para si)
-- =================================================================
local bambu_driver = Driver("bambu-printer-patricktd", {
  -- A única coisa que definimos na construção é o nosso ponto de entrada.
  discovery = start_discovery
})

-- Inicia o driver
bambu_driver:run()
