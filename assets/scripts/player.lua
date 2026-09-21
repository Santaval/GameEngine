player_thrust = 50

function update()
  player_entity = this

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

  -- La nave siempre mira hacia el mouse
  local px_aim, py_aim = get_position(this)
  local mx, my = get_mouse_world_position()
  local target_rotation = math.atan(my - py_aim, mx - px_aim) + 1.5
  set_rotation_absolute(this, target_rotation)

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

  -- La cámara sigue a la nave
  local cam_x, cam_y = get_position(this)
  center_camera_on(cam_x, cam_y)
end
