-- =====================================================================
--  Escena principal: el sistema solar a escala comprimida
--  Los datos (distancias, tamanos, masas, cinturones, anillo) viven en
--  solar_system_config.lua; aca solo se arman las entidades.
--  Ver docs/solar-system.md
-- =====================================================================

local cfg = require("asteroid_config")
local field = require("asteroid_field")
local solar = require("solar_system_config")
local randRange = cfg.randRange

-- Semilla: mismo valor -> mismos cinturones en cada ejecucion
local SEED = 19700101

-- Tamano de las rocas de los cinturones (escala del frame de 96x96)
local BELT_SCALE = { min = 0.3, max = 1.5 }

-- Separacion minima extra entre rocas e intentos de colocacion
local PACKING = { minGap = 8, tries = 30 }

math.randomseed(SEED)

-- ---------------------------------------------------------------------
--  Planetas
-- ---------------------------------------------------------------------

local PLANETS = solar.build_planets()
solar.validate(PLANETS)

-- Globals para los modulos del jugador (orbita, zonas, mineria), el anillo
-- de Saturno y el minimapa: Lua no puede listar entidades
scene_planets = PLANETS

-- La nave arranca del lado de la Tierra que mira al Sol, justo afuera de su
-- gravedad
local spawn_planet = solar.find_planet(PLANETS, solar.PLAYER_SPAWN.planet)
local spawn_dist = spawn_planet.distance - spawn_planet.range - solar.PLAYER_SPAWN.altitude
local SPAWN = {
  x = solar.SUN_CENTER.x + spawn_dist * math.cos(spawn_planet.angle),
  y = solar.SUN_CENTER.y + spawn_dist * math.sin(spawn_planet.angle),
}

-- ---------------------------------------------------------------------
--  Cinturones de asteroides
-- ---------------------------------------------------------------------

local function beltCount(belt)
  local area = math.pi * (belt.outer * belt.outer - belt.inner * belt.inner)
  return math.floor(area / (1000 * 1000) * belt.density + 0.5)
end

-- Deriva casi tangente al Sol (sentido horario, como el anillo), con un poco
-- de desvio y un sentido u otro al azar para que no parezca una cinta
local function beltDrift(cx, cy)
  local a = math.atan(cy - solar.SUN_CENTER.y, cx - solar.SUN_CENTER.x) + math.pi / 2
  a = a + randRange(-solar.BELT_DRIFT_ANGLE, solar.BELT_DRIFT_ANGLE)
  local speed = randRange(solar.BELT_SPEED.min, solar.BELT_SPEED.max)
  return math.cos(a) * speed, math.sin(a) * speed
end

local function buildBelts()
  local placed = {}
  local asteroids = {}

  for _, p in ipairs(PLANETS) do
    placed[#placed + 1] = { x = p.x, y = p.y, radius = p.body_radius }
  end

  for _, belt in ipairs(solar.BELTS) do
    local opts = {
      sampler = field.annulus_sampler(solar.SUN_CENTER.x, solar.SUN_CENTER.y, belt.inner, belt.outer),
      scale = BELT_SCALE,
      packing = PACKING,
      safe_zone = { x = SPAWN.x, y = SPAWN.y, radius = solar.SAFE_ZONE_RADIUS },
    }
    for _ = 1, beltCount(belt) do
      local cx, cy, scale, radius = field.find_spot(placed, opts)
      if cx then
        placed[#placed + 1] = { x = cx, y = cy, radius = radius }
        asteroids[#asteroids + 1] = field.make_asteroid(cx, cy, scale, beltDrift)
      end
    end
  end

  return asteroids
end

-- Generadores en runtime (asteroid_spawner.lua): repartidos sobre cada
-- cinturon, lanzan rocas a lo largo de el para mantenerlo poblado
local function buildGenerators()
  local list = {}
  for _, belt in ipairs(solar.BELTS) do
    local r = (belt.inner + belt.outer) / 2
    local offset = randRange(0, 2 * math.pi)
    for i = 1, belt.generators do
      local a = offset + i * 2 * math.pi / belt.generators
      list[#list + 1] = {
        x = solar.SUN_CENTER.x + r * math.cos(a),
        y = solar.SUN_CENTER.y + r * math.sin(a),
        heading = a + math.pi / 2,
        spread = solar.BELT_DRIFT_ANGLE,
        speed = { min = solar.BELT_SPEED.min + 2, max = solar.BELT_SPEED.max + 6 },
      }
    end
  end
  return list
end

scene_asteroid_generators = buildGenerators()
scene_bounds = { x = solar.SUN_CENTER.x, y = solar.SUN_CENTER.y, radius = solar.MAP_RADIUS }

-- ---------------------------------------------------------------------
--  Jugador (mismo que scene_01.lua salvo la posicion, ver los comentarios
--  de collider y equipo alla)
-- ---------------------------------------------------------------------

local PLAYER_SCALE = 0.2
local PLAYER_FRAME = { w = 430, h = 650 }

local player = {
    components = {
      circle_collider =  {
        radius = 170,
        width = PLAYER_FRAME.w,
        heigth = PLAYER_FRAME.h,
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
        width = PLAYER_FRAME.w,
        height = PLAYER_FRAME.h,
        src_rect = {x = 0, y = 0},
        rotation = 0,
      },
      animation = {
        numFrames = 4,
        frameSpeedRate = 5,
        isLoop=true
      },
      -- position es la esquina sup-izq: se centra la nave en SPAWN
      transform = {
        position = {
          x = SPAWN.x - PLAYER_FRAME.w * PLAYER_SCALE / 2,
          y = SPAWN.y - PLAYER_FRAME.h * PLAYER_SCALE / 2,
        },
        scale = { x = PLAYER_SCALE, y = PLAYER_SCALE }
      },
      path = {
        active = true
      },
      health = {
        max = 100,
        invulnerability = 0.5,
      },
      damage = {
        amount = cfg.SHIP_RAM_DAMAGE,
      },
      equipment = {
        engine = 1,
        gun    = 3,
        shield = 4,
      },
      inventory = {
        capacity = 500,
      },
      script = {
        path = "./assets/scripts/player/player.lua"
      }
    },
}

-- ---------------------------------------------------------------------
--  Entidades (RenderSystem dibuja en el orden de la lista)
-- ---------------------------------------------------------------------

local entities = {}

-- Planetas primero para quedar detras de todo
for i, p in ipairs(PLANETS) do
  entities[i - 1] = field.make_planet(p, p.frame, p.frame_body_radius)
end

entities[#entities + 1] = player

for _, asteroid in ipairs(buildBelts()) do
  entities[#entities + 1] = asteroid
end

-- Directores invisibles (solo script). Van al final para que asteroid.lua ya
-- este cargado y sus hooks asteroid_on_* existan
local DIRECTORS = {
  "./assets/scripts/asteroid_spawner.lua",
  "./assets/scripts/saturn_ring.lua",
  "./assets/scripts/solar_hud.lua",
  "./assets/scripts/game_director.lua",
}
for _, path in ipairs(DIRECTORS) do
  entities[#entities + 1] = { components = { script = { path = path } } }
end

scene = {
  sprites = {
    [0] =
    {assetId="spaceship-attack", filePath="./assets/sprites/spaceship/player/attack.png"},
    {assetId="spaceship-idle", filePath="./assets/sprites/spaceship/player/idle.png"},
    {assetId="spaceship-mine", filePath="./assets/sprites/spaceship/player/mine_sheet.png"},
    {assetId="spaceship-movement", filePath="./assets/sprites/spaceship/player/movement.png"},
    {assetId="bullet", filePath="./assets/sprites/bullets/bullets.png"},
    {assetId="asteroid", filePath="./assets/sprites/asteroid/asteroid.png"},
    {assetId="mineral", filePath="./assets/sprites/minerals/tech.png"},
    {assetId="planet-iron", filePath="./assets/sprites/planets/iron.png"},
    {assetId="planet-gunpowder", filePath="./assets/sprites/planets/gunpowder.png"},
    {assetId="planet-plasma", filePath="./assets/sprites/planets/plasma.png"},
    {assetId="planet-sun", filePath="./assets/sprites/planets/sun.png"},
  },

  -- El tamaño se fija al cargar: hace falta un fontId por cada tamaño
  fonts = {
    [0] =
    {fontId="default", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=16},
    {fontId="debug-big", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=28},
    {fontId="title", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=56},
  },

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
    {name = "orbit", key = 102},
  },

  mouse = {
    [0] =
    {name = "shoot", button = 1},
  },

  entities = entities,
}
