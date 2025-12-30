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
  ["6"] = "Paused due to filament runout",
  ["7"] = "Heating Hotend",
  ["8"] = "Calibrating Extrusion",
  ["9"] = "Scanning Bed Surface",
  ["10"] = "Inspecting First Layer",
  ["11"] = "Identifying Build Plate Type",
  ["12"] = "Calibrating Micro Lidar",
  ["13"] = "Homing Toolhead",
  ["14"] = "Cleaning Nozzle Tip",
  ["15"] = "Checking Extruder Temperature",
  ["16"] = "Printing was paused by the user",
  ["17"] = "Pause of front cover falling",
  ["18"] = "Calibrating the micro lida",
  ["19"] = "Calibrating extrusion flow",
  ["20"] = "Paused due to nozzle temperature issue",
  ["21"] = "Paused due to heatbed temperature issue",
  ["22"] = "Filament unloading",
  ["23"] = "Skip Step Pause",
  ["24"] = "Filament loading",
  ["25"] = "Motor Noise Calibration",
  ["26"] = "Paused due to AMS lost",
  ["27"] = "Paused due to low speed of the fan",
  ["28"] = "Paused due to chamber temperature issue",
  ["29"] = "Cooling Chamber",
  ["30"] = "Paused by the Gcode",
  ["31"] = "Motor Noise Showoff",
  ["32"] = "Nozzle Filament Covered Detected Pause",
  ["33"] = "Cutter Error Pause",
  ["34"] = "First Layer Error Pause",
  ["35"] = "Nozzle Clog Pause"
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
  }
}

return Config
