-- Tecla 5 en la escena principal: abre el demo de walker (flanco de subida,
-- is_action_activated devuelve "mantenida").
local was_down = false
update = function()
  local down = is_action_activated("walkdemo")
  if down and not was_down then load_scene("scenes/walk_demo.lua") end
  was_down = down
end
