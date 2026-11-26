-- Controlador de la escena del interior (scenes/house_demo.lua)
update = require("town_controller").make_update({
  map = "maps/house_mama.tmx",
  scenes = {
    ["maps/town.tmx"] = "scenes/town_demo.lua",
    ["maps/house_mama.tmx"] = "scenes/house_demo.lua",
  },
})
