-- Controlador de la escena del barrio (scenes/town_demo.lua)
update = require("town_controller").make_update({
  map = "maps/town.tmx",
  scenes = {
    ["maps/town.tmx"] = "scenes/town_demo.lua",
    ["maps/house_mama.tmx"] = "scenes/house_demo.lua",
  },
})
