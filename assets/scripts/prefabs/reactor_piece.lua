-- Prefab de una pieza dibujada de la megaestructura del reactor (ver
-- map_reactor.lua). Solo se ve: la colision la ponen los circulos de
-- reactor_collider.lua. Cada cliente la crea local con spawn_local, sin red.
-- state: una pieza de map_reactor.sites (asset, x, y, w, h, rot): x, y es el
-- centro, w, h el tamano dibujado y rot el giro en radianes alrededor del centro.
local data = require("map_reactor_data")

return function(state)
  local asset = data.ASSETS[state.asset]
  -- La escala lleva el frame de la imagen al tamano dibujado; position es la
  -- esquina sup-izq y el giro es alrededor del centro del sprite
  local sx, sy = state.w / asset.w, state.h / asset.h

  return {
    components = {
      transform = {
        position = { x = state.x - state.w / 2, y = state.y - state.h / 2 },
        scale = { x = sx, y = sy },
        rotation = state.rot or 0,
      },
      sprite = {
        assetId = asset.assetId,
        width = asset.w,
        height = asset.h,
        src_rect = { x = 0, y = 0 },
      },
      -- Duerme fuera del area activa (set_active_area), como las rocas del chunk
      cull = true,
    },
  }
end
