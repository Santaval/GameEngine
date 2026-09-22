player_thrust = 100
player_bullet_damage = 20
player_fire_rate = 3

player_shoot_cooldown = 0


function update()
  player_entity = this

  accel_y = 0

  if is_action_activated("accelerate") then
    accel_y = accel_y + -1
    set_sprite(this, "spaceship-movement")
  end

  if is_action_activated("shoot") then
    -- set_sprite(this, "spaceship-attack")
  end

  if is_action_activated("brake") then
    accel_y = accel_y + 1
  end

  -- "T" activa/desactiva la línea de trayectoria. is_action_activated
  -- reporta la tecla sostenida, no un flanco, así que hay que detectar el
  -- flanco a mano con un global (los globals de scripts se comparten entre
  -- archivos, de ahí el prefijo player_).
  local path_key_down = is_action_activated("toggle_path")
  if path_key_down and not player_path_key_was_down then
    set_path_active(this, not is_path_active(this))
  end
  player_path_key_was_down = path_key_down

  -- "C" activa/desactiva el overlay de hitboxes, mismo patrón de flanco
  local collider_key_down = is_action_activated("toggle_colliders")
  if collider_key_down and not player_collider_key_was_down then
    toggle_colliders()
  end
  player_collider_key_was_down = collider_key_down

  if not is_action_activated("accelerate") then
    set_sprite(this, "spaceship-idle")
  end

  -- La nave siempre mira hacia el mouse
  local px_aim, py_aim = get_position(this)
  local mx, my = get_mouse_world_position()
  local target_rotation = math.atan(my - py_aim, mx - px_aim) + 1.5
  set_rotation_absolute(this, target_rotation)


  if is_action_activated("shoot") and player_shoot_cooldown <= 0 then
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
    -- true = la bala se destruye al impactar contra algo que tenga vida
    add_damage(bullet, player_bullet_damage, true)

    player_shoot_cooldown = 1 / player_fire_rate

  else 
    player_shoot_cooldown = player_shoot_cooldown - get_delta_time()
  end

  accel_y = accel_y * player_thrust

  set_acceleration(this, 0, accel_y)

  -- La cámara sigue a la nave
  local cam_x, cam_y = get_position(this)
  center_camera_on(cam_x, cam_y)

  -- HUD de debug: se vuelve a pedir cada frame
  local vx, vy = get_velocity(this)
  local speed = math.sqrt(vx * vx + vy * vy)
  local dt = get_delta_time()

  draw_text(20, 20, string.format("Pos:   %8.1f , %8.1f", cam_x, cam_y), "default", 255, 255, 255)
  draw_text(20, 42, string.format("Vel:   %8.1f , %8.1f", vx, vy), "default", 120, 220, 255)
  draw_text(20, 64, string.format("Speed: %8.1f", speed), "default", 120, 220, 255)
  draw_text(20, 86, string.format("Rot:   %8.2f", get_rotation(this)), "default", 200, 200, 120)
  draw_text(20, 108, string.format("FPS:   %8.0f", 1.0 / math.max(dt, 0.0001)), "default", 200, 200, 120)

  -- La barra de vida se pone roja por debajo de un tercio
  local hp, hp_max = get_health(this), get_max_health(this)
  local hp_g = hp * 3 >= hp_max and 220 or 60
  draw_text(20, 130, string.format("HP:    %8d / %d", hp, hp_max), "default", 255, hp_g, 60)

  -- Etiqueta en coordenadas del mundo: sigue a la nave
  
  draw_text_world(cam_x - 30, cam_y - 60, "PLAYER", "default", 255, 200, 0)

  if not hud_probe_done then
    hud_probe_done = true
    print("[PROBE] HUD reached end of update, speed=" .. speed)
  end
end

-- Hooks opcionales: el motor los llama solo si el script los define, con la
-- entidad afectada en "this"

function on_damage(amount, source)
  print(string.format("[player] -%d HP (quedan %d)", amount, get_health(this)))
end

function on_death()
  print("[player] nave destruida")
end
