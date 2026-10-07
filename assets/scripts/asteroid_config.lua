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

-- Datos del spritesheet ./assets/sprites/asteroid/asteroid.png (768x96)
-- 8 frames de 96x96: los 3 primeros son la roca (sana / agrietada / fundida),
-- los 5 restantes son la explosion.
config.ASTEROID_SHEET = {
  assetId = "asteroid",
  frameSize = 96,
  variants = 3,     -- cuantos frames iniciales se usan como variantes visuales
  bodyRadius = 26,  -- radio de la roca dentro del frame de 96x96
}

-- Vida de un asteroide de escala 1.0: la vida real se escala con el tamano,
-- asi que las rocas grandes aguantan mas balazos que las pequenas
config.ASTEROID_HEALTH = 60

-- Segundos de invulnerabilidad tras cada golpe. Importa sobre todo entre
-- asteroides: se rozan durante muchos frames seguidos y sin ella se
-- pulverizarian al instante
config.ASTEROID_INVULNERABILITY = 0.5

-- Dano que hace un asteroide al estrellarse contra algo con vida
config.ASTEROID_DAMAGE = 20

-- Dano que hace la nave al embestir un asteroide (el asteroide solo suelta
-- loot si lo rompen a tiros, ver asteroid_on_damage en asteroid.lua)
config.SHIP_RAM_DAMAGE = 10

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

-- Elige un tipo de ASTEROID_TYPES respetando los weight
function config.pickAsteroidType()
  local total = 0
  for _, asteroidType in ipairs(config.ASTEROID_TYPES) do
    total = total + asteroidType.weight
  end

  local roll = math.random() * total
  for _, asteroidType in ipairs(config.ASTEROID_TYPES) do
    roll = roll - asteroidType.weight
    if roll < 0 then return asteroidType end
  end

  return config.ASTEROID_TYPES[#config.ASTEROID_TYPES]
end

-- Vida maxima de un asteroide segun su tipo y tamano
function config.healthFor(asteroidType, scale)
  return math.max(1, math.floor(config.ASTEROID_HEALTH * asteroidType.healthMul * scale + 0.5))
end

return config
