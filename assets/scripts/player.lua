player_thrust = 50
player_rotation_delta = 5

function update()
  rotation_delta = 0
  accel_y = 0

  if is_action_activated("accelerate") then
    accel_y = accel_y + -1
    set_sprite(this, "spaceship-attack")
  end

  if is_action_activated("brake") then
    accel_y = accel_y + 1
  end

  if not is_action_activated("accelerate") then
    set_sprite(this, "spaceship-idle")
  end

  if is_action_activated("rotate_left") then
    rotation_delta = -1 * player_rotation_delta
  end

  if is_action_activated("rotate_right") then
    rotation_delta = player_rotation_delta
  end

  accel_y = accel_y * player_thrust

  set_acceleration(this, 0, accel_y)
  set_rotation(this, rotation_delta)
end
