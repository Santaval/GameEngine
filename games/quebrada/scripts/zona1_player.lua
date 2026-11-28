-- Jugador de la zona 1 (issue #78): copia de town_player.lua SIN `bounds`: la camara se limita al
-- tamano del mapa cargado (walker.lua usa get_tile_map_size), que aqui es 1920x576.
-- (Texto original, issue #62:) Jugador de la ciudad: mismo walker que el demo de #61 (WASD / flechas,
-- Shift corre) pero publica player_entity y player_walker para que el
-- controlador pueda teletransportarlo y bloquear su input. Se publican en cada
-- frame porque el motor limpia player_entity al cargar una escena.
local fn, obj = require("walker").make_update({
  camera = {
    follow = true,
    deadzone = { w = 24, h = 16 },
    smooth = 10,
    box = { x = 5, y = 28, w = 14, h = 8 }, -- pies del muneco 24x38
  },
  footsteps = { on_state = require("footsteps").on_state }, -- pasos por superficie (issue #65)
})

update = function()
  player_entity = this
  player_walker = obj
  fn()
end
