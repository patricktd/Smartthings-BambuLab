package.path = package.path .. ';src/?.lua'

-- stub st.capabilities
local cap_status = { printer = function(value) return { value = value } end }
package.loaded['st.capabilities'] = { ['patchprepare64330.status'] = cap_status }

-- stub cosock socket
local cosock_stub = { socket = {} }
package.loaded['cosock'] = cosock_stub
package.loaded['cosock.socket'] = cosock_stub.socket
package.loaded['log'] = { info=function() end, error=function() end }

local refresh = require 'refresh'

describe('refresh_data', function()
  it('emits standby when connection succeeds', function()
    cosock_stub.socket.tcp = function()
      return {
        settimeout = function() end,
        connect = function() return true end,
        close = function() end
      }
    end
    local device = { id='1', ip_address='1.2.3.4', port=80, events={} }
    function device:emit_event(evt) table.insert(self.events, evt.value) end
    refresh.refresh_data({}, device)
    assert.are.same({'standby'}, device.events)
  end)

  it('emits offline when connection fails', function()
    cosock_stub.socket.tcp = function()
      return {
        settimeout = function() end,
        connect = function() return nil, 'err' end,
        close = function() end
      }
    end
    local device = { id='1', ip_address='1.2.3.4', port=80, events={} }
    function device:emit_event(evt) table.insert(self.events, evt.value) end
    refresh.refresh_data({}, device)
    assert.are.same({'offline'}, device.events)
  end)
end)
