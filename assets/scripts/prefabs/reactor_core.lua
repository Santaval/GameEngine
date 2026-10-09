-- Prefab del nucleo del reactor (ver map_reactor.lua): la hoja reactor-pulse
-- (4 x 2 frames de core_frame px) a tamano core_size, con un collider central.
-- No lleva animation: map_reactor_world.lua elige el frame con
-- set_sprite_frame segun el estado (reposo, carga, onda).
-- state: site.core de map_reactor.sites (x, y, size), el centro y el tamano dibujado.
local cfg = require("map_config")
local asteroid_cfg = require("asteroid_config")
local data = require("map_reactor_data")

local R = cfg.REACTOR

return function(state)
  local frame = R.core_frame
  local scale = state.size / frame
  -- Radio del collider (CORE_RADIUS del tamano dibujado) en px del frame: el motor lo
  -- multiplica por la escala
  local radius = math.floor(data.CORE_RADIUS * frame + 0.5)

  return {
    components = {
      transform = {
        position = { x = state.x - state.size / 2, y = state.y - state.size / 2 },
        scale = { x = scale, y = scale },
      },
      sprite = {
        assetId = "reactor-pulse",
        width = frame,
        height = frame,
        src_rect = { x = 0, y = 0 },
      },
      circle_collider = {
        radius = radius,
        width = frame,
        heigth = frame,
      },
      damage = {
        amount = asteroid_cfg.ASTEROID_DAMAGE,
        min_impact_speed = asteroid_cfg.IMPACT_MIN_SPEED,
        full_impact_speed = asteroid_cfg.IMPACT_FULL_SPEED,
      },
      script = {
        path = "./assets/scripts/reactor_hull.lua",
      },
      cull = true,
    },
  }
end
