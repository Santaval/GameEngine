-- Arranque de la partida (el motor siempre arranca scenes/main.lua):
--   * al abrir el juego, si hay partida guardada se continua automaticamente (la tecla 7 sigue sirviendo);
--   * sin partida, o con la tecla 8 ("nueva partida", borra el progreso), empieza en la casa de mama
--     (chequelo_day.lua).
-- No actua con la mision empezada ni con el atajo de la tecla z (zona1.demo_start).
local ws = require("world_state")
local missions = require("missions")
local save = require("save")

local was_new = false

local function start_new_game()
  ws.restore({})
  ws.set_ctx({})
  time_state = time_state or { phase = "day" }
  time_state.phase, time_state.card = "day", nil
  foco_state = nil -- foco.lua lo recrea con la bateria llena
  ws.set("game.started", true)
  ws.set_ctx({
    arrival = { map = "maps/house_mama.tmx", spawn = "inside_door", facing = "up" },
    return_map = "maps/zona1.tmx", return_spawn = "exit_mama", return_facing = "down",
  })
  save.autosave({ map = "maps/house_mama.tmx", scene = "scenes/house_demo.lua" })
  load_scene("scenes/house_demo.lua")
end

update = function()
  -- Tecla 8: nueva partida (flanco de subida)
  local down = is_action_activated("new_game")
  if down and not was_new then
    was_new = true
    start_new_game()
    return
  end
  was_new = down

  -- Primer frame tras abrir el juego (un global sobrevive a load_scene): continuar si hay partida
  if not boot_checked then
    boot_checked = true
    if ws.has("zona1.demo_start") or ws.has("game.started") or ws.ctx().arrival then return end
    if save.exists() then
      local scene, err = save.load()
      if scene then load_scene(scene); return end
      print("[save] no se pudo continuar: " .. tostring(err))
    end
    if missions.state("chequelo") == "none" then start_new_game() end
  end
end
