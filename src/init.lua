-- Bibliotecas padrão do SmartThings
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

-- Bibliotecas de rede e JSON
local cosock = require "cosock"
local socket = require "cosock.socket"
local json = require "dkjson"

-- Módulo de descoberta customizado
local discovery = require "discovery"

-- Mapeamento das capacidades
-- Adicionamos a capacidade de Refresh, que é uma prática padrão
local cap_refresh = capabilities.refresh
local cap_status = capabilities["patchprepare64330.status"]

-----------------------------------------------------------------
-- Função principal de atualização de dados
-----------------------------------------------------------------

---
-- Faz uma requisição HTTP para a impressora para obter seu status atual.
-- @param driver A instância do driver.
-- @param device O dispositivo a ser atualizado.
local function refresh_data(driver, device)
  log.info(string.format("[%s] Atualizando dados da impressora...", device.id))

  -- Precisamos do IP e da porta que foram salvos durante a descoberta
  local ip = device.ip_address
  local port = device.port

  if not ip then
    log.error(string.format("[%s] IP da impressora não encontrado. Não é possível atualizar.", device.id))
    device:emit_event(cap_status.printer("offline"))
    return
  end
  
  -- OBS: A API real da Bambu Lab usa MQTT. Uma requisição HTTP simples pode não retornar o status completo.
  -- Este exemplo fará um "ping" na porta para verificar se a impressora está online.
  -- Para um status detalhado (printing, paused, etc.), seria necessário implementar um cliente MQTT.
  local conn, err = socket.tcp()
  if not conn then
    log.error("Falha ao criar socket TCP: " .. (err or "desconhecido"))
    return
  end

  conn:settimeout(5) -- Timeout de 5 segundos
  local ok, err = conn:connect(ip, port)

  if ok then
    log.info(string.format("[%s] Impressora está online em %s:%d", device.id, ip, port))
    -- Se a conexão for bem-sucedida, consideramos que está "standby".
    -- A lógica real para obter "printing", etc., seria mais complexa.
    device:emit_event(cap_status.printer("standby"))
  else
    log.error(string.format("[%s] Impressora offline ou inacessível: %s", device.id, err or "timeout"))
    device:emit_event(cap_status.printer("offline"))
  end

  -- Fecha o socket em qualquer cenário para evitar vazamento de recursos
  conn:close()
end

-----------------------------------------------------------------
-- Handlers do ciclo de vida do dispositivo
-----------------------------------------------------------------

local function device_init(driver, device)
  log.info(string.format("[%s] Inicializando impressora Bambu Lab", device.id))
  device:online()

  -- Agenda a atualização periódica. Usa a preferência 'pollInterval' ou 60s como padrão.
  local poll_interval = device.preferences.pollInterval or 60
  device:call_on_schedule(poll_interval, function() refresh_data(driver, device) end)

  -- Faz uma atualização imediata ao inicializar
  refresh_data(driver, device)
end

local function device_added(driver, device)
  log.info(string.format("[%s] Adicionando nova impressora Bambu Lab", device.id))
  -- Nenhuma ação especial necessária aqui por enquanto
end

local function device_removed(driver, device)
  log.info(string.format("[%s] Removendo impressora Bambu Lab", device.id))
  -- Cancela qualquer timer agendado para este dispositivo
  device:cancel_timers()
end

---
-- Lida com mudanças nas configurações do dispositivo (ex: mudança de IP)
local function handle_infochanged(driver, device)
  log.info(string.format("[%s] Informações do dispositivo alteradas. Reagendando timers.", device.id))
  device:cancel_timers()
  -- Re-inicializa para aplicar as novas configurações
  device_init(driver, device)
end

-----------------------------------------------------------------
-- Handlers das capacidades
-----------------------------------------------------------------

---
-- Lida com o comando de refresh manual do app
local function handle_refresh(driver, device)
  log.info(string.format("[%s] Comando de refresh manual recebido.", device.id))
  refresh_data(driver, device)
end

-----------------------------------------------------------------
-- Definição e execução do driver
-----------------------------------------------------------------

local bambulab_driver = Driver("Bambu Lab", {
  discovery = discovery.handle_discovery,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    removed = device_removed,
    infoChanged = handle_infochanged
  },
  capability_handlers = {
    [cap_refresh.ID] = {
      [cap_refresh.commands.refresh.NAME] = handle_refresh,
    }
  }
})

-- CORREÇÃO FINAL: Use o nome correto do objeto do driver!
bambulab_driver:run()
