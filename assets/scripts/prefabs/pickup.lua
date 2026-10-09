-- Prefab de un pickup de loot (ver docs/lua-api.md, seccion Network). Se arma
-- solo con el estado de spawn, asi que un cliente que entra tarde lo
-- reconstruye igual. pos/vel/rot del estado sobreescriben transform y
-- rigid_body.
-- state: item (nombre), quantity, world.

-- Usa los orbes de los death drops (DEATH_DROP.orbs: color por mineral,
-- animados), mas chicos que un orbe de muerte. Lo que no tenga orbe (p. ej.
-- stone) usa el de iron
local cfg = require("map_config")
local D = cfg.DEATH_DROP

-- Ancho en pantalla; pickup.lua calcula su centro con el mismo valor
local SIZE = 32

return function(state)
  state = state or {}
  local item = state.item or "iron"
  local quantity = math.max(1, math.floor(state.quantity or 1))
  local scale = SIZE / D.frame_w

  return {
    components = {
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
      animation = {
        numFrames = D.frames,
        frameSpeedRate = D.fps,
        isLoop = true,
      },
      circle_collider = {
        -- Entero: el motor rechaza radios con decimales (543 / 2 = 271.5)
        -- y la entidad quedaba a medio construir, sin script
        radius = math.floor(D.frame_w / 2),
        width = D.frame_w,
        heigth = D.frame_h,
      },
      loot = { [item] = quantity },
      script = {
        path = "./assets/scripts/pickup.lua",
      },
    },
  }
end
