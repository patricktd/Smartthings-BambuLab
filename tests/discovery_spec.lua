package.path = package.path .. ';src/?.lua'

-- stub cosock and dependencies before requiring discovery
local udp_stub = {}
function udp_stub:setsockname() end
function udp_stub:setoption() return true end
function udp_stub:settimeout() end
function udp_stub:sendto(payload, ip, port)
  self.sent_payload = payload
  self.sent_ip = ip
  self.sent_port = port
  return true
end
local called = false
function udp_stub:receivefrom()
  if not called then
    called = true
    local resp = table.concat({
      "HTTP/1.1 200 OK",
      "LOCATION: http://192.168.1.100/",
      "USN: uuid:abcd",
      "DEVNAME.BAMBU.COM: P1P",
      "",
      ""
    }, "\r\n")
    return resp, "192.168.1.100", 1900
  end
  return nil
end
function udp_stub:close() self.closed = true end

local cosock_stub = { socket = { udp = function() return udp_stub end } }
package.loaded["cosock"] = cosock_stub
package.loaded["cosock.socket"] = cosock_stub.socket
package.loaded["log"] = {info=function() end, error=function() end, pretty_print=function() end}

-- manipulate os.time so the loop exits quickly
local original_time = os.time
local counter = 0
os.time = function()
  counter = counter + 3
  return counter
end

local discovery = require 'discovery'

describe('discovery.handle_discovery', function()
  it('creates device when response received', function()
    local created
    local driver = { try_create_device = function(_, meta) created = meta end }
    discovery.handle_discovery(driver, function() return false end)
    assert.is_not_nil(created)
    assert.are.equal('192.168.1.100', created.ip_address)
  end)
end)

os.time = original_time
