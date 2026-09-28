local player_visual_helpers_module = {}

-- is_action_activated reporta la tecla sostenida, no un flanco, asi que el
-- flanco se detecta a mano guardando el estado del frame anterior
local path_key_was_down = false
local collider_key_was_down = false

-- "T" activa/desactiva la linea de trayectoria
function player_visual_helpers_module.toggle_path(entity)
  local path_key_down = is_action_activated("toggle_path")
  if path_key_down and not path_key_was_down then
    set_path_active(entity, not is_path_active(entity))
  end
  path_key_was_down = path_key_down
end

-- "C" activa/desactiva el overlay de hitboxes
function player_visual_helpers_module.toggle_colliders()
  local collider_key_down = is_action_activated("toggle_colliders")
  if collider_key_down and not collider_key_was_down then
    toggle_colliders()
  end
  collider_key_was_down = collider_key_down
end

function player_visual_helpers_module.update(entity)
  player_visual_helpers_module.toggle_path(entity)
  player_visual_helpers_module.toggle_colliders()
end

return player_visual_helpers_module
