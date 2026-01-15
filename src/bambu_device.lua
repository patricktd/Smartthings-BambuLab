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
  self.last_activity_time = os.time() -- Initialize activity time
  self.cache = {} -- Initialize cache for persistent data (AMS, etc)
  return self
end

function BambuDevice:connect()
  -- Se já existe um cliente, desconecta antes de reconectar (evita leaks)
  if self.client then
    pcall(function() self.client:disconnect() end)
    self.client = nil
  end
  
  -- Reset activity time to give a grace period for the new connection
  self.last_activity_time = os.time()

  local ip = self.ip or ""
  -- trim spaces and remove optional square brackets
  ip = ip:match("^%s*(.-)%s*$"):gsub("[%[%]]", "")

  local port = config.CONNECTION.PORT
  local pass = self.access_code
  local serial = self.serial



  -- Validation: Check for empty or default values
  local invalid_ip = (not ip) or (ip == "") or (ip == "192.168.1.x")
  local invalid_serial = (not serial) or (serial == "") or (serial == "Serial") or (serial == "000000000000000")
  local invalid_pass = (not pass) or (pass == "") or (pass == "00000000")

  if invalid_ip or invalid_serial or invalid_pass then
    self.device:emit_event(capabilities["schoolheart47510.statusMessage"].message("Error"))
    -- print("DEBUG: Config incompleta. IP:", ip, "Serial:", serial, "Access Code:", pass)
    return
  end

  local uri = string.format("%s:%s", ip, port)
  -- print("DEBUG: Tentando conectar. URI:", uri, "IP:", ip, "Port:", port)

  local client = mqtt.client({
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
  
  self.client = client
  
  client:on("connect", function()
    log.info("MQTT connected successfully!")
    self.device:online() -- Marca o dispositivo como Online
    
    -- Explicitly update Health Check capability
    if capabilities.healthCheck then
        self.device:emit_event(capabilities.healthCheck.healthStatus("online"))
    end
    
    -- Initialize printerControl state
    -- Use raw event to avoid dependency on capability object

    
    -- Inscreve no topico de report
    local topic_report = config.topics.report(serial)
    client:subscribe({topic = topic_report})
    
    -- Força a atualização de status (PUSH_ALL) com delay para garantir subscrição
    local topic_request = config.topics.request(serial)
    local payload = json.encode(config.commands.PUSH_ALL)
    
    cosock.spawn(function()
        cosock.socket.sleep(2)
        if self.client then
            log.info("DEBUG: Sending PUSH_ALL to topic: " .. tostring(topic_request))
            self.client:publish({
              topic = topic_request,
              payload = payload,
              qos = 0
            })
        end
    end)
    
    -- Start Watchdog Loop
    cosock.spawn(function()
        local client_ref = self.client
        while self.client == client_ref do
            local now = os.time()
            -- Increase timeout to 90s to be safe
            if self.last_activity_time and (now - self.last_activity_time > 90) then
                log.warn("WATCHDOG: No activity for 90s. Performing Hard Reconnect...")
                self.device:offline()
                if capabilities.healthCheck then
                    self.device:emit_event(capabilities.healthCheck.healthStatus("offline"))
                end
                self.last_activity_time = nil 
                
                -- Perform Hard Reconnect (Destroy and Recreate)
                self:reconnect_hard()
                break -- Exit this loop, new connect() will spawn new loops
            end
            cosock.socket.sleep(10)
        end
    end, "watchdog-" .. serial)
  end)



  self.client:on("message", function(msg)
    self:_handle_message(msg)
  end)
  
  self.client:on("error", function(err)
    log.error("Erro MQTT: " .. tostring(err))
    self.device:offline() -- Marca como offline em caso de erro
    if capabilities.healthCheck then
        self.device:emit_event(capabilities.healthCheck.healthStatus("offline"))
    end
  end)

  self.device:emit_event(capabilities["schoolheart47510.statusMessage"].message("Preparing"))

  -- Inicia o loop MQTT em uma thread separada (cosock)
  cosock.spawn(function()
    local client_ref = self.client
    while self.client == client_ref do
      log.info("Iniciando loop MQTT...")
      local ok, err = mqtt.run_sync(client_ref)
      
      if not ok then
        log.error("MQTT loop error: " .. tostring(err))
        self.device:offline()
        if capabilities.healthCheck then
            self.device:emit_event(capabilities.healthCheck.healthStatus("offline"))
        end
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
    self.last_activity_time = os.time() -- Update activity on any message
    
    -- Defensive check: Ensure cache exists
    if not self.cache then
        log.warn("CRITICAL: self.cache is nil in _handle_message. Re-initializing to prevent crash.")
        self.cache = {}
    end

    local payload = msg.payload
    local ok, data = pcall(json.decode, payload)
    if not ok or not data or not data.print then return end

    local print_data = data.print
    
    -- Cache Layer Info
    if print_data.layer_num then self.last_layer_num = print_data.layer_num end
    if print_data.total_layer_num then self.last_total_layer_num = print_data.total_layer_num end

    -- DEBUG: Log keys to understand what we are receiving
    -- local keys = ""
    -- for k, _ in pairs(print_data) do
    --     keys = keys .. k .. ","
    -- end
    -- log.debug("DEBUG: Received keys: " .. keys)
    
    if print_data.ams then
        -- log.debug("DEBUG: AMS data found in print_data!")
        
        -- Helper table for tray keys
        -- print_data.ams.ams_exist_bits: "1" usually implies AMS logic
        -- print_data.ams.tray_exist_bits: Binary string of exists trays
        -- print_data.ams.tray_now: active tray id
        -- print_data.ams.tray: array of tray objects
        
        local trays = print_data.ams.tray or {}
        
        if print_data.ams.ams_exist_bits == "1" then
            -- DEBUG: Dump AMS keys
            -- local ams_keys = ""
            -- for k,v in pairs(print_data.ams) do ams_keys = ams_keys .. k .. "=" .. tostring(v) .. " " end
            -- log.debug("DEBUG: AMS Keys: " .. ams_keys)

            if print_data.ams.ams then
                -- log.debug("DEBUG: AMS.ams array found with " .. #print_data.ams.ams .. " items")
            end
        end
    else
        -- Check if it's in the root data (unlikely but possible)
        if data.ams then
             -- log.debug("DEBUG: AMS data found in ROOT data!")
        end
    end
    
    -- DEBUG LOGS
    -- if print_data.subtask_name then log.debug("DEBUG: File Name received: " .. print_data.subtask_name) end
    -- if print_data.mc_remaining_time then log.debug("DEBUG: Time Remaining received: " .. print_data.mc_remaining_time) end
    
    if print_data.gcode_state then
      self.last_gcode_state = print_data.gcode_state
    end





    -- Consolidated Print Stats (Extended Display)
    if print_data.mc_remaining_time or print_data.layer_num or print_data.total_layer_num then
        -- Persist total layers if available
        if print_data.total_layer_num then
            self.last_total_layer_num = print_data.total_layer_num
        end
        
        -- Persist remaining time if available
        if print_data.mc_remaining_time then
            self.last_mc_remaining_time = print_data.mc_remaining_time
        end
        
        local cap_extended = capabilities["schoolheart47510.printDisplayExtended"]
        
        if cap_extended then
            local time_str = "--"
            local finish_str = "--"
            
            -- Use persisted time if available
            local minutes = print_data.mc_remaining_time or self.last_mc_remaining_time
            
            if minutes then
                local hours = math.floor(minutes / 60)
                local mins = minutes % 60
                time_str = string.format("%dh %02dm", hours, mins)
                
                -- Calculate Finish Time with Timezone Offset
                local now = os.time()
                local minutes_total = minutes * 60
                local offset = 0
                
                if self.device.preferences and self.device.preferences.timezoneOffset then
                    offset = self.device.preferences.timezoneOffset * 3600
                end
                
                local finish_time = now + minutes_total + offset
                finish_str = os.date("%H:%M", finish_time)
            end
            
            -- Persist current layer if available
            if print_data.layer_num then
                self.last_layer_num = print_data.layer_num
            end
            
            local layer_str = "--"
            -- Use persisted layer if available
            local current_layer = print_data.layer_num or self.last_layer_num
            
            if current_layer then
                 local total_layer = self.last_total_layer_num or print_data.total_layer_num or "?"
                 layer_str = string.format("%s/%s", current_layer, total_layer)
            end
            
            -- Emit Extended Stats
            if time_str ~= "--" and time_str ~= self.last_emitted_time_left then
                self.device:emit_component_event(self.device.profile.components.main, cap_extended.remainingTime(time_str))
                self.last_emitted_time_left = time_str
                
                -- Only update finish time if time left changed to avoid drift/jitter events
                self.device:emit_component_event(self.device.profile.components.main, cap_extended.finishTime(finish_str))
            end
            
            if layer_str ~= "--" and layer_str ~= self.last_emitted_layer_info then
                self.device:emit_component_event(self.device.profile.components.main, cap_extended.layerInfo(layer_str))
                self.last_emitted_layer_info = layer_str
            end
            
        else 
            -- Fallback for older profiles (shouldn't happen if deployed correctly)
             log.warn("Capability printDisplayExtended not found")
        end
    end

    -- Fan Speed Normalization Helper
    local function normalize_fan_speed(raw)
      local s = tonumber(raw) or 0
      
      -- DEBUG: Log raw fan inputs to track behavior on A1/P1S
      -- log.debug("DEBUG: Normalize Fan raw=" .. tostring(raw))
      
      if s <= 15 and s > 0 then return math.floor((s / 15) * 100) end
      if s > 100 then return 100 end
      return s
    end
    
    -- DEBUG: Log all fans if any is present
    -- if print_data.cooling_fan_speed or print_data.big_fan1_speed or print_data.big_fan2_speed then
    --     log.debug(string.format("DEBUG: Fans Report - Cool: %s, Aux: %s, Cham: %s", 
    --         tostring(print_data.cooling_fan_speed),
    --         tostring(print_data.big_fan1_speed),
    --         tostring(print_data.big_fan2_speed)))
    -- end

    -- Fan Speed Updates and Consolidation
    local fan_cap_id = "schoolheart47510.fansDisplayNum"
    
    local status, err = pcall(function()
        -- Debug Raw Input (Commented out for production, can uncomment if needed)
        -- log.debug("DEBUG: Checking Fan Keys: Cooling=" .. tostring(print_data.cooling_fan_speed) .. 
        --          " Aux=" .. tostring(print_data.big_fan1_speed) .. 
        --          " Cham=" .. tostring(print_data.big_fan2_speed) ..
        --          " Gear=" .. tostring(print_data.fan_gear))

        local component_others = self.device.profile.components.others
        if not component_others then
             return
        end
        
        local fan_cap = capabilities[fan_cap_id]
        if not fan_cap then
            log.warn("Fan capability not found in st.capabilities")
            return
        end

        -- Helper to get normalized value if key exists
        local c_val, a_val, ch_val
        
        if print_data.cooling_fan_speed then 
            c_val = normalize_fan_speed(print_data.cooling_fan_speed) 
        elseif print_data.fan_gear then
            c_val = normalize_fan_speed(print_data.fan_gear)
        end
        if print_data.big_fan1_speed then a_val = normalize_fan_speed(print_data.big_fan1_speed) end
        if print_data.big_fan2_speed then ch_val = normalize_fan_speed(print_data.big_fan2_speed) end

        -- Logic: If all 3 fans are reported and are identical, it's likely an A1 Mini 
        -- mirroring the values (since it lacks Aux/Chamber). Suppress them to 0.
        if c_val and a_val and ch_val then
            if c_val == a_val and a_val == ch_val and c_val > 0 then
                a_val = 0
                ch_val = 0
            end
        end

        if c_val and c_val ~= self.last_emitted_c_val then
          self.device:emit_component_event(component_others, fan_cap.coolingFanSpeed(c_val))
          self.last_emitted_c_val = c_val
        end
        if a_val and a_val ~= self.last_emitted_a_val then
           self.device:emit_component_event(component_others, fan_cap.auxFanSpeed(a_val))
           self.last_emitted_a_val = a_val
        end
        if ch_val and ch_val ~= self.last_emitted_ch_val then
           self.device:emit_component_event(component_others, fan_cap.chamberFanSpeed(ch_val))
           self.last_emitted_ch_val = ch_val
        end
    end)
    
    if not status then
        log.error("FAN UPDATE ERROR: " .. tostring(err))
    end
    
    -- Parse Light Status
    if print_data.lights_report then
      if print_data.lights_report[1] and print_data.lights_report[1].node == "chamber_light" then
       local mode = print_data.lights_report[1].mode
       self.last_light_state = mode -- Cache state for toggle
       
       local switch_state = "off"
       if mode == "on" then switch_state = "on" end
       
       if switch_state ~= self.last_emitted_light_state then
           if self.device.profile.components.light then
               self.device:emit_component_event(self.device.profile.components.light, capabilities.switch.switch(switch_state))
               self.last_emitted_light_state = switch_state
           end
       end
      end
    end



    -- Consolidated Temperatures

    if print_data.bed_temper or print_data.nozzle_temper then
        if print_data.bed_temper then self.last_bed_temper = print_data.bed_temper end
        if print_data.nozzle_temper then self.last_nozzle_temper = print_data.nozzle_temper end
        
        local bed_val = tonumber(self.last_bed_temper) or 0
        local nozzle_val = tonumber(self.last_nozzle_temper) or 0
        
        -- Emit to individual capabilities (now in Main)
        local cap_temp = capabilities["schoolheart47510.temperatures"]
        if cap_temp then
             if print_data.bed_temper then
                local rounded_bed = math.floor(bed_val * 10 + 0.5) / 10
                if rounded_bed ~= self.last_emitted_bed_temp then
                    self.device:emit_component_event(self.device.profile.components.main, cap_temp.bedTemp(rounded_bed))
                    self.last_emitted_bed_temp = rounded_bed
                end
             end
             if print_data.nozzle_temper then
                local rounded_nozzle = math.floor(nozzle_val * 10 + 0.5) / 10
                if rounded_nozzle ~= self.last_emitted_nozzle_temp then
                    self.device:emit_component_event(self.device.profile.components.main, cap_temp.extruderTemp(rounded_nozzle))
                    self.last_emitted_nozzle_temp = rounded_nozzle
                end
             end
        end
        

    end

    if print_data.mc_print_stage then
      local new_stage = tostring(print_data.mc_print_stage)
      
      -- TRIGGER: Force refresh (Pull data) when entering "Heatbed Preheating" (Stage 2)
      -- This ensures we get updated AMS/Filament color data at the start of a print
      if new_stage == "2" and self.last_mc_print_stage ~= "2" then
          log.info("Detected Heatbed Preheating. Forcing full status refresh to pull colors...")
          -- Use pcall to avoid crashing if send_push_all fails
          pcall(function() self:send_push_all() end)
      end
      
      self.last_mc_print_stage = new_stage
    end

    if print_data.subtask_name then
      -- Fix: Emit to others component
      if capabilities["schoolheart47510.fileName"] then
          self.device:emit_component_event(self.device.profile.components.others, capabilities["schoolheart47510.fileName"].fileName(print_data.subtask_name))
      end
    end

     -- Atualiza o status se tivermos informacao suficiente
    -- DEBUG: Track state reception
    if print_data.gcode_state then
        log.debug("DEBUG: Received gcode_state: " .. tostring(print_data.gcode_state))
    end
    if print_data.mc_print_stage then
        log.debug("DEBUG: Received mc_print_stage: " .. tostring(print_data.mc_print_stage))
    end

    if self.last_gcode_state then
      local status = self.last_gcode_state
      -- DEBUG: Internal status calculation trace
      local raw_status = status
      
      local stage_str = nil

      -- Priority Logic: Use mc_print_stage only if gcode_state is RUNNING or PREPARE
      if status == "RUNNING" or status == "PREPARE" then
          if self.last_mc_print_stage then
             local stage_id = tostring(self.last_mc_print_stage)
             if config.print_stages[stage_id] then
                stage_str = config.print_stages[stage_id]
             end
          end
      end

      -- If we have a specific stage string, use it. Otherwise map gcode_state.
      if stage_str then
          status = stage_str
      else
          
          -- Map key states to user-friendly strings (or keep raw if not found)
          if status == "IDLE" then status = "Idle"
          elseif status == "RUNNING" then status = "Printing" -- Restored to generic Printing
          elseif status == "PREPARE" then status = "Preparing"
          elseif status == "PAUSE" then status = "Paused"
          elseif status == "FINISH" then status = "Finished"
          elseif status == "FAILED" then status = "Failed"
          elseif status == "OFFLINE" then status = "Offline"
          end
      end
      
      -- Empty check
      if not status or status == "" then status = "Idle" end
      
      -- Prepare messages
      local enum_message = status -- This holds the "Enum" value (e.g. Printing, Idle)
      local display_message = status -- Default to same as enum
        
      -- Override display message for Printing with Layer info
      if status == "Printing" and self.last_layer_num and self.last_total_layer_num then
          display_message = string.format("Layer %s/%s", self.last_layer_num, self.last_total_layer_num)
      end
      
      -- Emit if Status changed
      -- CRITICAL FIX: Force update if last status is nil (first run) or changed
      if status ~= self.last_emitted_status then
      
        local cap_status_msg = capabilities["schoolheart47510.statusMessage"]
        if cap_status_msg then
            -- Emit Enum Message (for Automation and Display)
            self.device:emit_event(cap_status_msg.message(enum_message))
            log.debug("DEBUG: Emitting Status Message: " .. tostring(enum_message))
        else
            log.warn("Capability schoolheart47510.statusMessage not found!")
        end
        
        self.last_emitted_status = status
        
        -- Emit to Extended Display
        if cap_extended then
             self.device:emit_component_event(self.device.profile.components.main, cap_extended.printStatus(status))
        end
        
         -- Restore Macro Printer Status
         if capabilities["schoolheart47510.printerStatus"] then
             local macro_state = "printing" -- Default assumption: If we have a status, we are doing something active
             
             if status == "Idle" or status == "Offline" or status == "" then
                macro_state = "idle"
             elseif status == "Paused" then
                macro_state = "pause"
             elseif status == "Finished" then
                macro_state = "finish"
             elseif status == "Failed" or status == "Error" then
                macro_state = "error"
             end
             
             -- DEBUG: Log the transition
             if self.last_emitted_macro ~= macro_state then
                 log.info(string.format("DEBUG: Macro Status Logic - Input: '%s' -> Output: '%s'", tostring(status), macro_state))
                 self.device:emit_component_event(self.device.profile.components.main, capabilities["schoolheart47510.printerStatus"].printState(macro_state))
                 self.last_emitted_macro = macro_state
             end
         end
        
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
            -- Calculate control_state based on simple_state
            local control_state = "stop"
            if simple_state == "printing" then
                control_state = "resume"
            elseif simple_state == "pause" then
                control_state = "pause"
            end
            
            -- Sync printerControl state with actual status
            local cap_control = capabilities["schoolheart47510.printerControl"]
            if cap_control then
                self.device:emit_component_event(self.device.profile.components.others, cap_control.state(control_state))
            else
                log.warn("Capability schoolheart47510.printerControl not found for state sync")
            end
        end)
        
        if not success then
            log.error("Error syncing printerControl: " .. tostring(err))
        end
      end -- Close 'if status ~= self.last_emitted_status'
    end -- Close 'if self.last_gcode_state'

    -- Nozzle temp handled in consolidated block above
    if print_data.nozzle_temper then
         -- Just update cache if needed, but main logic is above
         self.last_nozzle_temper = print_data.nozzle_temper
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

    -- AMS Info Parsing
    -- Check for AMS presence using ams_exist_bits
    -- Update cache if present
    if print_data.ams and print_data.ams.ams_exist_bits then
        self.cache.ams_exist_bits = print_data.ams.ams_exist_bits
        -- log.info("DEBUG: ams_exist_bits (new) = " .. tostring(self.cache.ams_exist_bits))
    end
    
    local ams_exists = false
    -- Use cached value if available
    if self.cache.ams_exist_bits then
        if self.cache.ams_exist_bits ~= "0" then
            ams_exists = true
        end
    end
    
    -- Update vt_tray cache if present
    if print_data.vt_tray then
        self.cache.vt_tray = print_data.vt_tray
        -- log.info("DEBUG: vt_tray (new) found. Type: " .. tostring(print_data.vt_tray.tray_type))
    end
    
    -- Use cached vt_tray for display
    local vt_tray = self.cache.vt_tray
    
    if vt_tray then
        -- log.info("DEBUG: Using cached vt_tray")
    else
        -- log.info("DEBUG: vt_tray is NIL (and no cache)")
    end
    
    -- Color Map removed (Moved to config.lua)
    
    local function format_tray(tray)
        if not tray then return "Empty" end
        local type = tray.tray_sub_brands
        if not type or type == "" then type = tray.tray_type or "Unknown" end
        if type == "Unknown" then return "Empty" end
        
        local color_hex = tray.tray_color or ""
        if #color_hex > 6 then color_hex = color_hex:sub(1, 6) end
        
        local upper_hex = string.upper(color_hex)
        -- Access color definition from config
        local color_emoji = config.COLORS[upper_hex]
        
        if not color_emoji then
            log.warn("Unknown Color Hex received: " .. tostring(upper_hex))
            color_emoji = "⚪"
        end
        
        return string.format("%s %s", type, color_emoji)
    end

    if ams_exists then
        -- AMS LOGIC
        if print_data.ams and print_data.ams.ams and print_data.ams.ams[1] then
            local ams_data = print_data.ams.ams[1]
            
            -- Cache trays if present (FULL UPDATE)
            if ams_data.tray then
                self.cache.trays = ams_data.tray
            end
            
            -- Use cached trays if current is empty (PARTIAL UPDATE)
            local trays = ams_data.tray or self.cache.trays or {}
            
            -- Check for AMS Lite vs Standard (Humidity check)
            local humidity = ams_data.humidity
            
            -- Cache the active tray ID early for slot highlighting
            if print_data.ams.tray_now then
                self.cache.tray_now = print_data.ams.tray_now
            end
            local active_tray_id = self.cache.tray_now

            if capabilities["schoolheart47510.amsSlots"] then
                local cap_slots = capabilities["schoolheart47510.amsSlots"]
                local slot_map = { ["0"] = "slotA", ["1"] = "slotB", ["2"] = "slotC", ["3"] = "slotD" }
                
                for i = 0, 3 do
                    local slot_id = tostring(i)
                    local attr_name = slot_map[slot_id]
                    local tray_found = nil
                    
                    for _, tray in pairs(trays) do
                        if tostring(tray.id) == slot_id then
                            tray_found = tray
                            break
                        end
                    end
                    
                    local slot_val = format_tray(tray_found)
                    
                    -- Highlight Active Slot
                    if active_tray_id and tostring(active_tray_id) == slot_id then
                         slot_val = "➡️ " .. slot_val
                    end

                    if attr_name and cap_slots[attr_name] then
                        self.device:emit_component_event(self.device.profile.components.others, cap_slots[attr_name]({value = slot_val}))
                    end
                end
            end
        end
    else
        -- NO AMS LOGIC (External Spool)
        -- Use vt_tray (already retrieved from cache above)
        
        if capabilities["schoolheart47510.amsSlots"] then
            local cap_slots = capabilities["schoolheart47510.amsSlots"]
            
            -- Slot A = External Spool
            local ext_val = "Empty"
            if vt_tray then
                -- vt_tray structure is similar to tray but might lack id
                ext_val = format_tray(vt_tray)
                if ext_val ~= "Empty" then
                    ext_val = "Ext: " .. ext_val
                end
            end
            
            self.device:emit_component_event(self.device.profile.components.others, cap_slots.slotA({value = ext_val}))
            
            -- Clear other slots
            self.device:emit_component_event(self.device.profile.components.others, cap_slots.slotB({value = "-"}))
            self.device:emit_component_event(self.device.profile.components.others, cap_slots.slotC({value = "-"}))
            self.device:emit_component_event(self.device.profile.components.others, cap_slots.slotD({value = "-"}))
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
    local state = command.command
    local mode = "off"
    if state == "on" then mode = "on" end
    
    log.info("Switch command received: " .. state)
    
    local start_mode = mode
    if self.device.profile.components.light then
        self.device:emit_component_event(self.device.profile.components.light, capabilities.switch.switch(start_mode))
        self.last_emitted_light_state = start_mode
    end

    local payload = {
        system = {
            sequence_id = "2003",
            command = "ledctrl",
            led_node = "chamber_light",
            led_mode = mode,
            led_on_time = 500,
            led_off_time = 500,
            loop_times = 0,
            interval_time = 0
        }
    }
    self:send_message(payload)
end

function BambuDevice:handle_refresh()
    log.info("Refresh command received")
    
    -- Force status update on next message
    self.last_emitted_status = nil
    
    -- Request full status update
    local payload = {
        pushing = {
            sequence_id = "2004",
            command = "pushall"
        }
    }
    self:send_message(payload)
end

function BambuDevice:init()
    -- Register capability handlers
    self.device:set_field("bambu_device", self)
    
    -- Standard Switch Handler
    self.device:register_capability_listener(capabilities.switch, {
        on = function(device, command)
            self:handle_switch(command)
        end,
        off = function(device, command)
            self:handle_switch(command)
        end
    })
end


function BambuDevice:handle_aux_fan_speed(speed_percent)
  log.info("Setting Aux Fan Speed: " .. tostring(speed_percent) .. "%")
  
  -- Prevent nil or invalid range
  local p = tonumber(speed_percent) or 0
  if p < 0 then p = 0 end
  if p > 100 then p = 100 end
  
  -- Convert 0-100% to 0-255 PWM
  local pwm_value = math.floor((p / 100) * 255)
  
  -- Construct G-code payload
  -- M106 P2 S<pwm> is standard for Aux Fan on Bambu
  local gcode_cmd = "M106 P2 S" .. pwm_value
  
  local payload = {
    print = {
      sequence_id = tostring(os.time()),
      command = "gcode_line",
      param = gcode_cmd
    }
  }
  
  self:send_message(payload)
end

function BambuDevice:disconnect(skip_offline)
  if self.client then
    log.info("Disconnecting client...")
    pcall(function() self.client:disconnect() end)
    self.client = nil
    
    if not skip_offline then
        self.device:offline() -- Marca como offline ao desconectar voluntariamente
        if capabilities.healthCheck then
            self.device:emit_event(capabilities.healthCheck.healthStatus("offline"))
        end
    end
  end
end

function BambuDevice:reconnect_hard()
    log.warn("Executing Hard Reconnect Sequence...")
    self:disconnect()
    
    -- Wait a bit to ensure sockets are closed and loops exit
    cosock.socket.sleep(2)
    
    log.info("Re-initializing connection...")
    self:connect()
end

function BambuDevice:check_connection()
    -- Called periodically by the driver to ensure we are not stuck
    local now = os.time()
    local last = self.last_activity_time or now -- If nil, assume now (grace period)
    
    -- If no activity for 3 minutes (180s), force a hard reconnect
    -- This catches cases where the printer was off for a long time and the internal loop gave up or got stuck
    if (now - last > 180) then
         log.warn("HEALTH CHECK: No activity for 180s. Forcing Hard Reconnect.")
         self:reconnect_hard()
         -- Reset time to prevent immediate loop (reconnect_hard does this via connect, but being safe)
         self.last_activity_time = nil
    end
end

return BambuDevice
