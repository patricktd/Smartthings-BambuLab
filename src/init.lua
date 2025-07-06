local capabilities = require "st.capabilities"

-- Quando receber mensagem do Node-RED:
device:emit_event(
    capabilities["pattetech.status"].jobStatus("printing")
)
