-- Controlador de la escena del interior (scenes/house_demo.lua)
-- El interior se dibuja con tiles (issue #71): suelo, pared del fondo y muebles de maps/house_mama.tmx.
-- La puerta de salida vuelve al mapa del que se entro (@return), asi que cada mapa de exterior
-- que tenga una puerta a esta casa debe estar en `scenes`.
-- chequelo_day se pide aqui (no solo en el saludo) para registrar dialogue.on_end.mama (issue #82)
local chequelo_day = require("chequelo_day")

update = require("town_controller").make_update({
  map = "maps/house_mama.tmx",
  tile_map = true,
  world_debug = false,
  scenes = {
    ["maps/zona1.tmx"] = "scenes/main.lua",
    ["maps/house_mama.tmx"] = "scenes/house_demo.lua",
  },
  -- Al entrar: saludo de mama si es de dia y aun no se decidio (issue #82)
  on_start = function() chequelo_day.maybe_greet() end,
})
