-- Jugador de la casa de Abuela Paula y Abuelo Pepe: copia de house_player.lua SIN `bounds` (la camara se limita al tamano del mapa, 256x176; mama usa 192x144). Original (issue #62): mismo walker que el demo de #61 (WASD / flechas,
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
