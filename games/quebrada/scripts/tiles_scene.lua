-- Controlador de la escena del tileset (scenes/tiles_demo.lua, issue #55)
update = require("town_controller").make_update({
  map = "maps/tiles_demo.tmx",
  tile_map = true,
  scenes = {
    ["maps/tiles_demo.tmx"] = "scenes/tiles_demo.lua",
  },
})
