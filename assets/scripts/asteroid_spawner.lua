-- =====================================================================
--  Generadores de asteroides
--  Script del "director": una entidad invisible de la escena que solo tiene
--  este script. Reparte generadores en un anillo justo afuera del FIELD y
--  cada uno, cada tanto (tiempo aleatorio), lanza un asteroide hacia un
--  punto al azar del mapa. Nunca spawnea a la vista ni cerca del jugador.
--
--  Multijugador: solo el host siembra y genera (offline siempre lo es). Los
--  asteroides se crean con net_spawn("asteroid.lua", ...) con world = true,
--  asi que son del host y todos los clientes los simulan. Si el host se va, el
--  nuevo host retoma los generadores (se arman al primer frame que es host).
--  El campo inicial lo publica la escena en scene_initial_asteroids.
--
--  Una escena puede reemplazar los generadores y los limites del mapa con
--  dos globals (los usa scenes/solar_system.lua):
--    scene_asteroid_generators = { {x, y, heading, spread, speed = {min, max}}, ... }
--      heading: direccion base del lanzamiento (rad), spread: desvio maximo
--    scene_bounds = { x, y, radius }  -- circulo fuera del cual se borran
-- =====================================================================

local cfg = require("asteroid_config")
local field = require("asteroid_field")
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
-- de la escena no cuenta). Se cuentan en drifting_asteroids, que llena cada
-- asteroide con despawn_far en todos los clientes
local MAX_ALIVE = 40

-- No spawnear si el jugador esta a menos de esta distancia del generador
local PLAYER_SAFE_RADIUS = 500

-- Ni si el generador cae dentro de la pantalla (agrandada con este margen,
-- que tiene que cubrir medio asteroide grande: 96 * 3 / 2 = 144)
local SCREEN_MARGIN = 150

-- Siembra del campo inicial en red: asteroides por segundo, para no pasar el
-- limite del relay (120 msg/s). Offline se crean todos de golpe
local SEED_RATE = 30

-- ---------------------------------------------------------------------
--  Estado (locals del archivo: las closures los mantienen entre frames)
-- ---------------------------------------------------------------------

local generators = nil
-- Campo inicial: ya sembrado (o este cliente nunca fue host)
local seeded = false
local seed_index = 1
local seed_budget = 0

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

local function near(e, x, y)
  if e == nil or not is_alive(e) then return false end

  local px, py = get_position(e)
  local dx, dy = px - x, py - y
  return dx * dx + dy * dy < PLAYER_SAFE_RADIUS * PLAYER_SAFE_RADIUS
end

-- La nave local o la de cualquier otro jugador (player_ships)
local function isPlayerNear(x, y)
  if near(player_entity, x, y) then return true end
  for id in pairs(player_ships or {}) do
    if near(find_by_net_id(id), x, y) then return true end
  end
  return false
end

-- Asteroides vivos creados por los generadores. Se poda lo que ya no existe
local function countAlive()
  local count = 0
  for id in pairs(drifting_asteroids) do
    local e = find_by_net_id(id)
    if e ~= nil and is_alive(e) then
      count = count + 1
    else
      drifting_asteroids[id] = nil
    end
  end
  return count
end

local function trySpawn(gen)
  if countAlive() >= MAX_ALIVE then return end
  if isPlayerNear(gen.x, gen.y) or isOnScreen(gen.x, gen.y) then return end

  local speedRange = gen.speed or SPAWN_SPEED
  local speed = randRange(speedRange.min, speedRange.max)

  if gen.heading ~= nil then
    -- Generador de la escena: lanza hacia su heading con un poco de desvio
    local a = gen.heading + randRange(-gen.spread, gen.spread)
    field.spawn_drifting(gen.x, gen.y, math.cos(a) * speed, math.sin(a) * speed)
    return
  end

  -- Direccion aleatoria pero hacia dentro: apunta a un punto al azar del
  -- mapa, asi todos los asteroides lo cruzan en vez de perderse afuera
  local tx = randRange(FIELD.x, FIELD.x + FIELD.width)
  local ty = randRange(FIELD.y, FIELD.y + FIELD.height)
  local dx, dy = tx - gen.x, ty - gen.y
  local d = math.sqrt(dx * dx + dy * dy)

  field.spawn_drifting(gen.x, gen.y, dx / d * speed, dy / d * speed)
end

-- Crea el campo inicial publicado por la escena. Online lo reparte en
-- varios frames (SEED_RATE por segundo); offline lo crea todo de una vez
local function seedField()
  local list = scene_initial_asteroids or {}
  local online = net_is_online()

  if online then
    seed_budget = seed_budget + get_delta_time() * SEED_RATE
  end

  while seed_index <= #list do
    if online then
      if seed_budget < 1 then return end
      seed_budget = seed_budget - 1
    end
    net_spawn("asteroid.lua", list[seed_index])
    seed_index = seed_index + 1
  end

  seeded = true
end

function update()
  drifting_asteroids = drifting_asteroids or {}

  -- Solo el host siembra y genera. Quien no lo era al empezar nunca siembra,
  -- ni siquiera si despues pasa a ser host (el mundo ya existe: lo recibio
  -- por snapshot); solo retoma los generadores
  if not net_is_host() then
    seeded = true
    return
  end

  if not seeded then seedField() end

  -- Mismo guard que enemy.lua: hasta que el jugador corra su primer frame
  -- ni player_entity existe ni la camara esta centrada en el, y los chequeos
  -- de distancia / pantalla darian cualquier cosa
  if player_entity == nil then return end

  -- Los generadores se arman al primer frame como host (tambien tras migrar)
  if generators == nil then
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
