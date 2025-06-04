-- src/utils.lua
local M = {}

function M.parse_json_safely(json_string)
    if not json_string or json_string == "" then return nil, "JSON string is nil or empty" end
    local dkjson = require "dkjson" -- Certifique-se que esta biblioteca está disponível no ambiente Edge
    if not dkjson then
        require("log").error("UTILS: Biblioteca dkjson não encontrada.")
        return nil, "dkjson library not found"
    end
    local success, result = pcall(dkjson.decode, json_string)
    if success then
        return result
    else
        require("log").error("UTILS: Falha ao fazer parse do JSON: " .. tostring(result))
        return nil, "JSON parse error: " .. tostring(result)
    end
end

-- Exemplo de como usar stringify_table de st.utils se precisar de uma string
-- function M.format_hms_messages(hms_table)
--    if not hms_table or #hms_table == 0 then return "No HMS messages" end
--    return require("st.utils").stringify_table(hms_table) -- Exemplo
-- end

return M

