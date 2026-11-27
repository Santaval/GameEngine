-- Tecla 7 en la escena principal: continua la partida guardada (issue #52). Flanco de
-- subida, como las demas teclas de lanzamiento.
local save = require("save")
local was_down = false
update = function()
  local down = is_action_activated("continue")
  if down and not was_down then
    local scene, err = save.load()
    if scene then
      load_scene(scene)
    else
      print("[save] no se puede continuar: " .. tostring(err))
    end
  end
  was_down = down
end
