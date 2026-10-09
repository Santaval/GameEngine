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
-- Sitios del Reactor Remains: los publica map_reactor_world.lua (el minimapa los lee)
reactor_sites = nil
-- Tormentas errantes (#21): netId -> true / netId -> radio; las llena wandering_storm.lua
wandering_storms = {}
wandering_storm_radius = {}
-- Portales estables (#22): los pares los publica map_portal_world.lua (el
-- minimapa los lee); local_portal_transit lo lee player.lua
portal_sites = nil
local_portal_transit = false
-- Escudo de aparicion (#28): lo lleva map_spawn.lua
local_spawn_shield = false
-- Ranking (#29): lo lleva map_ranking.lua. ranking_scores es playerId ->
-- {total, t}, ranking_list los primeros {id, total} y ranking_leader el id del
-- lider (nil si nadie tiene minerales)
ranking_scores = {}
ranking_list = {}
ranking_leader = nil
-- Portales inestables (#23): netId -> {x, y, life, age}, los llena
-- unstable_portal.lua; unstable_portal_life_fix: netId -> vida que corrige un
-- recien llegado (map_portal_world.lua)
unstable_portals = {}
unstable_portal_life_fix = {}
-- Eventos del mapa (#24): map_events es id -> evento activo (lo lleva
-- map_event_director.lua en todos los clientes; el minimapa lo lee) y
-- map_event_types el registro de tipos: cada script que implementa un evento
-- registra aqui su pick / fire (ver docs/aval-cup.md)
map_events = {}
map_event_types = {}
-- Cajas de loot (#27): loot_crates es clave (netId, o la entidad sin red) ->
-- {e, x, y, kind, slot}, lo llena loot_crate.lua; supply_opened es slot ->
-- instante (reloj de map_supply_world.lua) en que se abrio el contenedor
loot_crates = {}
supply_opened = {}

-- Sin cinturones ni generadores: nadie crea asteroides en runtime salvo los
-- fragmentos de una roca partida
scene_initial_asteroids = nil
scene_asteroid_generators = nil

-- Circulo que cubre el cuadrado del mundo: los fragmentos que salen de el se borran
scene_bounds = { x = map.WORLD_SIZE / 2, y = map.WORLD_SIZE / 2, radius = map.WORLD_SIZE * 0.75 }

-- La nave nace aqui (centro del mundo) y map_spawn.lua (#28) la mueve a su
-- punto de aparicion en cuanto llegan la semilla y los portales
local SPAWN = map.PLAYER_SPAWN

-- ---------------------------------------------------------------------
--  Jugador (la nave local de cada cliente; las demas llegan por red como
--  remote_player.lua)
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
        max_speed=140
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
  "./assets/scripts/map_reactor_world.lua",
  "./assets/scripts/solar_hud.lua",
  "./assets/scripts/map_visuals.lua",
  "./assets/scripts/map_storm_world.lua",
  "./assets/scripts/map_portal_world.lua",
  "./assets/scripts/map_spawn.lua",
  "./assets/scripts/map_ranking.lua",
  "./assets/scripts/map_event_world.lua",
  "./assets/scripts/map_event_director.lua",
  "./assets/scripts/map_supply_world.lua",
  "./assets/scripts/map_death_drop.lua",
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
    {assetId="reactor-hull-01", filePath="./assets/sprites/reactor/reactor_hull_01.png"},
    {assetId="reactor-hull-02", filePath="./assets/sprites/reactor/reactor_hull_02.png"},
    {assetId="reactor-hull-03", filePath="./assets/sprites/reactor/reactor_hull_03.png"},
    {assetId="reactor-hull-04", filePath="./assets/sprites/reactor/reactor_hull_04.png"},
    {assetId="reactor-ring", filePath="./assets/sprites/reactor/reactor_ring.png"},
    {assetId="storm-tile", filePath="./assets/sprites/storm/storm_tile.png"},
    {assetId="storm-edge", filePath="./assets/sprites/storm/storm_edge.png"},
    {assetId="icon-storm", filePath="./assets/sprites/hud/icon_storm.png"},
    {assetId="reactor-pulse", filePath="./assets/sprites/vfx/reactor_pulse.png"},
    {assetId="portal-stable", filePath="./assets/sprites/portals/portal_stable.png"},
    {assetId="portal-exit-flash", filePath="./assets/sprites/portals/portal_exit_flash.png"},
    {assetId="portal-warning-halo", filePath="./assets/sprites/portals/portal_warning_halo.png"},
    {assetId="portal-warp", filePath="./assets/sprites/vfx/portal_warp.png"},
    {assetId="portal-unstable", filePath="./assets/sprites/portals/portal_unstable.png"},
    {assetId="portal-open", filePath="./assets/sprites/portals/portal_open.png"},
    {assetId="portal-collapse", filePath="./assets/sprites/portals/portal_collapse.png"},
    {assetId="nexus", filePath="./assets/sprites/portals/nexus.png"},
    {assetId="icon-portal-unstable", filePath="./assets/sprites/hud/icon_portal_unstable.png"},
    {assetId="icon-nexus", filePath="./assets/sprites/hud/icon_nexus.png"},
    {assetId="event-banner", filePath="./assets/sprites/hud/event_banner.png"},
    {assetId="loot-crate-pal", filePath="./assets/sprites/items/loot_crate_pal.png"},
    {assetId="supply-crate", filePath="./assets/sprites/items/supply_crate.png"},
    {assetId="icon-event-contraction", filePath="./assets/sprites/hud/icon_event_contraction.png"},
    {assetId="icon-event-pal-signal", filePath="./assets/sprites/hud/icon_event_pal_signal.png"},
    {assetId="icon-event-debris", filePath="./assets/sprites/hud/icon_event_debris.png"},
    {assetId="pal-beacon", filePath="./assets/sprites/vfx/pal_beacon.png"},
    {assetId="debris-arrow", filePath="./assets/sprites/hud/debris_arrow.png"},
    {assetId="aura-overcharged", filePath="./assets/sprites/vfx/aura_overcharged.png"},
    {assetId="orb-protection", filePath="./assets/sprites/items/orb_protection.png"},
    {assetId="orb-weapon", filePath="./assets/sprites/items/orb_weapon.png"},
    {assetId="orb-propulsion", filePath="./assets/sprites/items/orb_propulsion.png"},
    {assetId="spawn-shield", filePath="./assets/sprites/vfx/spawn_shield.png"},
    {assetId="ranking-panel", filePath="./assets/sprites/hud/ranking_panel.png"},
    {assetId="icon-leader", filePath="./assets/sprites/hud/icon_leader.png"},
    {assetId="leader-crown", filePath="./assets/sprites/hud/leader_crown.png"},
  },

  -- El tamaño se fija al cargar: hace falta un fontId por cada tamaño
  fonts = {
    [0] =
    {fontId="default", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=16},
    {fontId="debug-big", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=28},
    {fontId="title", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=56},
    {fontId="small", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=10},
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
    {name = "debug_pulse", key = 107},
    {name = "debug_collapse", key = 108},
    {name = "debug_event", key = 106},
  },

  mouse = {
    [0] =
    {name = "shoot", button = 1},
  },

  entities = entities,
}
