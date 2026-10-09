-- Prefab de la caja de loot alto de Pal (#25, ver map_storm_contraction.lua).
-- Se arma solo con el estado de spawn, asi que un cliente que entra tarde la
-- reconstruye igual. pos del estado sobreescribe el transform (esquina sup-izq).
-- Sin rigid_body: se queda quieta. Muestra el frame 0 de la hoja (la animacion
-- de apertura llega con #27). El loot sale de LOOT_CRATE_PAL.
-- state: world.
local cfg = require("map_config")

local L = cfg.LOOT_CRATE_PAL

return function(state)
  local sheet = L.sheet
  local scale = L.size / sheet.frame_w

  return {
    components = {
      transform = {
        position = { x = 0, y = 0 },
        scale = { x = scale, y = scale },
        rotation = 0,
      },
      sprite = {
        assetId = "loot-crate-pal",
        width = sheet.frame_w,
        height = sheet.src_h,
        src_rect = { x = 0, y = sheet.src_y },
        rotation = 0,
      },
      circle_collider = {
        radius = L.radius,
        width = sheet.frame_w,
        heigth = sheet.src_h,
      },
      loot = L.loot,
      script = {
        path = "./assets/scripts/loot_crate.lua",
      },
    },
  }
end
