-- Jugador del demo de walker (issue #61): WASD / flechas, Shift corre.
-- Caja de pies 10x8 en (3,8) dentro del frame de 16x16; la camara sigue esa caja
-- y se limita al mundo de 640x480. Cada paso imprime el pie (aqui ira el audio).
local walk_update = require("walker").make_update({
  camera = {
    follow = true,
    deadzone = { w = 24, h = 16 },
    smooth = 10,
    box = { x = 3, y = 8, w = 10, h = 8 },
    bounds = { x = 0, y = 0, w = 640, h = 480 },
  },
  footsteps = {
    frames = { 1, 3 },
    on_footstep = function(e, foot) print("[walker] step " .. foot) end,
  },
})

-- El jugador es el oyente del audio espacial (issue #63)
update = function()
  player_entity = this
  walk_update()
end
