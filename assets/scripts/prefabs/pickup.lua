-- Prefab de un pickup de loot (ver docs/lua-api.md, seccion Network). Se arma
-- solo con el estado de spawn, asi que un cliente que entra tarde lo
-- reconstruye igual. pos/vel/rot del estado sobreescriben transform y
-- rigid_body.
-- state: item (nombre), quantity, world.

-- Sprite de cada pickup segun el item que lleva. Lo que no este aqui usa
-- "mineral" (el unico sprite de minerales cargado hoy en la escena)
local PICKUP_SPRITES = {}
local DEFAULT_PICKUP_SPRITE = "mineral"

return function(state)
  state = state or {}
  local item = state.item or "iron"
  local quantity = math.max(1, math.floor(state.quantity or 1))

  return {
    components = {
      transform = {
        position = { x = 0, y = 0 },
        scale = { x = 1, y = 1 },
        rotation = 0,
      },
      rigid_body = {
        velocity = { x = 0, y = 0 },
      },
      sprite = {
        assetId = PICKUP_SPRITES[item] or DEFAULT_PICKUP_SPRITE,
        width = 16,
        height = 16,
        src_rect = { x = 0, y = 0 },
        rotation = 0,
      },
      circle_collider = {
        radius = 8,
        width = 16,
        heigth = 16,
      },
      loot = { [item] = quantity },
      script = {
        path = "./assets/scripts/pickup.lua",
      },
    },
  }
end
