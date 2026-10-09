-- =====================================================================
--  Configuracion compartida de los asteroides
--  La usan la escena (campo inicial, scene_01.lua) y los generadores que
--  crean asteroides en runtime (asteroid_spawner.lua), para que el
--  balance (vida, dano, loot, tamanos) viva en un solo lugar.
-- =====================================================================

local config = {}

-- Region (en pixeles de mundo) que ocupa el mapa / campo de asteroides
config.FIELD = {
  x = 0,
  y = 0,
  width = 2000,
  height = 2000,
}

-- Rango de tamanos (escala aplicada al frame del sprite)
config.ASTEROID_SCALE = { min = 0.25, max = 1.5 }

-- Division de rocas grandes: al morir una roca con escala >= MIN_SCALE se
-- parte en PIECES fragmentos del mismo tipo, cada uno de escala
-- padre * SCALE_FACTOR (nunca menos que ASTEROID_SCALE.min; MIN_SCALE *
-- SCALE_FACTOR.min tiene que ser >= ASTEROID_SCALE.min) que salen en
-- abanico con SPEED px/s extra sobre la velocidad del padre. Una roca que se
-- parte no suelta loot: lo sueltan los fragmentos que ya no se pueden partir
config.SPLIT = {
  MIN_SCALE = 0.6,
  PIECES = { min = 2, max = 3 },
  SCALE_FACTOR = { min = 0.45, max = 0.6 },
  SPEED = { min = 30, max = 60 },
}

-- Datos del spritesheet ./assets/sprites/asteroid/asteroid.png (768x96)
-- 8 frames de 96x96: los 3 primeros son la roca (sana / agrietada / fundida),
-- los 5 restantes son la explosion.
config.ASTEROID_SHEET = {
  assetId = "asteroid",
  frameSize = 96,
  variants = 3,     -- cuantos frames iniciales se usan como variantes visuales
  bodyRadius = 26,  -- radio de la roca dentro del frame de 96x96
}

-- Pecios (rocas grandes especiales de los biomas debris y reactor, ver
-- map_chunks.lua): spritesheet de 768x96 como el de los asteroides (3
-- variantes y 5 frames de explosion), pero un solo sprite por pecio. healthMul
-- multiplica la vida y bonus es el loot EXTRA que sueltan al romperse a tiros,
-- ademas de partirse como cualquier roca grande
config.WRECK_SHEET = { frameSize = 96, bodyRadius = 34 }
config.WRECK_TYPES = {
  { assetId = "wreck-cargo-hull", healthMul = 2.5, bonus = { iron = 3, gunpowder = 1 } },
  { assetId = "wreck-robot-arm", healthMul = 2.5, bonus = { plasma = 2, iron = 2 } },
}

-- Vida de un asteroide de escala 1.0: la vida real se escala con el tamano,
-- asi que las rocas grandes aguantan mas balazos que las pequenas
config.ASTEROID_HEALTH = 60

-- Segundos de invulnerabilidad tras cada golpe. Importa sobre todo entre
-- asteroides: se rozan durante muchos frames seguidos y sin ella se
-- pulverizarian al instante
config.ASTEROID_INVULNERABILITY = 0.5

-- Dano maximo que hace un asteroide al estrellarse contra algo con vida (el
-- choque real escala con la velocidad, ver IMPACT_*_SPEED)
config.ASTEROID_DAMAGE = 20

-- Dano maximo que hace la nave al embestir un asteroide (el asteroide solo
-- suelta loot si lo rompen a tiros, ver on_damage en asteroid.lua)
config.SHIP_RAM_DAMAGE = 10

-- Velocidad de impacto (px/s, de cierre a lo largo de la normal entre los
-- centros) que escala el dano de contacto: por debajo de MIN no hay dano (ni
-- invulnerabilidad), en FULL se aplica el dano entero. Los asteroides van a
-- 1-20 px/s y la nave a 100-220 (max_speed 60 + 40 por nivel de motor), asi
-- que casi todo el cierre lo pone la nave: FULL = 200 hace que un choque a
-- velocidad crucero ya sea completo y MIN = 40 deja pasar los roces y los
-- asteroides a la deriva
config.IMPACT_MIN_SPEED = 40
config.IMPACT_FULL_SPEED = 200

-- Tipos de asteroide. weight es la probabilidad relativa de aparicion,
-- frame la variante del spritesheet (0 sana, 1 agrietada, 2 fundida),
-- healthMul multiplica ASTEROID_HEALTH y loot es lo que suelta al morir
-- (nombre de item -> cantidad; los nombres son libres, igual que inventory)
config.ASTEROID_TYPES = {
  { name = "iron", weight = 6, frame = 0, healthMul = 1.0, loot = { iron = 1 } },
  { name = "gunpowder", weight = 3, frame = 1, healthMul = 1.5, loot = { gunpowder = 2 } },
  { name = "plasma", weight = 1, frame = 2, healthMul = 2.0, loot = { plasma = 1, stone = 1 } },
}

-- Gravedad (ver docs/gravity.md). Masa por tipo de cuerpo; los planetas
-- definen la suya en scene_01.lua
config.GRAVITY = {
  -- masa = escala * esto. No se usa aun: los asteroides no atraen
  ASTEROID_MASS_PER_SCALE = 20,
  BULLET = { mass = 1 },
  SHIP = { mass = 10 },
}

function config.randRange(min, max)
  return min + math.random() * (max - min)
end

-- Elige un tipo de ASTEROID_TYPES respetando los weight. Devuelve el tipo y su
-- indice en ASTEROID_TYPES (el indice es lo que viaja por la red, ver
-- prefabs/asteroid.lua)
-- roll01 (opcional, en [0,1)) reemplaza al sorteo: el generador de chunks pasa
-- el suyo para ser determinista desde la semilla. Sin el usa math.random()
function config.pickAsteroidType(roll01)
  local total = 0
  for _, asteroidType in ipairs(config.ASTEROID_TYPES) do
    total = total + asteroidType.weight
  end

  local roll = (roll01 or math.random()) * total
  for index, asteroidType in ipairs(config.ASTEROID_TYPES) do
    roll = roll - asteroidType.weight
    if roll < 0 then return asteroidType, index end
  end

  return config.ASTEROID_TYPES[#config.ASTEROID_TYPES], #config.ASTEROID_TYPES
end

-- Vida maxima de un asteroide segun su tipo y tamano
function config.healthFor(asteroidType, scale)
  return math.max(1, math.floor(config.ASTEROID_HEALTH * asteroidType.healthMul * scale + 0.5))
end

return config
