-- Prefab de un planeta de los biomas (ver map_biomes.lua). Cada cliente lo crea
-- local con spawn_local desde la semilla (sin red): sin cull (los planetas no
-- duermen, el HUD y las zonas de gravedad los leen siempre) y sin script.
-- state: un planeta de map_biomes.planets (assetId, x, y, scale, mass, range,
-- frame, frame_body_radius).
local field = require("asteroid_field")

return function(state)
  return field.make_planet(state, state.frame, state.frame_body_radius)
end
