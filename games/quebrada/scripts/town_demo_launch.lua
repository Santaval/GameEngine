-- Tecla 6 en la escena principal: abre el demo de puertas y zonas (flanco de
-- subida, is_action_activated devuelve "mantenida").
local was_down = false
update = function()
  local down = is_action_activated("towndemo")
  if down and not was_down then load_scene("scenes/town_demo.lua") end
  was_down = down
end
