-- Bibliotecas padrão do SmartThings
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

-- Bibliotecas de rede e JSON
local cosock = require "cosock"
local socket = require "cosock.socket"
local json = require "dkjson"
local refresh = require "refresh"

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
  refresh.refresh_data(driver, device)
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
-- Driver definition and execution
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

-- Start the driver event loop
bambulab_driver:run()
