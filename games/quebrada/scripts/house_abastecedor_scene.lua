-- Controlador del interior del abastecedor El Jardín (scenes/house_abastecedor.lua), copia de house_paula_scene.lua.
-- La puerta de salida vuelve al mapa del que se entro (@return). mandados registra lo que pasa al hablar con Doña María.
local mandados = require("mandados")

update = require("town_controller").make_update({
  map = "maps/house_abastecedor.tmx",
  tile_map = true,
  world_debug = false,
  scenes = {
    ["maps/zona1.tmx"] = "scenes/main.lua",
    ["maps/house_abastecedor.tmx"] = "scenes/house_abastecedor.lua",
  },
})
