-- Controlador de la escena del interior (scenes/house_demo.lua)
-- El interior se dibuja con tiles (issue #71): suelo, pared del fondo y muebles de maps/house_mama.tmx.
-- La puerta de salida vuelve al mapa del que se entro (@return), asi que cada mapa de exterior
-- que tenga una puerta a esta casa debe estar en `scenes`.
update = require("town_controller").make_update({
  map = "maps/house_mama.tmx",
  tile_map = true,
  world_debug = false,
  scenes = {
    ["maps/town.tmx"] = "scenes/town_demo.lua",
    ["maps/buildings_demo.tmx"] = "scenes/buildings_demo.lua",
    ["maps/zona1.tmx"] = "scenes/zona1.lua",
    ["maps/house_mama.tmx"] = "scenes/house_demo.lua",
  },
})
