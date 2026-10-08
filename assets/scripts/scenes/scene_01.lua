-- =====================================================================
--  Campo de asteroides: constantes ajustables
--  La cantidad de asteroides se calcula a partir del area de la region
--  y de la densidad, asi que basta con cambiar FIELD / ASTEROID_DENSITY.
-- =====================================================================

-- Constantes compartidas con los generadores (asteroid_spawner.lua):
-- FIELD, tamanos, sprite, vida, dano y tipos/loot viven en asteroid_config
local cfg = require("asteroid_config")
local field = require("asteroid_field")
local FIELD = cfg.FIELD
local ASTEROID_SCALE = cfg.ASTEROID_SCALE
local randRange = cfg.randRange

-- Asteroides por cada bloque de 1000x1000 px.
-- La cantidad final = area(FIELD) / (1000*1000) * ASTEROID_DENSITY
local ASTEROID_DENSITY = 2

-- Rango de velocidad de deriva (px/s). min = max = 0 -> asteroides quietos
local ASTEROID_SPEED = { min = 1, max = 20 }

-- Zona libre alrededor del spawn del jugador (nil para desactivarla)
local SAFE_ZONE = { x = 400, y = 100, radius = 180 }

-- Semilla: mismo valor -> mismo campo de asteroides en cada ejecucion
local ASTEROID_SEED = 20250920

-- Separacion minima extra entre asteroides e intentos de colocacion
local ASTEROID_PACKING = { minGap = 6, tries = 40 }

-- Planetas: uno por tipo para probar. Tienen collider para tragarse a los
-- asteroides que los tocan (ver asteroid.lua); la nave y las balas los cruzan
-- x, y es el centro del planeta; scale agranda el sprite de 48x48
-- mass y range alimentan la gravedad (ver docs/gravity.md): range en px
-- damage: vida que pierde la nave cada 0.5 s apoyada en el planeta
-- mineral / mine_interval: item que da minar dentro de la gravedad y cada cuantos segundos
local PLANET_FRAME = 48          -- los png son de 48x48
-- Radio del planeta dibujado dentro del png de 48x48; se escala con p.scale
-- en runtime, igual que ASTEROID_SHEET.bodyRadius
local PLANET_BODY_RADIUS = 22
local PLANETS = {
  { assetId = "planet-iron",      x = 1500, y = 400,  scale = 5, mass = 3000, range = 700, damage = 15,
    mineral = "iron", mine_interval = 2 },
  { assetId = "planet-gunpowder", x = 600,  y = 1300, scale = 4, mass = 2000, range = 600, damage = 15,
    mineral = "gunpowder", mine_interval = 2 },
  { assetId = "planet-plasma",    x = 1500, y = 1600, scale = 6, mass = 4500, range = 800, damage = 15,
    mineral = "plasma", mine_interval = 2 },
}

-- Global para player_gravity_zones / player_mining: Lua no puede listar entidades, asi que la
-- escena publica sus planetas (centro, masa, range y radio del cuerpo en px)
for _, p in ipairs(PLANETS) do
  p.body_radius = PLANET_BODY_RADIUS * p.scale
end
scene_planets = PLANETS
-- Esta escena usa los generadores y limites por defecto del spawner (FIELD):
-- se borran por si quedaron de la escena del sistema solar
scene_asteroid_generators = nil
scene_bounds = nil

-- Estado compartido del mundo en red (lo rellenan asteroid.lua y
-- remote_player.lua, lo leen el spawner y los enemigos). Se reinicia al
-- cargar la escena para no arrastrar ids de la partida anterior
drifting_asteroids = {}
ring_slots = {}
player_ships = {}

-- ---------------------------------------------------------------------
--  Generacion (constructores compartidos en asteroid_field.lua)
-- ---------------------------------------------------------------------

math.randomseed(ASTEROID_SEED)

local function asteroidCount()
  local area = FIELD.width * FIELD.height
  return math.max(0, math.floor((area / (1000 * 1000)) * ASTEROID_DENSITY + 0.5))
end

local FIELD_OPTS = {
  sampler = field.rect_sampler(FIELD),
  scale = ASTEROID_SCALE,
  packing = ASTEROID_PACKING,
  safe_zone = SAFE_ZONE,
}

-- Deriva en una direccion al azar
local function randomDrift()
  local heading = randRange(0, 2 * math.pi)
  local speed = randRange(ASTEROID_SPEED.min, ASTEROID_SPEED.max)
  return math.cos(heading) * speed, math.sin(heading) * speed
end

local function makePlanet(p)
  return field.make_planet(p, PLANET_FRAME, PLANET_BODY_RADIUS)
end

local function buildAsteroidField()
  local placed = {}
  local asteroids = {}

  -- Los planetas ocupan espacio: se registran primero para que find_spot
  -- no coloque asteroides encima de ellos
  for _, p in ipairs(PLANETS) do
    placed[#placed + 1] = { x = p.x, y = p.y, radius = PLANET_FRAME * p.scale / 2 }
  end

  for _ = 1, asteroidCount() do
    local cx, cy, scale, radius = field.find_spot(placed, FIELD_OPTS)
    if cx then
      placed[#placed + 1] = { x = cx, y = cy, radius = radius }
      asteroids[#asteroids + 1] = field.asteroid_state(cx, cy, scale, randomDrift)
    end
  end

  return asteroids
end

-- ---------------------------------------------------------------------
--  Entidades fijas de la escena
-- ---------------------------------------------------------------------

-- Player
local player = {
    components = {
      -- El radio esta en unidades del sprite SIN escalar: CollisionSystem lo
      -- multiplica por scale.x (0.2), asi que 170 -> 34 px de radio en
      -- pantalla, casi exactamente la semi-anchura visible de la nave.
      -- El sprite real ocupa 353x474 dentro del frame de 430x650 (el resto es
      -- transparente), y el centro del collider cae en el pivote de rotacion
      -- de RenderSystem: desde ahi hay 163 px al borde derecho y 172 a la
      -- cola, asi que 170 inscribe el cuerpo. La punta de la nariz queda
      -- afuera: es inevitable con un solo circulo en una nave mas alta que
      -- ancha, y de paso perdona un poco (DamageSystem mata al instante).
      --
      -- width/heigth son el frame COMPLETO a proposito, no el bbox del dibujo:
      -- el centro sale de position + (width/2)*scale, y ese punto es el pivote
      -- con el que SDL_RenderCopyEx gira el sprite (center = NULL), el unico
      -- que no se desplaza cuando la nave apunta al mouse.
      circle_collider =  {
        radius = 170,
        width = 430,
        heigth = 650,
      },
      gravity = {
        mass = cfg.GRAVITY.SHIP.mass,
        attracts = false,
        affected = true,
      },
      rigid_body = {
        velocity = { x = 0, y = 0},
        max_speed=100
      },
      sprite = {
        assetId = "spaceship-idle",
        width = 430,
        height = 650,
        src_rect = {x = 0, y = 0},
        rotation = 0,
      },
      animation = {
        numFrames = 4,
        frameSpeedRate = 5,
        isLoop=true
      },
      transform = {
        position = {x = 400, y = 100},
        scale = { x = 0.2, y = 0.2}
      },
      path = {
        active = true
      },
      -- medio segundo de gracia tras cada golpe: sin eso, rozar un asteroide
      -- aplicaria dano en cada frame y la nave moriria al instante
      health = {
        max = 100,
        invulnerability = 0.5,
        player = true,
      },
      -- Al embestir, la nave tambien lastima (sin destroy_on_hit: sobrevive
      -- al choque)
      damage = {
        amount = cfg.SHIP_RAM_DAMAGE,
      },
      -- Niveles iniciales de las herramientas mejorables del jugador. Las
      -- claves son libres (nada en C++ las conoce de antemano); el loader
      -- las ordena alfabeticamente al leerlas, asi que el orden aqui no
      -- importa.
      equipment = {
        engine = 1,
        gun    = 3,
        shield = 4,
      },
      -- Bodega de carga: 50 unidades entre todos los items. Sin "items"
      -- arranca vacia.
      inventory = {
        capacity = 500,
      },
      script = {
        path = "./assets/scripts/player/player.lua"
      }
    },
}

-- RenderSystem dibuja en el orden de la lista: los planetas van primero
-- (indices 0..2) para quedar detras del jugador y de los asteroides
local entities = {}

entities[0] = makePlanet(PLANETS[1])
for i = 2, #PLANETS do
  entities[#entities + 1] = makePlanet(PLANETS[i])
end

entities[#entities + 1] = player

-- Los asteroides iniciales ya no son entidades de la escena: el host los
-- crea con net_spawn (asteroid_spawner.lua) para que todos los clientes
-- los vean. Aqui solo se publica su estado de spawn
scene_initial_asteroids = buildAsteroidField()

-- Director invisible de los generadores de asteroides: solo tiene script
-- (ScriptSystem no pide nada mas)
entities[#entities + 1] = {
  components = {
    script = {
      path = "./assets/scripts/asteroid_spawner.lua"
    }
  },
}

-- Director de la partida: game over, reinicio y vuelta al menu
entities[#entities + 1] = {
  components = {
    script = {
      path = "./assets/scripts/game_director.lua"
    }
  },
}

scene = {
  -- Sprites
  sprites = {
    [0] =
    {assetId="spaceship-attack", filePath="./assets/sprites/spaceship/player/attack.png"},
    {assetId="spaceship-idle", filePath="./assets/sprites/spaceship/player/idle.png"},
    {assetId="spaceship-movement", filePath="./assets/sprites/spaceship/player/movement.png"},
    {assetId="bullet", filePath="./assets/sprites/bullets/bullets.png"},
    {assetId="asteroid", filePath="./assets/sprites/asteroid/asteroid.png"},
    {assetId="mineral", filePath="./assets/sprites/minerals/tech.png"},
    {assetId="planet-iron", filePath="./assets/sprites/planets/iron.png"},
    {assetId="planet-gunpowder", filePath="./assets/sprites/planets/gunpowder.png"},
    {assetId="planet-plasma", filePath="./assets/sprites/planets/plasma.png"},
  },

  -- Fuentes
  -- El tamaño se fija al cargar: hace falta un fontId por cada tamaño
  fonts = {
    [0] =
    {fontId="default", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=16},
    {fontId="debug-big", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=28},
    {fontId="title", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=56},
  },

  -- Keys
  keys = {
    [0] = 
    {name = "accelerate", key=119},
    {name = "brake", key=115},
    {name = "toggle_path", key = 116},
    {name = "toggle_colliders", key = 99},
    {name = "toggle_upgrades", key = 101},
    {name = "upgrade_1", key = 49},
    {name = "upgrade_2", key = 50},
    {name = "upgrade_3", key = 51},
    {name = "confirm", key = 13},
    {name = "menu", key = 109},
  },

  -- Mouse
  mouse = {
    [0] =
    {name = "shoot", button = 1},
  },

  -- Entities
  entities = entities,
}
