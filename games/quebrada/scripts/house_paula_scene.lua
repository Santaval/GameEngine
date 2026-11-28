-- Controlador de la escena del interior de la casa de Abuela Paula y Abuelo Pepe (scenes/house_paula.lua), copia de house_scene.lua
-- El interior se dibuja con tiles: suelo, pared de madera del fondo y muebles de maps/house_paula.tmx.
-- La puerta de salida vuelve al mapa del que se entro (@return), asi que cada mapa de exterior
-- que tenga una puerta a esta casa debe estar en `scenes`.
update = require("town_controller").make_update({
  map = "maps/house_paula.tmx",
  tile_map = true,
  world_debug = false,
  scenes = {
    ["maps/town.tmx"] = "scenes/town_demo.lua",
    ["maps/buildings_demo.tmx"] = "scenes/buildings_demo.lua",
    ["maps/zona1.tmx"] = "scenes/zona1.lua",
    ["maps/house_paula.tmx"] = "scenes/house_paula.lua",
  },
})
