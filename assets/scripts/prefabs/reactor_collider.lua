-- Prefab de un circulo de colision invisible del casco o el anillo del reactor
-- (ver map_reactor.lua). Sin vida ni rigid_body: es indestructible y no se
-- mueve; reactor_hull.lua hace rebotar lo que lo toca. Lleva el mismo dano por
-- impacto que un asteroide, asi que chocar fuerte contra el casco duele.
-- state: un circulo de map_reactor.sites (x, y, r): centro y radio en px de mundo.
local asteroid_cfg = require("asteroid_config")

return function(state)
  -- El motor lee el radio y el ancho como enteros
  local r = math.floor(state.r + 0.5)

  return {
    components = {
      -- position es la esquina sup-izq: el centro del collider queda en (x, y)
      transform = {
        position = { x = state.x - r, y = state.y - r },
        scale = { x = 1, y = 1 },
      },
      circle_collider = {
        radius = r,
        width = 2 * r,
        heigth = 2 * r,
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
