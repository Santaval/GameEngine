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

-- Contenido provisional de cada chunk (asteroides estaticos) hasta que lleguen
-- los biomas: cuantas rocas, separacion minima entre bordes (px) y escala
config.PLACEHOLDER_ROCKS = { min = 4, max = 8 }
config.ROCK_MIN_GAP = 300
config.ROCK_SCALE = { min = 0.6, max = 1.5 }

-- Comprueba que la rejilla es coherente; se llama al cargar el modulo
function config.validate()
  assert(config.SECTOR_SIZE * config.SECTORS == config.WORLD_SIZE,
    "map_config: SECTOR_SIZE * SECTORS debe ser WORLD_SIZE")
  assert(config.CHUNK_SIZE * config.CHUNKS_PER_SECTOR == config.SECTOR_SIZE,
    "map_config: CHUNK_SIZE * CHUNKS_PER_SECTOR debe ser SECTOR_SIZE")
end

config.validate()

return config
