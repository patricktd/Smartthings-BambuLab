local Config = {}

-- CONSTANTES GERAIS
Config.CONNECTION = {
  PORT = 8883,
  USERNAME = "bblp",
  TLS_PROTOCOL = "tlsv1_2",
  TIMEOUT = 10
}

-- GERADORES DE TÓPICOS
Config.topics = {
  report  = function(serial) return "device/" .. serial .. "/report" end,
  request = function(serial) return "device/" .. serial .. "/request" end
}

-- ESTAGIOS DE IMPRESSAO (mc_print_stage)
Config.print_stages = {
  ["1"] = "Auto Bed Leveling",
  ["2"] = "Heatbed Preheating",
  ["3"] = "Sweeping XY Mech Mode",
  ["4"] = "Changing Filament",
  ["5"] = "M400 Pause",
  ["6"] = "Heating Hotend",
  ["7"] = "Calibration",
  ["8"] = "Homing",
  ["9"] = "Cleaning Nozzle",
  ["10"] = "Checking Extruder Temperature",
  ["11"] = "Checking Bed Height",
  ["12"] = "Loading Filament",
  ["13"] = "Unloading Filament",
  ["14"] = "Micro Lidar Calibration",
  ["15"] = "Homing Calibration",
  ["16"] = "Scanning First Layer",
  ["17"] = "Inspecting First Layer",
  ["18"] = "Identifying Filament",
  ["19"] = "Calibrating Flow Rate",
  ["20"] = "Nozzle Wipe",
  ["21"] = "Cooling Down",
  ["255"] = "Idle / Ready"
}

-- COMANDOS (Payloads JSON)
Config.commands = {
  -- Forçar atualização de status
  PUSH_ALL = {
    pushing = {
      sequence_id = "20002",
      command = "pushall",
      version = 1,
      push_target = 1
    }
  },
  -- Controle de Luz
  LIGHT_ON = {
    system = {
      sequence_id = "20006",
      command = "ledctrl",
      led_node = "chamber_light",
      led_mode = "on",
      led_on_time = 500, 
      led_off_time = 500, 
      loop_times = 0, 
      interval_time = 0
    }
  },
  LIGHT_OFF = {
    system = {
      sequence_id = "20007",
      command = "ledctrl",
      led_node = "chamber_light",
      led_mode = "off",
      led_on_time = 500, 
      led_off_time = 500, 
      loop_times = 0, 
      interval_time = 0
    }
  },
  PAUSE = {
    print = {
      sequence_id = "2004",
      command = "pause"
    }
  },
  RESUME = {
    print = {
      sequence_id = "2005",
      command = "resume"
    }
  },
  STOP = {
    print = {
      sequence_id = "2006",
      command = "stop",
      param = "" -- Required for some P1P/P1S firmwares
    }
  }
}

return Config
