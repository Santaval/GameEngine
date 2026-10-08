-- =====================================================================
--  Script de runtime de cada asteroide (prefabs/asteroid.lua). Lo corre
--  cada cliente con su copia: el host es el duenio del asteroide (decide su
--  muerte, el loot y cuando se borra) y los demas lo simulan con lo que
--  llega por la red. Los datos propios salen de spawn_state; los locals del
--  chunk son por entidad porque este archivo corre una vez por asteroide.
--  El loot (pickup.lua / loot_net.lua) y el iman viven en sus propios archivos.
-- =====================================================================

local cfg = require("asteroid_config")
local FIELD = cfg.FIELD

-- Separacion entre pickups cuando el asteroide suelta varios items distintos
local PICKUP_SPREAD = 20

-- Rebote contra la nave: RESTITUTION es cuanto de la velocidad de choque
-- se devuelve (0 = sin rebote), MIN_KNOCKBACK es el empuje minimo (px/s) con
-- el que sale la nave aunque el golpe sea suave o ella este quieta
local BOUNCE_RESTITUTION = 0.6
local MIN_KNOCKBACK = 60

-- Al alejarse esto del FIELD el asteroide se borra sin soltar loot. Tiene
-- que ser mayor que SPAWN_MARGIN del spawner o moririan al nacer
local DESPAWN_MARGIN = 600

-- Rocas del anillo de Saturno: correccion hacia su carril (px/s de velocidad
-- por px de error) y que tan rapido la velocidad real converge a la deseada
-- (1/s). Bajo, para que el rebote contra la nave se note antes de volver
local POSITION_GAIN = 1.5
local STEER_RATE = 2

-- Datos de esta roca (spawn_state lo fija el motor mientras arma el prefab)
local state = spawn_state or {}
local despawn_far = state.despawn_far == true
local ring = state.ring
local slot = state.slot
local half = cfg.ASTEROID_SHEET.frameSize * (state.scale or 1) / 2

-- on_death puede llegar dos veces (kill() es diferido: una bala y el
-- despawn en el mismo frame, o el update del frame siguiente): la bandera
-- evita soltar el loot dos veces
local dead = false

local function isFarOutside(cx, cy)
  if scene_bounds ~= nil then
    local dx, dy = cx - scene_bounds.x, cy - scene_bounds.y
    return dx * dx + dy * dy > scene_bounds.radius * scene_bounds.radius
  end
  return cx < FIELD.x - DESPAWN_MARGIN or cx > FIELD.x + FIELD.width + DESPAWN_MARGIN
      or cy < FIELD.y - DESPAWN_MARGIN or cy > FIELD.y + FIELD.height + DESPAWN_MARGIN
end

-- Vacia el loot para que on_death no deje pickups. Se copia primero
-- porque set_loot modifica la lista mientras se recorre
local function clear_loot(e)
  local names = {}
  for i = 1, get_loot_count(e) do
    names[#names + 1] = get_loot_at(e, i)
  end
  for _, name in ipairs(names) do
    set_loot(e, name, 0)
  end
end

-- Desaparece sin soltar loot. Solo el duenio lo borra; las copias esperan el
-- despawn del duenio (el mismo planeta lo traga en todos los clientes)
local function vanish(e)
  if not is_local(e) then return end
  dead = true
  clear_loot(e)
  net_despawn(e)
end

-- Una nave: la local (tiene inventario) o la de otro jugador (player_ships)
local function is_ship(e)
  if e == nil then return false end
  if has_inventory(e) then return true end
  local id = get_net_id(e)
  return id ~= nil and player_ships ~= nil and player_ships[id] == true
end

-- Rocas del anillo: sigue el carril (radio ring.radius alrededor de ring.x,
-- ring.y) a velocidad tangencial ring.speed * radio. Depende solo del estado
-- replicado, asi que corre igual en todos los clientes
local function steer_in_lane()
  local x, y = get_collider_center(this)
  local dx, dy = x - ring.x, y - ring.y
  local r = math.sqrt(dx * dx + dy * dy)
  if r < 0.001 then return end
  local ux, uy = dx / r, dy / r

  local v_t = ring.speed * ring.radius
  local radial = (ring.radius - r) * POSITION_GAIN
  local want_x = -uy * v_t + ux * radial
  local want_y = ux * v_t + uy * radial

  local vx, vy = get_velocity(this)
  local k = math.min(1, STEER_RATE * get_delta_time())
  set_velocity(this, vx + (want_x - vx) * k, vy + (want_y - vy) * k)
end

function update()
  if dead then return end

  -- Cada cliente anota sus asteroides: el spawner cuenta los vivos con esta
  -- tabla (asi el nuevo host arranca con la cuenta correcta tras migrar) y
  -- el anillo sabe que lugares siguen ocupados
  local id = get_net_id(this)
  if id ~= nil then
    if despawn_far and drifting_asteroids ~= nil then drifting_asteroids[id] = true end
    if ring ~= nil and slot ~= nil and ring_slots ~= nil then ring_slots[slot] = id end
  end

  if ring ~= nil then steer_in_lane() end

  -- Solo el duenio decide que se fue del mapa
  if despawn_far and is_local(this) then
    local x, y = get_position(this)
    if isFarOutside(x + half, y + half) then
      -- Sin loot: no dejar pickups perdidos en el vacio
      vanish(this)
    end
  end
end

local function asteroid_on_damage(amount, source)
  print(string.format("[asteroid] -%d HP (quedan %d)", amount, get_health(this)))
  -- Un choque de la nave que lo rompe no suelta loot: on_death corre
  -- despues de este hook y ya no encuentra nada
  if is_local(this) and is_ship(source) and get_health(this) <= 0 then
    clear_loot(this)
  end
end

-- Suelta un pickup por cada item del loot del asteroide (ver ASTEROID_TYPES
-- en asteroid_config.lua). Solo el duenio: las copias reciben el death pero
-- no repiten el loot. Los pickups son del host y los ven todos
local function asteroid_on_death()
  if dead then return end
  dead = true
  if not is_local(this) then return end

  local x, y = get_position(this)
  local count = get_loot_count(this)

  for i = 1, count do
    local name, quantity = get_loot_at(this, i)
    local offset = (i - (count + 1) / 2) * PICKUP_SPREAD
    net_spawn("pickup.lua", {
      pos = { x = x + offset, y = y },
      item = name,
      quantity = quantity,
      world = true,
    })
  end
end

-- Choque elastico (con perdida) entre el asteroide y la nave a lo largo de la
-- normal que une sus centros. Solo actua si se estan acercando, asi que los
-- frames siguientes de solape no repiten el impulso; el empuje minimo cubre
-- el caso de la nave quieta golpeada por un asteroide lento. max_speed no
-- topa este impulso: solo limita lo que suma el motor (MovementSystem)
local function bounce_off_ship(asteroid, ship)
  local ax, ay = get_collider_center(asteroid)
  local sx, sy = get_collider_center(ship)
  local dx, dy = sx - ax, sy - ay
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.001 then return end
  local nx, ny = dx / d, dy / d

  local mAst, mShip = get_mass(asteroid), get_mass(ship)
  if mAst <= 0 then mAst = 1 end
  if mShip <= 0 then mShip = 1 end

  local avx, avy = get_velocity(asteroid)
  local svx, svy = get_velocity(ship)
  local along = (svx - avx) * nx + (svy - avy) * ny

  if along < 0 then
    local j = -(1 + BOUNCE_RESTITUTION) * along
    local total = mShip + mAst
    svx = svx + j * mAst / total * nx
    svy = svy + j * mAst / total * ny
    avx = avx - j * mShip / total * nx
    avy = avy - j * mShip / total * ny
    set_velocity(asteroid, avx, avy)
  end

  local shipAlong = svx * nx + svy * ny
  if shipAlong < MIN_KNOCKBACK then
    local push = MIN_KNOCKBACK - shipAlong
    svx = svx + push * nx
    svy = svy + push * ny
  end
  set_velocity(ship, svx, svy)
end

-- Un planeta (fuente de gravedad) se traga al asteroide que lo toca; la nave
-- (con inventario) lo hace rebotar. El rebote corre en todos los clientes y
-- el "state" del duenio lo corrige
local function asteroid_on_collision(other)
  if is_gravity_source(other) then
    vanish(this)
  elseif has_inventory(other) then
    bounce_off_ship(this, other)
  end
end

on_damage = asteroid_on_damage
on_death = asteroid_on_death
on_collision = asteroid_on_collision
