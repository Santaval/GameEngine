-- =====================================================================
--  Campo de asteroides: constantes ajustables
--  La cantidad de asteroides se calcula a partir del area de la region
--  y de la densidad, asi que basta con cambiar FIELD / ASTEROID_DENSITY.
-- =====================================================================

-- Constantes compartidas con los generadores (asteroid_spawner.lua):
-- FIELD, tamanos, sprite, vida, dano y tipos/loot viven en asteroid_config
local cfg = require("asteroid_config")
local FIELD = cfg.FIELD
local ASTEROID_SCALE = cfg.ASTEROID_SCALE
local ASTEROID_SHEET = cfg.ASTEROID_SHEET
local ASTEROID_DAMAGE = cfg.ASTEROID_DAMAGE
local randRange = cfg.randRange
local pickAsteroidType = cfg.pickAsteroidType

-- Asteroides por cada bloque de 1000x1000 px.
-- La cantidad final = area(FIELD) / (1000*1000) * ASTEROID_DENSITY
local ASTEROID_DENSITY = 20

-- Rango de velocidad de deriva (px/s). min = max = 0 -> asteroides quietos
local ASTEROID_SPEED = { min = 1, max = 20 }

-- Zona libre alrededor del spawn del jugador (nil para desactivarla)
local SAFE_ZONE = { x = 400, y = 100, radius = 180 }

-- Semilla: mismo valor -> mismo campo de asteroides en cada ejecucion
local ASTEROID_SEED = 20250920

-- Separacion minima extra entre asteroides e intentos de colocacion
local ASTEROID_PACKING = { minGap = 6, tries = 40 }

-- Planetas decorativos (sin collider): uno por tipo para probar
-- x, y es el centro del planeta; scale agranda el sprite de 48x48
local PLANET_FRAME = 48          -- los png son de 48x48
local PLANETS = {
  { assetId = "planet-iron",      x = 1500, y = 400,  scale = 5 },
  { assetId = "planet-gunpowder", x = 600,  y = 1300, scale = 4 },
  { assetId = "planet-plasma",    x = 1500, y = 1600, scale = 6 },
}

-- ---------------------------------------------------------------------
--  Generacion
-- ---------------------------------------------------------------------

math.randomseed(ASTEROID_SEED)

local function distance(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

local function asteroidCount()
  local area = FIELD.width * FIELD.height
  return math.max(0, math.floor((area / (1000 * 1000)) * ASTEROID_DENSITY + 0.5))
end

-- Devuelve cx, cy, scale de un hueco libre, o nil si no lo encuentra
local function findSpot(placed)
  for _ = 1, ASTEROID_PACKING.tries do
    local scale = randRange(ASTEROID_SCALE.min, ASTEROID_SCALE.max)
    local radius = ASTEROID_SHEET.bodyRadius * scale
    local cx = randRange(FIELD.x + radius, FIELD.x + FIELD.width - radius)
    local cy = randRange(FIELD.y + radius, FIELD.y + FIELD.height - radius)

    local free = true

    if SAFE_ZONE and distance(cx, cy, SAFE_ZONE.x, SAFE_ZONE.y) < SAFE_ZONE.radius + radius then
      free = false
    end

    if free then
      for _, other in ipairs(placed) do
        if distance(cx, cy, other.x, other.y) < other.radius + radius + ASTEROID_PACKING.minGap then
          free = false
          break
        end
      end
    end

    if free then
      return cx, cy, scale, radius
    end
  end

  return nil
end

local function makeAsteroid(cx, cy, scale)
  local frameSize = ASTEROID_SHEET.frameSize
  local drawSize = frameSize * scale
  local asteroidType = pickAsteroidType()
  local frame = asteroidType.frame
  local heading = randRange(0, 2 * math.pi)
  local speed = randRange(ASTEROID_SPEED.min, ASTEROID_SPEED.max)

  return {
    components = {
      -- transform.position es la esquina superior izquierda del sprite,
      -- asi que se descuenta medio frame para centrar la roca en (cx, cy)
      transform = {
        position = { x = cx - drawSize / 2, y = cy - drawSize / 2 },
        scale = { x = scale, y = scale },
        rotation = randRange(0, 2 * math.pi),
      },
      rigid_body = {
        velocity = { x = math.cos(heading) * speed, y = math.sin(heading) * speed },
      },
      sprite = {
        assetId = ASTEROID_SHEET.assetId,
        width = frameSize,
        height = frameSize,
        src_rect = { x = frame * frameSize, y = 0 },
        rotation = 0,
      },
      circle_collider = {
        radius = ASTEROID_SHEET.bodyRadius,
        width = frameSize,
        heigth = frameSize,
      },
      health = {
        max = cfg.healthFor(asteroidType, scale),
        invulnerability = cfg.ASTEROID_INVULNERABILITY,
      },
      -- El asteroide sobrevive al choque (sin destroy_on_hit): el que tiene
      -- que preocuparse es quien se lo lleve por delante
      damage = {
        amount = ASTEROID_DAMAGE,
      },
      loot = asteroidType.loot,
       script = {
        path = "./assets/scripts/asteroid.lua"
      }
      -- Sin animation: el AnimationSystem sobrescribe src_rect.x y se perderia
      -- la variante elegida (ademas los frames 4-8 son la explosion).
    },
  }
end

-- Solo se ve: sin rigid_body, collider, health ni script
local function makePlanet(p)
  local size = PLANET_FRAME * p.scale

  return {
    components = {
      -- transform.position es la esquina superior izquierda del sprite,
      -- asi que se descuenta medio tamano para centrar el planeta en (x, y)
      transform = {
        position = { x = p.x - size / 2, y = p.y - size / 2 },
        scale = { x = p.scale, y = p.scale },
        rotation = 0,
      },
      sprite = {
        assetId = p.assetId,
        width = PLANET_FRAME,
        height = PLANET_FRAME,
        src_rect = { x = 0, y = 0 },
        rotation = 0,
      },
    },
  }
end

local function buildAsteroidField()
  local placed = {}
  local asteroids = {}

  -- Los planetas ocupan espacio: se registran primero para que findSpot
  -- no coloque asteroides encima de ellos
  for _, p in ipairs(PLANETS) do
    placed[#placed + 1] = { x = p.x, y = p.y, radius = PLANET_FRAME * p.scale / 2 }
  end

  for _ = 1, asteroidCount() do
    local cx, cy, scale, radius = findSpot(placed)
    if cx then
      placed[#placed + 1] = { x = cx, y = cy, radius = radius }
      asteroids[#asteroids + 1] = makeAsteroid(cx, cy, scale)
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

-- Los asteroides generados se anexan detras del jugador
for _, asteroid in ipairs(buildAsteroidField()) do
  entities[#entities + 1] = asteroid
end

-- Director invisible de los generadores de asteroides: solo tiene script
-- (ScriptSystem no pide nada mas). Va al final para que asteroid.lua ya
-- este cargado y sus hooks asteroid_on_* existan.
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
    {assetId="spaceship-mine", filePath="./assets/sprites/spaceship/player/mine.png"},
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
