local player_movement_module = require("player_movement")
local bullet_lifetime = require("bullet_lifetime")

local player_shooting_module = {}

player_shooting_module.bullet_damage = 20
player_shooting_module.bullet_speed = 1000
player_shooting_module.fire_rate = 2

local shoot_cooldown = 0

local function spawn_bullet(owner)
  local bullet = create_entity()
  local px, py = get_position(owner)

  -- La bala siempre sale hacia el frente de la nave
  local direction = get_rotation(owner) - player_movement_module.SPRITE_ROTATION_OFFSET
  local speed = player_shooting_module.bullet_speed
  local b_vx = math.cos(direction) * speed
  local b_vy = math.sin(direction) * speed

  add_transform(bullet, px, py, 0.5, 0.5, direction)
  add_rigid_body(bullet, b_vx, b_vy, 0, 0)
  add_gravity(bullet, 1, false, true)
  add_sprite(bullet, "bullet", 64, 32, 0, 192)
  add_animation(bullet, 8, 5, true)
  add_circle_collider(bullet, 30, 64, 32, owner)
  -- destroy_on_hit = true: la bala se destruye al impactar contra algo que tenga vida
  -- player = true: es un arma de jugador (respeta la regla de pvp)
  add_damage(bullet, player_shooting_module.bullet_damage, true, true)
  -- La bala expira sola a los 2 s (online, en cada cliente por separado)
  add_script(bullet, bullet_lifetime.make_update())

  -- Disparar cancela el escudo de aparicion (#28, lo define map_spawn.lua)
  if get_shield(owner) > 0 then
    set_shield(owner, 0)
    if spawn_shield_cancelled ~= nil then spawn_shield_cancelled() end
  end

  -- Online: la bala es mia y los demas crean una replica con "fire"
  local shooter_id = get_net_id(owner)
  if net_is_online() and shooter_id then
    local bullet_id = net_register(bullet)
    net_send("fire", {
      bulletNetId = bullet_id,
      shooterNetId = shooter_id,
      pos = { x = px, y = py },
      vel = { x = b_vx, y = b_vy },
      dmg = player_shooting_module.bullet_damage,
    })
  end
end

function player_shooting_module.update(entity)
  if is_action_activated("shoot") and shoot_cooldown <= 0 then
    spawn_bullet(entity)
    shoot_cooldown = 1 / player_shooting_module.fire_rate
  else
    shoot_cooldown = shoot_cooldown - get_delta_time()
  end
end

return player_shooting_module
