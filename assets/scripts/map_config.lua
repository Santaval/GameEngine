-- =====================================================================
--  Configuracion del mapa de la Aval Cup: solo datos. Todos los ajustes
--  del mapa viven aqui (ver docs/aval-cup.md); el resto de modulos
--  (map_grid, map_chunks, aval_cup_world, solar_hud) los leen de este archivo.
-- =====================================================================

local config = {}

-- Rejilla del mundo: WORLD_SIZE px por lado = SECTORS x SECTORS sectores de
-- SECTOR_SIZE px, cada uno en CHUNKS_PER_SECTOR x CHUNKS_PER_SECTOR chunks de
-- CHUNK_SIZE px. Un chunk es la unidad que se genera desde la semilla
config.WORLD_SIZE = 20000
config.SECTORS = 5
config.SECTOR_SIZE = 4000
config.CHUNKS_PER_SECTOR = 2
config.CHUNK_SIZE = 2000

-- Franja del borde del mundo (px) que consume la tormenta: no hay contenido
config.STORM_BAND = 500

-- Solo se simulan y se dibujan los chunks a esta distancia (en chunks) del
-- jugador local; el resto duerme (CullComponent, set_active_area)
config.UPDATE_RADIUS_CHUNKS = 2

-- Portales
config.STABLE_PORTAL_PAIRS = 12
config.NEXUS_COUNT = 1
config.PORTAL_CLEAR_RADIUS = 600
config.PORTAL_COOLDOWN = 4
config.PORTAL_EXIT_WARNING = 0.75
config.UNSTABLE_PORTAL_LIFE = { min = 45, max = 75 }

-- Eventos y tormenta (segundos)
config.EVENT_INTERVAL = { min = 60, max = 120 }
config.STORM_CONTRACTION_INTERVAL = { min = 180, max = 240 }
config.STORM_CONTRACTION_SAFE_RADIUS = 1500

-- Jugadores
config.DEATH_DROP_FRACTION = 0.6
config.SPAWN_SHIELD = 5

-- Biomas: cada sector tiene uno (ver map_biomes.lua). weight es la
-- probabilidad relativa de salir. Dos sectores contiguos (vecinos ortogonales,
-- sin diagonales) no repiten bioma salvo BIOME_REPEAT_OK. El sector central
-- es siempre uno de CENTER_BIOMES (lo elige map_biomes antes que el resto)
config.BIOMES = {
  { id = "debris", name = "Debris", weight = 35 },
  { id = "planetary", name = "Planetary", weight = 20 },
  { id = "dense_belt", name = "Dense Belt", weight = 15 },
  { id = "deep_void", name = "Deep Void", weight = 15 },
  { id = "nebula", name = "Nebula", weight = 10 },
  { id = "reactor", name = "Reactor", weight = 5 },
}
config.BIOME_REPEAT_OK = "debris"
config.CENTER_BIOMES = { "planetary", "reactor" }

-- Color de cada bioma en el minimapa (r, g, b)
config.BIOME_COLORS = {
  debris = { 120, 110, 100 },
  planetary = { 60, 140, 200 },
  dense_belt = { 160, 110, 60 },
  deep_void = { 30, 30, 50 },
  nebula = { 150, 80, 170 },
  reactor = { 200, 70, 60 },
}

-- Tamanos de roca (escala aplicada al frame del sprite)
config.ROCK_SIZES = {
  large = { min = 1.0, max = 1.5 },
  medium = { min = 0.6, max = 1.0 },
  small = { min = 0.3, max = 0.6 },
}

-- Rocas grandes por chunk (en dense_belt, LARGE_ROCKS_DENSE) y separacion
-- minima entre sus centros (px, Poisson-disk)
config.LARGE_ROCKS = { min = 4, max = 6 }
config.LARGE_ROCKS_DENSE = { min = 10, max = 14 }
config.LARGE_SPACING = 300

-- Rocas medianas o pequenas por chunk (mitad y mitad; ninguna en deep_void) y
-- separacion minima entre ellas (px)
config.SMALL_ROCKS = { min = 6, max = 10 }
config.SMALL_SPACING = 120

-- Intentos por roca: fijo, para que el resultado sea determinista
config.ROCK_TRIES = 30

-- Rocas a la deriva: probabilidad por roca, velocidad (px/s) e intentos de
-- encontrar un rumbo que no cruce la gravedad de ningun planeta. No se
-- duermen con el culling (ver docs/aval-cup.md)
config.DRIFT = { chance = 0.2, speed = { min = 20, max = 40 }, tries = 12 }

-- Pecios: probabilidad por chunk, solo en estos biomas (una roca grande del
-- chunk pasa a ser un pecio que suelta recursos extra)
config.WRECK_CHANCE = 1 / 3
config.WRECK_BIOMES = { "debris", "reactor" }

-- Planetas de los sectores Planetary: cuantos por sector, separacion entre
-- centros (multiplo de la suma de sus range) e intentos de colocacion.
-- Regla de borde: pedir >= 1 chunk (2000 px) al borde del sector solo deja el
-- centro libre y no caben 1-3 planetas, asi que se exige que TODO el pozo de
-- gravedad quede dentro del sector: centro a >= range + PLANET_EDGE_PAD
config.PLANETS_PER_SECTOR = { min = 1, max = 3 }
config.PLANET_SPACING_FACTOR = 2.5
config.PLANET_TRIES = 40
config.PLANET_EDGE_PAD = 100

-- Punto de aparicion de la nave (centro del mundo, ver scenes/aval_cup.lua) y
-- margen (px) que deja libre alrededor: ningun pozo de gravedad lo cubre, para
-- que nadie nazca dentro de un planeta. El sector central casi siempre es
-- Planetary
config.PLAYER_SPAWN = { x = config.WORLD_SIZE / 2, y = config.WORLD_SIZE / 2 }
config.SPAWN_CLEAR_PAD = 300

-- Rol de cada planeta (peso relativo). Solo mining mantiene el mineral; el
-- comportamiento de merchant y tech llega en otros issues
config.PLANET_ROLES = {
  { id = "mining", weight = 3 },
  { id = "merchant", weight = 1 },
  { id = "tech", weight = 1 },
}

-- Comprueba que la rejilla es coherente; se llama al cargar el modulo
function config.validate()
  assert(config.SECTOR_SIZE * config.SECTORS == config.WORLD_SIZE,
    "map_config: SECTOR_SIZE * SECTORS debe ser WORLD_SIZE")
  assert(config.CHUNK_SIZE * config.CHUNKS_PER_SECTOR == config.SECTOR_SIZE,
    "map_config: CHUNK_SIZE * CHUNKS_PER_SECTOR debe ser SECTOR_SIZE")
end

config.validate()

return config
