-- Controlador de la escena del interior (scenes/house_demo.lua)
-- El interior se dibuja con tiles (issue #71): suelo, pared del fondo y muebles de maps/house_mama.tmx.
-- La puerta de salida vuelve al mapa del que se entro (@return), asi que cada mapa de exterior
-- que tenga una puerta a esta casa debe estar en `scenes`.
-- Inicio de la partida (chequelo_day): mama manda a misa, indicador en la puerta, aviso de la luz y bendicion
local chequelo_day = require("chequelo_day")
local mandados = require("mandados") -- registra dialogue.on_end.mama (entrega de las papas)

update = require("town_controller").make_update({
  map = "maps/house_mama.tmx",
  tile_map = true,
  world_debug = false,
  scenes = {
    ["maps/zona1.tmx"] = "scenes/main.lua",
    ["maps/house_mama.tmx"] = "scenes/house_demo.lua",
    ["maps/house_abastecedor.tmx"] = "scenes/house_abastecedor.lua",
  },
  on_start = function()
    chequelo_day.on_start()
    mandados.on_enter_home() -- entrega de las papas al entrar (mission papas)
  end,
  on_tick = chequelo_day.tick,
  on_door = chequelo_day.on_door,
})
