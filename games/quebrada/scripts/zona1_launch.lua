-- Tecla z en la escena principal: reinicia la zona 1 con el atajo (issue #78; flanco de subida).
local ws = require("world_state")
local was_down = false
update = function()
  local down = is_action_activated("zona1")
  if down and not was_down then
    ws.set("zona1.demo_start", true)
    load_scene("scenes/main.lua")
  end
  was_down = down
end
