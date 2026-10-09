-- =====================================================================
--  Script de runtime de cada asteroide (prefabs/asteroid.lua). Lo corre
--  cada cliente con su copia: el host es el duenio del asteroide (decide su
--  muerte, el loot y cuando se borra) y los demas lo simulan con lo que
--  llega por la red. Los datos propios salen de spawn_state; los locals del
--  chunk son por entidad porque este archivo corre una vez por asteroide.
--  El loot (pickup.lua / loot_net.lua) y el iman viven en sus propios archivos.
-- =====================================================================

local cfg = require("asteroid_config")
local field = require("asteroid_field")
local FIELD = cfg.FIELD
local SPLIT = cfg.SPLIT
local randRange = cfg.randRange

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
-- Roca de un chunk del mapa (map_chunks.lua): cada cliente la construye local
-- desde la semilla, sin identidad de red, asi que no hay "duenio": decide el host
local chunk_id = state.chunk_id

-- Quien manda sobre esta roca: el host en las rocas de chunk, el duenio en el resto
local function owns(e)
  if chunk_id ~= nil then return net_is_host() end
  return is_local(e)
end

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
  if not owns(e) then return end
  dead = true
  clear_loot(e)
  if chunk_id ~= nil then
    -- No esta en la red: se borra aqui y el host avisa el id a los demas
    if map_world_destroyed ~= nil then map_world_destroyed(chunk_id) end
    destroy_entity(e)
  else
    net_despawn(e)
  end
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
  if despawn_far and owns(this) then
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
  if owns(this) and is_ship(source) and get_health(this) <= 0 then
    clear_loot(this)
  end
end

-- Parte la roca en fragmentos del mismo tipo (ver SPLIT en asteroid_config.lua).
-- Solo el duenio y solo si es lo bastante grande. Los fragmentos salen en
-- abanico desde el centro, con la velocidad del padre mas un empuje hacia
-- afuera, y nacen separados para no solaparse. No depende del loot del padre
-- (ya vacio si lo rompio una nave): cada fragmento trae el suyo. Devuelve
-- true si creo fragmentos
local function split(e)
  if not owns(e) then return false end
  local scale = state.scale or 1
  if scale < SPLIT.MIN_SCALE then return false end

  local cx, cy = get_collider_center(e)
  local pvx, pvy = get_velocity(e)
  local count = math.random(SPLIT.PIECES.min, SPLIT.PIECES.max)
  local base = randRange(0, 2 * math.pi)

  for i = 1, count do
    local pieceScale = scale * randRange(SPLIT.SCALE_FACTOR.min, SPLIT.SCALE_FACTOR.max)
    pieceScale = math.max(pieceScale, cfg.ASTEROID_SCALE.min)

    -- Angulos repartidos parejo con un poco de desvio
    local a = base + (i - 1) * 2 * math.pi / count + randRange(-0.3, 0.3)
    local ux, uy = math.cos(a), math.sin(a)
    local speed = randRange(SPLIT.SPEED.min, SPLIT.SPEED.max)
    local offset = cfg.ASTEROID_SHEET.bodyRadius * pieceScale

    field.spawn_drifting(cx + ux * offset, cy + uy * offset,
                         pvx + ux * speed, pvy + uy * speed, pieceScale, state.kind)
  end
  return true
end

-- Suelta un pickup por cada item del loot del asteroide (ver ASTEROID_TYPES
-- en asteroid_config.lua) salvo que se parta en fragmentos (split). vanish
-- marca dead antes de borrar, asi que ese caso no llega aqui. Solo el duenio:
-- las copias reciben el death pero no repiten el loot. Los pickups son del
-- host y los ven todos
local function asteroid_on_death()
  -- El director suelta su referencia: el id de la entidad se recicla y no debe
  -- usarse luego para borrar otra cosa
  if chunk_id ~= nil and map_rock_gone ~= nil then map_rock_gone(chunk_id) end
  if dead then return end
  dead = true
  if not owns(this) then return end

  -- El host anota la roca de chunk como destruida y avisa a los demas (late
  -- joiners incluidos); los clientes solo la marcan muerta: sin loot ni
  -- fragmentos, esos llegan del host por net_spawn
  if chunk_id ~= nil and map_world_destroyed ~= nil then map_world_destroyed(chunk_id) end

  -- Una roca que se parte no suelta loot: lo sueltan sus fragmentos
  if split(this) then return end

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
