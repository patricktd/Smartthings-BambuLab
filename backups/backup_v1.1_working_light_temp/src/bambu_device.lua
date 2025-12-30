local log = require('log')
local capabilities = require('st.capabilities')
local mqtt = require('mqtt')
local cosock = require('cosock')
local json = require('dkjson')
local config = require('config')

local BambuDevice = {}
BambuDevice.__index = BambuDevice

local BAMBU_CA_CERT = [[
-----BEGIN CERTIFICATE-----
MIIDdTCCAl2gAwIBAgILBAAAAAABFUtaw5QwDQYJKoZIhvcNAQEFBQAwVzELMAkG
A1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExEDAOBgNVBAsTB1Jv
ot CA1GzAZBgNVBAMTEkdsb2JhbFNpZ24gUm9vdCBDQTAeFw05ODA5MDExMjAw
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

function BambuDevice.new(device, ip, access_code, serial)
  local self = setmetatable({}, BambuDevice)
  self.device = device
  self.ip = ip
  self.access_code = access_code
  self.serial = serial
  self.client = nil
  return self
end

function BambuDevice:connect()
  -- Se já existe um cliente, desconecta antes de reconectar (evita leaks)
  if self.client then
    pcall(function() self.client:disconnect() end)
    self.client = nil
  end

  local ip = self.ip or ""
  -- trim spaces and remove optional square brackets
  ip = ip:match("^%s*(.-)%s*$"):gsub("[%[%]]", "")

  local port = config.CONNECTION.PORT
  local pass = self.access_code
  local serial = self.serial

  if not (ip and port and pass and serial and ip ~= "" and ip ~= "192.168.1.x" and serial ~= "Serial") then
    self.device:emit_event(capabilities["schoolheart47510.printerStatus"].printStatusMessage("Config. Incomplete"))
    print("DEBUG: Config incompleta. IP:", ip, "Serial:", serial)
    return
  end

  local uri = string.format("%s:%s", ip, port)
  print("DEBUG: Tentando conectar. URI:", uri, "IP:", ip, "Port:", port)

  self.client = mqtt.client({
    uri = uri,
    clean = true,
    reconnect = true, -- Auto-reconnect
    keep_alive = 30, -- Keep connection alive
    id = serial,
    username = config.CONNECTION.USERNAME,
    password = pass,
    ssl_module = "cosock.ssl", -- Fix: Use cosock.ssl for cosock sockets
    secure = {
      mode = "client",
      protocol = "any", -- Fix: SmartThings cosock.ssl only supports "any"
      verify = "none",
      options = "all",
    }
  })
  
  self.client:on("connect", function()
    log.info("MQTT connected successfully!")
    self.device:online() -- Marca o dispositivo como Online
    self.device:online() -- Marca o dispositivo como Online
    
    -- Initialize printerControl state
    -- Use raw event to avoid dependency on capability object
    pcall(function()
        self.device:emit_event({
            attribute_id = "state",
            capability_id = "schoolheart47510.printerControl",
            component_id = "main",
            state = { value = "stop" }
        })
        -- Initialize printTimeDisplay
        self.device:emit_event({
            attribute_id = "totalTime",
            capability_id = "schoolheart47510.printTimeDisplay",
            component_id = "main",
            state = { value = "--" }
        })
        self.device:emit_event({
            attribute_id = "remainingTime",
            capability_id = "schoolheart47510.printTimeDisplay",
            component_id = "main",
            state = { value = "--" }
        })
    end)
    
    -- Inscreve no topico de report
    local topic_report = config.topics.report(serial)
    self.client:subscribe({topic = topic_report})
    
    -- Força a atualização de status (PUSH_ALL)
    local topic_request = config.topics.request(serial)
    local payload = json.encode(config.commands.PUSH_ALL)
    
    self.client:publish({
      topic = topic_request,
      payload = payload,
      qos = 0
    })
    log.info("Enviado comando PUSH_ALL para: " .. serial)
  end)



  self.client:on("message", function(msg)
    self:_handle_message(msg)
  end)
  
  self.client:on("error", function(err)
    log.error("Erro MQTT: " .. tostring(err))
    self.device:offline() -- Marca como offline em caso de erro
  end)

  self.device:emit_event(capabilities["schoolheart47510.printerStatus"].printStatusMessage("Connecting..."))

  -- Inicia o loop MQTT em uma thread separada (cosock)
  cosock.spawn(function()
    local client_ref = self.client
    while self.client == client_ref do
      log.info("Iniciando loop MQTT...")
      local ok, err = mqtt.run_sync(client_ref)
      
      if not ok then
        log.error("MQTT loop error: " .. tostring(err))
        self.device:offline()
      else
        log.info("MQTT loop finished normally")
      end
      
      if self.client ~= client_ref then
        log.info("Client changed, stopping old loop")
        break
      end
      
      log.info("Reconnecting in 10s...")
      cosock.socket.sleep(10)
    end
  end, "mqtt-loop-" .. serial)
end

function BambuDevice:_handle_message(msg)
    local payload = msg.payload
    local ok, data = pcall(json.decode, payload)
    if not ok or not data or not data.print then return end

    local print_data = data.print
    
    -- DEBUG: Log keys to understand what we are receiving
    local keys = ""
    for k, _ in pairs(print_data) do
        keys = keys .. k .. ","
    end
    log.info("DEBUG: Received keys: " .. keys)
    
    -- DEBUG LOGS
    if print_data.subtask_name then log.info("DEBUG: File Name received: " .. print_data.subtask_name) end
    if print_data.mc_remaining_time then log.info("DEBUG: Time Remaining received: " .. print_data.mc_remaining_time) end
    
    if print_data.gcode_state then
      self.last_gcode_state = print_data.gcode_state
    end

    if print_data.subtask_name then
      self.device:emit_event(capabilities["schoolheart47510.fileName"].fileName(print_data.subtask_name))
    end

    if print_data.mc_remaining_time then
      local minutes = print_data.mc_remaining_time
      local hours = math.floor(minutes / 60)
      local mins = minutes % 60
      local time_str = string.format("%dh %02dm", hours, mins)
      
          -- Emit to new printTimeDisplay capability
          local cap_time = capabilities["schoolheart47510.printTimeDisplay"]
          if cap_time then
              self.device:emit_component_event(self.device.profile.components.main, cap_time.remainingTime(time_str))
          else
              log.warn("Capability schoolheart47510.printTimeDisplay not found for remainingTime")
          end
          
          -- Calculate Total Time
          -- Ensure we have a valid percentage (from current message or cache)
          local percent = print_data.mc_percent
          if not percent and self.last_mc_percent then
              percent = self.last_mc_percent
          end
          
          if percent and percent > 0 then
              local total_minutes = math.floor(minutes / ((100 - percent) / 100))
              -- Avoid division by zero or huge numbers if percent is close to 100 but time is still high (edge case)
              if percent == 100 then total_minutes = minutes end -- Should be 0 remaining, but just in case
              
              local t_hours = math.floor(total_minutes / 60)
              local t_mins = total_minutes % 60
              local total_str = string.format("%dh %02dm", t_hours, t_mins)
              
              if cap_time then
                  self.device:emit_component_event(self.device.profile.components.main, cap_time.totalTime(total_str))
              end
          else
              -- If we can't calculate, just show remaining or "Calculating..."
              if cap_time then
                  self.device:emit_component_event(self.device.profile.components.main, cap_time.totalTime(time_str))
              end
          end
    end

    if print_data.cooling_fan_speed then
      local raw_speed = print_data.cooling_fan_speed
      log.info("DEBUG: Raw Fan Speed: " .. tostring(raw_speed))
      
      local speed = tonumber(raw_speed) or 0
      -- Bambu fan speed is often 0-15. Normalize to 0-100%
      if speed <= 15 and speed > 0 then
        speed = math.floor((speed / 15) * 100)
      elseif speed > 100 then
        speed = 100
      end
      self.device:emit_component_event(self.device.profile.components.others, capabilities["schoolheart47510.coolingFan"].coolingFan(tostring(speed)))
    end
    
    -- Parse Light Status
    if print_data.lights_report then
      if print_data.lights_report[1] and print_data.lights_report[1].node == "chamber_light" then
       local mode = print_data.lights_report[1].mode
       self.last_light_state = mode -- Cache state for toggle
       self.device:emit_component_event(self.device.profile.components.others, capabilities["schoolheart47510.bambuChamberLight"].lightState(mode))
      end
    end

    if print_data.bed_temper then
      self.last_bed_temper = print_data.bed_temper
      -- Restore Bed Component Event
      local bed_val = tonumber(print_data.bed_temper) or 0
      self.device:emit_component_event(self.device.profile.components.bed, capabilities.temperatureMeasurement.temperature({value = bed_val, unit = "C"}))
    end

    if print_data.mc_print_stage then
      self.last_mc_print_stage = tostring(print_data.mc_print_stage)
      self.last_stage_time = os.time()
    end

    -- Atualiza o status se tivermos informacao suficiente
    if self.last_gcode_state then
      local status = self.last_gcode_state
      
      -- Se o estado mudou (ex: de RUNNING para PAUSE), limpa o cache de estagio
       if status ~= "RUNNING" then
          self.last_mc_print_stage = nil
       end
       
       if status == "FINISH" then
          status = "FINISH" -- Ensure it matches the key in presentation
       end

       if status == "PAUSE" then
          -- Check if we have a specific active stage that overrides generic PAUSE (e.g. Calibration)
          if self.last_mc_print_stage and config.print_stages[self.last_mc_print_stage] then
              local stage_name = config.print_stages[self.last_mc_print_stage]
              -- If stage name contains "Pause", it's a real pause. Otherwise it might be calibration.
              if not string.find(string.lower(stage_name), "pause") then
                  status = "RUNNING" -- Treat as running so we fall into the detailed stage logic
              else
                  status = "PAUSE"
              end
          else
              status = "PAUSE"
          end
       end
       
       -- Check for explicit error code
       if print_data.print_error and tonumber(print_data.print_error) ~= 0 then
          status = "Error"
       end
      
      -- Se estiver imprimindo (RUNNING) e tiver um estagio detalhado (CACHEADO ou ATUAL), usa ele
      if status == "RUNNING" then
         status = "Printing" -- Map generic RUNNING to Printing
         
         -- Check cache validity (timeout 30s)
         if self.last_mc_print_stage then
            local now = os.time()
            if self.last_stage_time and (now - self.last_stage_time > 30) then
               self.last_mc_print_stage = nil -- Expire cache
            else
                local stage_id = self.last_mc_print_stage
                if config.print_stages[stage_id] then
                   status = config.print_stages[stage_id]
                end
            end
         end
      end
      
      -- Só emite evento se o status mudou para evitar spam
      if status ~= self.last_emitted_status then
        -- Emit detailed message to new capability (Safe check)
        if capabilities["schoolheart47510.statusMessage"] then
            self.device:emit_event(capabilities["schoolheart47510.statusMessage"].message(status))
        end
        
        self.last_emitted_status = status
        
        -- Emit simplified state
        local success, err = pcall(function()
            local simple_state = "idle"
            local safe_status = tostring(status or "")
            
            if safe_status == "Printing" or (self.last_mc_print_stage and config.print_stages[self.last_mc_print_stage] and safe_status ~= "Pause") then
                simple_state = "printing"
            elseif safe_status == "Error" then
                simple_state = "error"
            elseif safe_status == "FINISH" then
                simple_state = "finish"
            elseif safe_status == "Idle" or safe_status == "Offline" then
                simple_state = "idle"
            else
                -- Check for pause keywords in status string if it's a stage name
                if string.find(string.lower(safe_status), "pause") then
                    simple_state = "pause"
                else
                    simple_state = "printing" -- Default to printing if it's a stage like "Heating"
                end
            end
            
            -- Override simple state based on gcode_state if available and reliable
            if self.last_gcode_state == "PAUSE" then simple_state = "pause" end
            if self.last_gcode_state == "IDLE" and safe_status ~= "Offline" and safe_status ~= "Error" and safe_status ~= "FINISH" then simple_state = "idle" end
            
            -- Emit simplified state using capability object to avoid nil errors
            local cap = capabilities["schoolheart47510.printerStatus"]
            if not cap then
                log.warn("Capability schoolheart47510.printerStatus not found in st.capabilities")
            end

            if cap and cap.printState then
                self.device:emit_event(cap.printState(simple_state))
            else
                -- Fallback to raw event if capability object is not found (should not happen if profile is correct)
                local event = {
                    attribute_id = "printState",
                    capability_id = "schoolheart47510.printerStatus",
                    component_id = "main",
                    state = { value = simple_state }
                }
                self.device:emit_event(event)
            end

            -- Map simple_state to mediaPlayback status
            local playback_status = "stopped"
            local control_state = "stop"
            
            if simple_state == "printing" then
                playback_status = "playing"
                control_state = "resume"
            elseif simple_state == "pause" then
                playback_status = "paused"
                control_state = "pause"
            end
            
            log.info(string.format("DEBUG: Status Sync - Simple: %s, Control: %s", simple_state, control_state))
            
            self.device:emit_component_event(self.device.profile.components.others, capabilities.mediaPlayback.playbackStatus(playback_status))
            
            -- Sync printerControl state with actual status
            local cap_control = capabilities["schoolheart47510.printerControl"]
            if cap_control then
                self.device:emit_component_event(self.device.profile.components.main, cap_control.state(control_state))
            else
                log.warn("Capability schoolheart47510.printerControl not found for state sync")
            end
        end)
        
        if not success then
            log.error("Error emitting printState: " .. tostring(err))
        end
      end
    end
    if print_data.nozzle_temper then
        local nozzle_val = tonumber(print_data.nozzle_temper) or 0
        self.device:emit_component_event(self.device.profile.components.extruder, capabilities.temperatureMeasurement.temperature({value = nozzle_val, unit = "C"}))
    end

    if print_data.mc_percent then
        -- Se o progresso mudou, limpa o estagio cacheado para permitir que o status avance
        if self.last_mc_percent and print_data.mc_percent > self.last_mc_percent then
           self.last_mc_print_stage = nil
           -- Failsafe: If percent is increasing, we are definitely RUNNING
           if self.last_gcode_state == "PAUSE" or self.last_gcode_state == "IDLE" then
               self.last_gcode_state = "RUNNING"
               log.info("DEBUG: Failsafe triggered - Forced RUNNING state due to progress increase")
           end
        end
        self.last_mc_percent = print_data.mc_percent
        
        local cap = capabilities["schoolheart47510.printerProgress"]
        if cap and cap.percentComplete then
            self.device:emit_event(cap.percentComplete(print_data.mc_percent))
        else
             -- Fallback or log warning
             log.warn("Capability schoolheart47510.printerProgress not found")
        end
    end
end

function BambuDevice:send_message(payload)
  if self.client then
    local topic_request = config.topics.request(self.serial)
    local json_payload = json.encode(payload)
    self.client:publish({
      topic = topic_request,
      payload = json_payload,
      qos = 0
    })
  end
end

function BambuDevice:send_push_all()
    local payload = {
        pushing = {
            sequence_id = "0",
            command = "pushall",
            version = 1,
            push_target = 1
        }
    }
    self:send_message(payload)
end

function BambuDevice:handle_switch(command)
  log.info("DEBUG: handle_switch called with command: " .. tostring(command.command))
  local on = command.command == "on"
  if command.command == "toggle" then
    if self.last_light_state == "on" then on = false else on = true end
  elseif command.command == "setLight" then
    on = command.args.value == "on"
  end

  local mode = on and "on" or "off"
  
  -- Construct JSON payload for light control
  -- Fix: Pass table, not string, because send_message does json.encode
  local seq_id = tostring(os.time())
  local payload = {
      system = {
          sequence_id = seq_id,
          command = "ledctrl",
          led_node = "chamber_light",
          led_mode = mode,
          led_on_time = 500,
          led_off_time = 500,
          loop_times = 0,
          interval_time = 0
      }
  }
  
  log.info("DEBUG: Sending Light Payload: " .. json.encode(payload))
  self:send_message(payload)
  
  -- Optimistic Update: Emit event immediately
  self.device:emit_component_event(self.device.profile.components.others, capabilities["schoolheart47510.bambuChamberLight"].lightState(mode))
end

function BambuDevice:handle_printer_control(command)
  local cmd = command.command
  log.info("DEBUG: handle_printer_control called with command: " .. tostring(cmd))
  
  -- Commands match MQTT commands directly now: resume, pause, stop
  local mqtt_cmd = cmd
  
  -- Handle setControl command which comes with an argument
  if cmd == "setControl" then
      mqtt_cmd = command.args.mode
  end
  
  if mqtt_cmd == "resume" or mqtt_cmd == "pause" or mqtt_cmd == "stop" then
      -- Construct JSON payload for printer control
      -- Fix: Pass table, not string
      local seq_id = tostring(os.time())
      local payload = {
          print = {
              sequence_id = seq_id,
              command = mqtt_cmd
          }
      }
      
      log.info("DEBUG: Sending Printer Control Payload: " .. json.encode(payload))
      self:send_message(payload)
      
      -- Update state attribute to show action
      -- Emit the command itself as the state value to match presentation keys
      local state_val = mqtt_cmd
      
      local cap_control = capabilities["schoolheart47510.printerControl"]
      if cap_control then
          self.device:emit_component_event(self.device.profile.components.main, cap_control.state(state_val))
      else
          log.warn("Capability schoolheart47510.printerControl not found for command sync")
      end
  end
end

function BambuDevice:disconnect()
  if self.client then
    pcall(function() self.client:disconnect() end)
    self.client = nil
    self.device:offline() -- Marca como offline ao desconectar voluntariamente
  end
end

return BambuDevice
