local capabilities = require "st.capabilities"
local cosock = require "cosock"
local socket = cosock.socket
local log = require "log"

local cap_status = capabilities["patchprepare64330.status"]

local M = {}

function M.refresh_data(driver, device)
  log.info(string.format("[%s] Atualizando dados da impressora...", device.id))

  local ip = device.ip_address
  local port = device.port

  if not ip then
    log.error(string.format("[%s] IP da impressora não encontrado. Não é possivel atualizar.", device.id))
    device:emit_event(cap_status.printer("offline"))
    return
  end

  local conn, err = socket.tcp()
  if not conn then
    log.error("Falha ao criar socket TCP: " .. (err or "desconhecido"))
    return
  end

  conn:settimeout(5)
  local ok, err = conn:connect(ip, port)

  if ok then
    log.info(string.format("[%s] Impressora está online em %s:%d", device.id, ip, port))
    device:emit_event(cap_status.printer("standby"))
  else
    log.error(string.format("[%s] Impressora offline ou inacessível: %s", device.id, err or "timeout"))
    device:emit_event(cap_status.printer("offline"))
  end

  conn:close()
end

return M
