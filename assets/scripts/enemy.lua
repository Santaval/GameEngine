enemy_thrust = 40
enemy_turn_speed = 3
enemy_bullet_damage = 15
shoot_cooldown = 1.2
shoot_timer = shoot_cooldown

function update()
  -- Espera a que el jugador haya corrido al menos un frame de su script
  if player_entity == nil then return end

  local dt = get_delta_time()

  local ex, ey = get_position(this)
  local px, py = get_position(player_entity)

  local dx = px - ex
  local dy = py - ey

  -- Misma convención que player.lua: el frente de la nave apunta a (rotation - 1.5)
  local angle_to_player = math.atan(dy, dx)
  local target_rotation = angle_to_player + 1.5

  local rotation = get_rotation(this)
  local diff = target_rotation - rotation

  while diff > math.pi do diff = diff - 2 * math.pi end
  while diff < -math.pi do diff = diff + 2 * math.pi end

  set_rotation(this, diff * enemy_turn_speed)
  set_acceleration(this, 0, -enemy_thrust)

  shoot_timer = shoot_timer - dt
  if shoot_timer <= 0 then
    shoot_timer = shoot_cooldown

    local fire_rotation = get_rotation(this)
    local speed = 700
    local b_vx = math.cos(fire_rotation - 1.5) * speed
    local b_vy = math.sin(fire_rotation - 1.5) * speed

    local bullet = create_entity()
    add_transform(bullet, ex, ey, 0.5, 0.5, fire_rotation - 1.5)
    add_rigid_body(bullet, b_vx, b_vy, 0, 0)
    add_sprite(bullet, "bullet", 64, 32, 0, 192)
    add_animation(bullet, 8, 5, true)
    add_circle_collider(bullet, 30, 64, 32, this)
    add_damage(bullet, enemy_bullet_damage, true)
  end
end
