-- Tecla 9 en la escena principal: abre el demo de edificios (issue #71; flanco de subida).
local was_down = false
update = function()
  local down = is_action_activated("buildingsdemo")
  if down and not was_down then load_scene("scenes/buildings_demo.lua") end
  was_down = down
end
