-- src/utils.lua
local log = require "log"
local dkjson_lib = require "dkjson" -- Certifique-se que esta biblioteca está disponível no ambiente Edge

local Utils = {}

-- Função para fazer parse de JSON de forma segura, retornando nil em caso de erro.
-- Útil para evitar que o driver falhe se receber um JSON malformado.
function Utils.parse_json_safely(json_string)
    if not json_string or json_string == "" then
        log.warn("UTILS: Tentativa de fazer parse de JSON string vazia ou nula.")
        return nil, "JSON string is nil or empty"
    end
    
    if not dkjson_lib then
        log.error("UTILS: Biblioteca dkjson não foi carregada ou não está disponível.")
        return nil, "dkjson library not found"
    end

    local success, result_or_error_msg = pcall(dkjson_lib.decode, json_string)
    
    if success then
        return result_or_error_msg -- Retorna a tabela Lua parseada
    else
        log.error(string.format("UTILS: Falha ao fazer parse do JSON: %s. String JSON original: %s", tostring(result_or_error_msg), json_string))
        return nil, "JSON parse error: " .. tostring(result_or_error_msg)
    end
end

-- Exemplo de outra função utilitária que poderia ser útil:
-- Formatar mensagens HMS (Health Management System) para exibição
function Utils.format_hms_messages_for_display(hms_table)
    if not hms_table or type(hms_table) ~= "table" or #hms_table == 0 then
        return "Sem mensagens HMS" -- Ou uma string vazia, conforme preferir
    end

    local formatted_messages = {}
    for i, hms_entry in ipairs(hms_table) do
        -- A estrutura exata de hms_entry depende do que a impressora envia.
        -- Supondo que tenha 'attr' (código do atributo) e 'code' (código do erro)
        -- e talvez uma descrição em 'desc'.
        if hms_entry.attr and hms_entry.code then
            -- Exemplo: "HMS 0700_2000_0001_0004: Código 03000201"
            -- Você pode querer mapear estes códigos para mensagens mais amigáveis.
            local msg = string.format("HMS %s: Código %s", tostring(hms_entry.attr), tostring(hms_entry.code))
            table.insert(formatted_messages, msg)
        elseif type(hms_entry) == "string" then -- Se já for uma string
             table.insert(formatted_messages, hms_entry)
        end
    end

    if #formatted_messages == 0 then
        return "Sem mensagens HMS"
    end
    
    return table.concat(formatted_messages, "; ") -- Separar múltiplas mensagens com ponto e vírgula
end


-- Pode adicionar mais funções utilitárias aqui conforme necessário.
-- Por exemplo, para converter unidades, validar dados, etc.

return Utils