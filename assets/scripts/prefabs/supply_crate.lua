-- Prefab del contenedor de suministros (#27, ver map_supply_world.lua). Igual
-- que loot_crate_pal.lua pero con la hoja supply_crate.png y un solo recurso:
-- el loot sale del estado de spawn, asi que un cliente que entra tarde (o el
-- host nuevo tras migrar) lo reconstruye igual. pos del estado sobreescribe el
-- transform (esquina sup-izq). Sin rigid_body: se queda quieta. Frame 0 de la
-- hoja; la animacion de apertura la dibuja map_supply_world.lua.
-- state: pos, world, kind ("supply"), slot ("sx:sy"), item, quantity.
local cfg = require("map_config")

local S = cfg.SUPPLY_CRATE

return function(state)
  state = state or {}
  local sheet = S.sheet
  local scale = S.size / sheet.frame_w
  local item = state.item or S.items[1]
  local quantity = state.quantity or S.quantity.min

  return {
    components = {
      transform = {
        position = { x = 0, y = 0 },
        scale = { x = scale, y = scale },
        rotation = 0,
      },
      sprite = {
        assetId = "supply-crate",
        width = sheet.frame_w,
        height = sheet.src_h,
        src_rect = { x = 0, y = sheet.src_y },
        rotation = 0,
      },
      circle_collider = {
        radius = S.radius,
        width = sheet.frame_w,
        heigth = sheet.src_h,
      },
      loot = { [item] = quantity },
      script = {
        path = "./assets/scripts/loot_crate.lua",
      },
    },
  }
end
