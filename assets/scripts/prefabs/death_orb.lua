-- Prefab de un orbe de muerte (#28, ver map_death_drop.lua y docs/aval-cup.md).
-- Se arma solo con el estado de spawn, asi un cliente que entra tarde lo
-- reconstruye igual. pos/vel del estado sobreescriben transform y rigid_body.
-- state: item (mineral), quantity, world.

local cfg = require("map_config")
local D = cfg.DEATH_DROP

return function(state)
  state = state or {}
  local item = state.item or "iron"
  local quantity = math.max(1, math.floor(state.quantity or 1))
  local scale = D.size / D.frame_w

  return {
    components = {
      -- position es la esquina sup-izq; el frame de la hoja se escala a D.size
      transform = {
        position = { x = 0, y = 0 },
        scale = { x = scale, y = scale },
        rotation = 0,
      },
      rigid_body = {
        velocity = { x = 0, y = 0 },
      },
      sprite = {
        assetId = D.orbs[item] or D.orbs.iron,
        width = D.frame_w,
        height = D.frame_h,
        src_rect = { x = 0, y = 0 },
        rotation = 0,
      },
      -- Pulso del orbe
      animation = {
        numFrames = D.frames,
        frameSpeedRate = D.fps,
        isLoop = true,
      },
      circle_collider = {
        radius = D.radius_px,
        width = D.frame_w,
        heigth = D.frame_h,
      },
      loot = { [item] = quantity },
      script = {
        path = "./assets/scripts/death_orb.lua",
      },
    },
  }
end
