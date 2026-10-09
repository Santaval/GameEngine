-- =====================================================================
--  Escena de la Aval Cup: mapa de 20 000 x 20 000 px (rejilla de sectores y
--  chunks, ver docs/aval-cup.md). El contenido no vive aqui: lo genera
--  aval_cup_world.lua a partir de la semilla de la partida: cada sector tiene
--  un bioma (map_biomes.lua) y cada chunk su campo de rocas, con algunas a la
--  deriva y pecios (map_chunks.lua).
-- =====================================================================

local cfg = require("asteroid_config")
local map = require("map_config")

-- Globals para los modulos del jugador, el minimapa y los asteroides.
-- scene_planets lo llena aval_cup_world.lua con los planetas de los sectores
-- Planetary (solar_hud y las zonas de gravedad del jugador lo leen)
scene_planets = {}
scene_map = map

-- Estado compartido del mundo en red (lo rellenan asteroid.lua y
-- remote_player.lua). Se reinicia al cargar la escena para no arrastrar ids
-- de la partida anterior. map_destroyed: ids de rocas de chunk ya destruidas
drifting_asteroids = {}
ring_slots = {}
player_ships = {}
map_destroyed = {}

-- Sin cinturones ni generadores: nadie crea asteroides en runtime salvo los
-- fragmentos de una roca partida
scene_initial_asteroids = nil
scene_asteroid_generators = nil

-- Circulo que cubre el cuadrado del mundo: los fragmentos que salen de el se borran
scene_bounds = { x = map.WORLD_SIZE / 2, y = map.WORLD_SIZE / 2, radius = map.WORLD_SIZE * 0.75 }

-- La nave sale en el centro del mundo (las reglas de aparicion llegan despues)
local SPAWN = map.PLAYER_SPAWN

-- ---------------------------------------------------------------------
--  Jugador (mismo que solar_system.lua salvo la posicion)
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
        player = true,
      },
      damage = {
        amount = cfg.SHIP_RAM_DAMAGE,
        min_impact_speed = cfg.IMPACT_MIN_SPEED,
        full_impact_speed = cfg.IMPACT_FULL_SPEED,
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

entities[0] = player

-- Directores invisibles (solo script)
local DIRECTORS = {
  "./assets/scripts/aval_cup_world.lua",
  "./assets/scripts/solar_hud.lua",
  "./assets/scripts/map_visuals.lua",
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
    {assetId="spaceship-movement", filePath="./assets/sprites/spaceship/player/movement.png"},
    {assetId="bullet", filePath="./assets/sprites/bullets/bullets.png"},
    {assetId="asteroid", filePath="./assets/sprites/asteroid/asteroid.png"},
    {assetId="wreck-cargo-hull", filePath="./assets/sprites/asteroid/wreck_cargo_hull.png"},
    {assetId="wreck-robot-arm", filePath="./assets/sprites/asteroid/wreck_robot_arm.png"},
    {assetId="drift-dust", filePath="./assets/sprites/vfx/drift_dust.png"},
    {assetId="mineral", filePath="./assets/sprites/minerals/tech.png"},
    {assetId="planet-iron", filePath="./assets/sprites/planets/iron.png"},
    {assetId="planet-gunpowder", filePath="./assets/sprites/planets/gunpowder.png"},
    {assetId="planet-plasma", filePath="./assets/sprites/planets/plasma.png"},
    {assetId="planet-sun", filePath="./assets/sprites/planets/sun.png"},
    {assetId="bg-default", filePath="./assets/sprites/biomes/bg_default.png"},
    {assetId="bg-void", filePath="./assets/sprites/biomes/bg_void.png"},
    {assetId="bg-dense-belt", filePath="./assets/sprites/biomes/bg_dense_belt.png"},
    {assetId="bg-nebula", filePath="./assets/sprites/biomes/bg_nebula.png"},
    {assetId="bg-reactor", filePath="./assets/sprites/biomes/bg_reactor.png"},
    {assetId="nebula-cloud-01", filePath="./assets/sprites/vfx/nebula_cloud_01.png"},
    {assetId="nebula-cloud-02", filePath="./assets/sprites/vfx/nebula_cloud_02.png"},
    {assetId="nebula-cloud-03", filePath="./assets/sprites/vfx/nebula_cloud_03.png"},
    {assetId="nebula-cloud-04", filePath="./assets/sprites/vfx/nebula_cloud_04.png"},
    {assetId="nebula-vignette", filePath="./assets/sprites/vfx/nebula_vignette.png"},
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
    {name = "toggle_pvp", key = 112},
  },

  mouse = {
    [0] =
    {name = "shoot", button = 1},
  },

  entities = entities,
}
