-- Enemigo (prefabs/enemy.lua). Lo corre cada cliente con su copia: persigue y
-- dispara a la nave mas cercana entre la local y las de otros jugadores
-- (player_ships), una regla determinista que todos calculan igual, asi que no
-- hace falta mandar un "target". Las balas del enemigo son locales en cada
-- cliente (no usan "fire", que las marcaria como de jugador y con pvp
-- apagado no dañarian a las naves remotas); el dano lo decide el duenio de la
-- nave golpeada. Los locals del chunk son por entidad.

local enemy_thrust = 40
local enemy_turn_speed = 3
local enemy_bullet_damage = 15
local shoot_cooldown = 1.2
local shoot_timer = shoot_cooldown

-- Nave viva mas cercana a (x, y): la local o alguna de player_ships. Poda las
-- que ya no existen
local function nearest_ship(x, y)
  local best, best_d = nil, math.huge

  local function consider(e)
    local px, py = get_position(e)
    local d = (px - x) * (px - x) + (py - y) * (py - y)
    if d < best_d then best, best_d = e, d end
  end

  if player_entity ~= nil and is_alive(player_entity) then consider(player_entity) end

  if player_ships ~= nil then
    for id in pairs(player_ships) do
      local e = find_by_net_id(id)
      if e ~= nil and is_alive(e) then
        consider(e)
      else
        player_ships[id] = nil
      end
    end
  end

  return best
end

function update()
  -- Espera a que el jugador haya corrido al menos un frame de su script
  if player_entity == nil then return end

  local dt = get_delta_time()

  local ex, ey = get_position(this)
  local target = nearest_ship(ex, ey)
  if target == nil then return end
  local px, py = get_position(target)

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
    add_gravity(bullet, 1, false, true)
    add_sprite(bullet, "bullet", 64, 32, 0, 192)
    add_animation(bullet, 8, 5, true)
    add_circle_collider(bullet, 30, 64, 32, this)
    add_damage(bullet, enemy_bullet_damage, true)
  end
end
