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
      sequence_id = "0",
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
      command = "pause",
      param = ""
    }
  },
  RESUME = {
    print = {
      sequence_id = "2005",
      command = "resume",
      param = ""
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

-- CORES (Mapeamento Hex -> Emoji/Nome)
Config.COLORS = {
    -- Basic Colors
    ["FFFF00"] = "🟡", ["000000"] = "⚫", ["FFFFFF"] = "⚪", ["FF0000"] = "🔴",
    ["00FF00"] = "🟢", ["0000FF"] = "🔵", ["808080"] = "🔘", ["C0C0C0"] = "⚪",
    ["FFA500"] = "🟠", ["800080"] = "🟣", ["A52A2A"] = "🟤", ["161616"] = "⚫",
    ["101410"] = "⚫", -- Bambu Black
    
    -- Pinks & Purples
    ["FCECD6"] = "🟣", ["FF69B4"] = "🟣", ["FFC0CB"] = "🟣", ["6E3FA3"] = "🟣",
    ["EC008C"] = "🟣", ["AE96D4"] = "🟣", ["E8AFCF"] = "🟣", ["950051"] = "🟣",
    ["69398E"] = "🟣",

    -- Browns & Bronzes (Mapped to Brown Circle)
    ["84754E"] = "🟤", -- Bronze
    ["9D432C"] = "🟤", -- Brown
    ["D3B7A7"] = "🟤", -- Latte Brown
    ["AE835B"] = "🟤", -- Caramel
    ["B15533"] = "🟤", -- Terracotta
    ["7D6556"] = "🟤", -- Dark Brown
    ["4D3324"] = "🟤", -- Dark Chocolate
    ["5E4B3C"] = "🟤", -- Silk Copper
    ["C58957"] = "🟤", -- Generic Wood guess
    ["E8DBB7"] = "🟤", -- Desert Tan (Sand)
    ["F5F5DC"] = "🟤", -- Beige (Generic)
    ["E1C16E"] = "🟤", -- Brass/Sand-like
    ["D3C5A3"] = "🟤", -- Light Brown / Beige
    ["7C4B00"] = "🟤", -- Custom Brown

    -- Greens
    ["00AE42"] = "🟢", ["BECF00"] = "🟢", ["5C9748"] = "🟢", ["68724D"] = "🟢",
    ["61C680"] = "🟢", ["C2E189"] = "🟢", ["057748"] = "🟢",

    -- Blues
    ["003059"] = "🔵", ["0A2989"] = "🔵", ["0086D6"] = "🔵", ["00358E"] = "🔵",
    ["0056B8"] = "🔵", ["A3D8E1"] = "🔵", ["56B7E6"] = "🔵", ["0078BF"] = "🔵",
    ["042F56"] = "🔵", ["6E88BC"] = "🔵", ["2842AD"] = "🔵", ["147BD1"] = "🔵",
    ["2850E0"] = "🔵",

    -- Yellows & Oranges
    ["FFF144"] = "🟡", ["E4BD64"] = "🟡", ["FCE300"] = "🟡", ["F7D959"] = "🟡",
    ["FFC600"] = "🟡", ["FF6A13"] = "🟠", ["FF9016"] = "🟠", ["F99963"] = "🟠",

    -- Grays & Silvers
    ["8E9089"] = "🔘", ["A6A9AA"] = "🔘", ["545454"] = "🔘", ["CBC6B8"] = "🔘",
    ["9B9EA0"] = "🔘", ["757575"] = "🔘", ["4D5054"] = "🔘", ["97999B"] = "🔘",
    ["898989"] = "🔘",
    
    -- Reds
    ["C12E1F"] = "🔴", ["9D2235"] = "🔴", ["DE4343"] = "🔴", ["BB3D43"] = "🔴",
    ["951E23"] = "🔴", ["F72323"] = "🔴"
}

return Config
