-- =====================================================================
--  Generadores de asteroides
--  Script del "director": una entidad invisible de la escena que solo tiene
--  este script. Reparte generadores en un anillo justo afuera del FIELD y
--  cada uno, cada tanto (tiempo aleatorio), lanza un asteroide hacia un
--  punto al azar del mapa. Nunca spawnea a la vista ni cerca del jugador.
--
--  Una escena puede reemplazar los generadores y los limites del mapa con
--  dos globals (los usa scenes/solar_system.lua):
--    scene_asteroid_generators = { {x, y, heading, spread, speed = {min, max}}, ... }
--      heading: direccion base del lanzamiento (rad), spread: desvio maximo
--    scene_bounds = { x, y, radius }  -- circulo fuera del cual se borran
-- =====================================================================

local cfg = require("asteroid_config")
local FIELD = cfg.FIELD
local randRange = cfg.randRange

-- Distancia fuera del FIELD a la que estan los generadores
local SPAWN_MARGIN = 150

-- Generadores por cada lado del FIELD (4 lados -> 4 * N en total)
local GENERATORS_PER_SIDE = 3

-- Segundos entre un asteroide y el siguiente, por generador
local SPAWN_INTERVAL = { min = 2, max = 6 }

-- Velocidad (px/s) de los asteroides generados
local SPAWN_SPEED = { min = 5, max = 20 }

-- Tope de asteroides vivos creados por los generadores (el campo inicial
-- de la escena no cuenta)
local MAX_ALIVE = 40

-- No spawnear si el jugador esta a menos de esta distancia del generador
local PLAYER_SAFE_RADIUS = 500

-- Ni si el generador cae dentro de la pantalla (agrandada con este margen,
-- que tiene que cubrir medio asteroide grande: 96 * 3 / 2 = 144)
local SCREEN_MARGIN = 150

-- Al alejarse esto del FIELD el asteroide se borra sin soltar loot. Tiene
-- que ser mayor que SPAWN_MARGIN o moririan al nacer
local DESPAWN_MARGIN = 600

-- ---------------------------------------------------------------------
--  Estado (locals del archivo: las closures los mantienen entre frames)
-- ---------------------------------------------------------------------

local generators = nil
local alive = 0

local function buildGenerators()
  local list = {}

  if scene_asteroid_generators ~= nil then
    for _, g in ipairs(scene_asteroid_generators) do
      list[#list + 1] = {
        x = g.x, y = g.y, heading = g.heading, spread = g.spread or 0, speed = g.speed,
        timer = randRange(SPAWN_INTERVAL.min, SPAWN_INTERVAL.max),
      }
    end
    return list
  end

  local left, top = FIELD.x - SPAWN_MARGIN, FIELD.y - SPAWN_MARGIN
  local right = FIELD.x + FIELD.width + SPAWN_MARGIN
  local bottom = FIELD.y + FIELD.height + SPAWN_MARGIN

  local function add(x, y)
    list[#list + 1] = { x = x, y = y, timer = randRange(SPAWN_INTERVAL.min, SPAWN_INTERVAL.max) }
  end

  -- Repartidos a lo largo de cada lado, sin caer en las esquinas
  for i = 1, GENERATORS_PER_SIDE do
    local t = i / (GENERATORS_PER_SIDE + 1)
    add(FIELD.x + FIELD.width * t, top)
    add(FIELD.x + FIELD.width * t, bottom)
    add(left, FIELD.y + FIELD.height * t)
    add(right, FIELD.y + FIELD.height * t)
  end

  return list
end

local function isOnScreen(x, y)
  local camX, camY = get_camera_position()
  local w, h = get_screen_size()
  return x > camX - SCREEN_MARGIN and x < camX + w + SCREEN_MARGIN
     and y > camY - SCREEN_MARGIN and y < camY + h + SCREEN_MARGIN
end

local function isPlayerNear(x, y)
  if player_entity == nil or not is_alive(player_entity) then return false end

  local px, py = get_position(player_entity)
  local dx, dy = px - x, py - y
  return dx * dx + dy * dy < PLAYER_SAFE_RADIUS * PLAYER_SAFE_RADIUS
end

local function isFarOutside(cx, cy)
  if scene_bounds ~= nil then
    local dx, dy = cx - scene_bounds.x, cy - scene_bounds.y
    return dx * dx + dy * dy > scene_bounds.radius * scene_bounds.radius
  end
  return cx < FIELD.x - DESPAWN_MARGIN or cx > FIELD.x + FIELD.width + DESPAWN_MARGIN
      or cy < FIELD.y - DESPAWN_MARGIN or cy > FIELD.y + FIELD.height + DESPAWN_MARGIN
end

-- ---------------------------------------------------------------------
--  Creacion de un asteroide en runtime (mismo asteroide que makeAsteroid
--  de scene_01.lua, pero con la API de entidades en vez de una tabla)
-- ---------------------------------------------------------------------

local function spawnAsteroid(cx, cy, vx, vy)
  local sheet = cfg.ASTEROID_SHEET
  local frameSize = sheet.frameSize
  local scale = randRange(cfg.ASTEROID_SCALE.min, cfg.ASTEROID_SCALE.max)
  local drawSize = frameSize * scale
  local asteroidType = cfg.pickAsteroidType()

  local e = create_entity()
  -- position es la esquina sup-izq: se descuenta medio frame para centrar
  add_transform(e, cx - drawSize / 2, cy - drawSize / 2, scale, scale, randRange(0, 2 * math.pi))
  add_rigid_body(e, vx, vy, 0, 0)
  add_gravity(e, scale * cfg.GRAVITY.ASTEROID_MASS_PER_SCALE, false, true)
  add_sprite(e, sheet.assetId, frameSize, frameSize, asteroidType.frame * frameSize, 0)
  add_circle_collider(e, sheet.bodyRadius, frameSize, frameSize)
  add_health(e, cfg.healthFor(asteroidType, scale), cfg.ASTEROID_INVULNERABILITY)
  add_damage(e, cfg.ASTEROID_DAMAGE)
  for name, quantity in pairs(asteroidType.loot) do
    set_loot(e, name, quantity)
  end

  -- on_death puede llegar dos veces (kill() es diferido: una bala y el
  -- despawn en el mismo frame, o el update del frame siguiente), asi que
  -- cada asteroide lleva su propia bandera para descontarse una sola vez
  local dead = false
  local half = drawSize / 2

  -- add_script primero: recrea el ScriptComponent y borraria los hooks
  add_script(e, function()
    if dead then return end
    local x, y = get_position(this)
    if isFarOutside(x + half, y + half) then
      -- Se fue del mapa: se borra sin loot para que asteroid_on_death no
      -- deje pickups perdidos en el vacio
      asteroid_vanish(this)
    end
  end)
  set_on_damage(e, asteroid_on_damage)
  set_on_collision(e, asteroid_on_collision)
  set_on_death(e, function()
    if dead then return end
    dead = true
    alive = alive - 1
    asteroid_on_death()
  end)

  alive = alive + 1
end

local function trySpawn(gen)
  if alive >= MAX_ALIVE then return end
  if isPlayerNear(gen.x, gen.y) or isOnScreen(gen.x, gen.y) then return end

  local speedRange = gen.speed or SPAWN_SPEED
  local speed = randRange(speedRange.min, speedRange.max)

  if gen.heading ~= nil then
    -- Generador de la escena: lanza hacia su heading con un poco de desvio
    local a = gen.heading + randRange(-gen.spread, gen.spread)
    spawnAsteroid(gen.x, gen.y, math.cos(a) * speed, math.sin(a) * speed)
    return
  end

  -- Direccion aleatoria pero hacia dentro: apunta a un punto al azar del
  -- mapa, asi todos los asteroides lo cruzan en vez de perderse afuera
  local tx = randRange(FIELD.x, FIELD.x + FIELD.width)
  local ty = randRange(FIELD.y, FIELD.y + FIELD.height)
  local dx, dy = tx - gen.x, ty - gen.y
  local d = math.sqrt(dx * dx + dy * dy)

  spawnAsteroid(gen.x, gen.y, dx / d * speed, dy / d * speed)
end

function update()
  -- Mismo guard que enemy.lua: hasta que el jugador corra su primer frame
  -- ni player_entity existe ni la camara esta centrada en el, y los chequeos
  -- de distancia / pantalla darian cualquier cosa
  if player_entity == nil then return end

  if generators == nil then
    -- Normalmente asteroid.lua ya lo cargo el campo inicial de la escena;
    -- si no hay ninguno se carga aca, en runtime, donde pisar los globals
    -- update/on_death ya no afecta al SceneLoader
    if asteroid_on_death == nil then require("asteroid") end
    generators = buildGenerators()
  end

  local dt = get_delta_time()
  for _, gen in ipairs(generators) do
    gen.timer = gen.timer - dt
    if gen.timer <= 0 then
      gen.timer = randRange(SPAWN_INTERVAL.min, SPAWN_INTERVAL.max)
      trySpawn(gen)
    end
  end
end
