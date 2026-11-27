-- Controlador de la escena de edificios (scenes/buildings_demo.lua, issue #71)
update = require("town_controller").make_update({
  map = "maps/buildings_demo.tmx",
  tile_map = true,
  world_debug = false,
  scenes = {
    ["maps/buildings_demo.tmx"] = "scenes/buildings_demo.lua",
    ["maps/house_mama.tmx"] = "scenes/house_demo.lua",
  },
})
