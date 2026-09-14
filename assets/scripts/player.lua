player_thrust = 50
player_rotation_delta = 5

function update()
  player_entity = this

  rotation_delta = 0
  accel_y = 0

  if is_action_activated("accelerate") then
    accel_y = accel_y + -1
    set_sprite(this, "spaceship-movement")
  end

  if is_action_activated("shoot") then
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

  if is_action_activated("shoot") then
    local bullet = create_entity()
    local px, py = get_position(this)
    local rotation = get_rotation(this)

    -- La bala siempre sale hacia el frente de la nave
    local speed = 1000
    local b_vx = math.cos(rotation - 1.5) * speed
    local b_vy = math.sin(rotation - 1.5) * speed

    add_transform(bullet, px, py, 0.5, 0.5, rotation - 1.5)
    add_rigid_body(bullet, b_vx, b_vy, 0, 0)
    add_sprite(bullet, "bullet", 64, 32, 0, 192)
    add_animation(bullet, 8, 5, true)
    add_circle_collider(bullet, 30, 64, 32, this)
  end

  accel_y = accel_y * player_thrust

  set_acceleration(this, 0, accel_y)
  set_rotation(this, rotation_delta)
end
