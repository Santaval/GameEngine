local player_shooting_module = {}

player_bullet_damage = 20
player_fire_rate = 2
player_shoot_cooldown = 0


function player_shooting_module.shoot(player)
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
end

return player_shooting_module