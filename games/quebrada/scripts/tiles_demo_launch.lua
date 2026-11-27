-- Tecla 8 en la escena principal: abre el demo del tileset (issue #55; flanco de subida).
local was_down = false
update = function()
  local down = is_action_activated("tilesdemo")
  if down and not was_down then load_scene("scenes/tiles_demo.lua") end
  was_down = down
end
