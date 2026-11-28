-- Partida nueva: el juego arranca en la casa de mama (chequelo_day.lua). Vive en la escena principal
-- (el motor siempre arranca scenes/main.lua). No actua con partida cargada, mision empezada ni el
-- atajo de la tecla z (zona1.demo_start).
local ws = require("world_state")
local missions = require("missions")

local done = false
update = function()
  if done then return end
  done = true
  if ws.has("zona1.demo_start") or ws.has("game.started") or ws.ctx().arrival then return end
  if missions.state("chequelo") ~= "none" then return end
  ws.set("game.started", true)
  ws.set_ctx({
    arrival = { map = "maps/house_mama.tmx", spawn = "inside_door", facing = "up" },
    return_map = "maps/zona1.tmx", return_spawn = "exit_mama", return_facing = "down",
  })
  load_scene("scenes/house_demo.lua")
end
