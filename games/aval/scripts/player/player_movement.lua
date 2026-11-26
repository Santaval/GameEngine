local player_movement_module = {}

player_movement_module.thrust = 100

-- Offset entre el angulo del sprite (mira hacia arriba) y el eje X del mundo
player_movement_module.SPRITE_ROTATION_OFFSET = 1.5

-- Empuje vertical segun las acciones: -1 acelera, +1 frena, 0 nada. Tambien
-- cambia el sprite, asi que se llama una vez por frame.
local function read_thrust_input(entity)
  local accel_y = 0

  if is_action_activated("accelerate") then
    accel_y = accel_y - 1
    set_sprite(entity, "spaceship-movement")
  else
    set_sprite(entity, "spaceship-idle")
  end

  if is_action_activated("brake") then
    accel_y = accel_y + 1
  end

  return accel_y
end

function player_movement_module.update_thrust(entity)
  local accel_y = read_thrust_input(entity) * player_movement_module.thrust
  set_acceleration(entity, 0, accel_y)
end

-- La nave siempre mira hacia el mouse
function player_movement_module.face_mouse(entity)
  local px, py = get_position(entity)
  local mx, my = get_mouse_world_position()
  local target_rotation = math.atan(my - py, mx - px) + player_movement_module.SPRITE_ROTATION_OFFSET
  set_rotation_absolute(entity, target_rotation)
end

return player_movement_module
