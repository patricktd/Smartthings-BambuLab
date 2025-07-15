describe('added_handler', function()
  package.path = package.path .. ';src/?.lua'

  -- stub modules expected by init.lua
  package.loaded['st.driver'] = function(name, opts)
    local driver = {
      name = name,
      try_create_device = function() end,
    }
    function driver:run() end
    return driver
  end
  package.loaded['st.capabilities'] = {
    ["custom.bambuPrinterStatus"] = {
      printerStatus = function(value)
        return {capability = 'status', value = value}
      end
    },
    ["custom.bambuPrinterProgress"] = {
      progress = function(value)
        return {capability = 'progress', value = value}
      end
    }
  }
  package.loaded['log'] = {info = function() end}

  local init = require('init')

  local function build_device(prefs)
    local dev = {id = '1', fields = {}, preferences = prefs or {}}
    function dev:get_field(k) return self.fields[k] end
    function dev:set_field(k, v, opts)
      self.fields[k] = v
      self.set_fields = self.set_fields or {}
      self.set_fields[k] = opts
    end
    function dev:emit_event(evt)
      self.events = self.events or {}
      table.insert(self.events, evt)
    end
    return dev
  end

  it('persists defaults and emits default events', function()
    local dev = build_device()
    init.added_handler(nil, dev)

    assert.equal('desconhecido', dev.fields.status)
    assert.True(dev.set_fields.status.persist)
    assert.equal('0.0.0.0', dev.fields.ip)
    assert.True(dev.set_fields.ip.persist)

    assert.equal('status', dev.events[1].capability)
    assert.equal('stop', dev.events[1].value)
    assert.equal('progress', dev.events[2].capability)
    assert.equal(0, dev.events[2].value)
  end)

  it('prefers stored ip from preferences', function()
    local dev = build_device({printerIp = '1.2.3.4'})
    init.added_handler(nil, dev)
    assert.equal('1.2.3.4', dev.fields.ip)
  end)
end)
