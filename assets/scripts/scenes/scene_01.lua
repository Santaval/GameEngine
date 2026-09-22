-- =====================================================================
--  Campo de asteroides: constantes ajustables
--  La cantidad de asteroides se calcula a partir del area de la region
--  y de la densidad, asi que basta con cambiar FIELD / ASTEROID_DENSITY.
-- =====================================================================

-- Region (en pixeles de mundo) donde se generan los asteroides
local FIELD = {
  x = 0,
  y = 0,
  width = 20000,
  height = 20000,
}

-- Asteroides por cada bloque de 1000x1000 px.
-- La cantidad final = area(FIELD) / (1000*1000) * ASTEROID_DENSITY
local ASTEROID_DENSITY = 1

-- Rango de tamanos (escala aplicada al frame del sprite)
local ASTEROID_SCALE = { min = 0.25, max = 3 }

-- Rango de velocidad de deriva (px/s). min = max = 0 -> asteroides quietos
local ASTEROID_SPEED = { min = 1, max = 20 }

-- Zona libre alrededor del spawn del jugador (nil para desactivarla)
local SAFE_ZONE = { x = 400, y = 100, radius = 180 }

-- Semilla: mismo valor -> mismo campo de asteroides en cada ejecucion
local ASTEROID_SEED = 20250920

-- Datos del spritesheet ./assets/sprites/asteroid/asteroid.png (768x96)
-- 8 frames de 96x96: los 3 primeros son la roca (sana / agrietada / fundida),
-- los 5 restantes son la explosion.
local ASTEROID_SHEET = {
  assetId = "asteroid",
  frameSize = 96,
  variants = 3,     -- cuantos frames iniciales se usan como variantes visuales
  bodyRadius = 26,  -- radio de la roca dentro del frame de 96x96
}

-- Separacion minima extra entre asteroides e intentos de colocacion
local ASTEROID_PACKING = { minGap = 6, tries = 40 }

-- ---------------------------------------------------------------------
--  Generacion
-- ---------------------------------------------------------------------

math.randomseed(ASTEROID_SEED)

local function randRange(min, max)
  return min + math.random() * (max - min)
end

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
  local frame = math.random(0, ASTEROID_SHEET.variants - 1)
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
      -- Sin animation: el AnimationSystem sobrescribe src_rect.x y se perderia
      -- la variante elegida (ademas los frames 4-8 son la explosion).
    },
  }
end

local function buildAsteroidField()
  local placed = {}
  local asteroids = {}

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

local entities = {
  [0] =
  -- Player
  {
    components = {
      circle_collider =  {
        radius = 8,
        width = 430,
        heigth = 650,
      },
      rigid_body = {
        velocity = { x = 0, y = 0}
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
      script = {
        path = "./assets/scripts/player.lua"
      }
    },
  },
}

-- Los asteroides generados se anexan detras del jugador (indices 1..n)
for _, asteroid in ipairs(buildAsteroidField()) do
  entities[#entities + 1] = asteroid
end

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
  },

  -- Fuentes
  -- El tamaño se fija al cargar: hace falta un fontId por cada tamaño
  fonts = {
    [0] =
    {fontId="default", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=16},
    {fontId="debug-big", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=28},
  },

  -- Keys
  keys = {
    [0] = 
    {name = "accelerate", key=119},
    {name = "brake", key=115},
    {name = "toggle_path", key = 116},
  },

  -- Mouse
  mouse = {
    [0] =
    {name = "shoot", button = 1},
  },

  -- Entities
  entities = entities,
}
