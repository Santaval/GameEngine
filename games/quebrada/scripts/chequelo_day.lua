-- Dia del chequelo (issue #82): la casa de mama de dia, la historia y la mision. Pegamento
-- entre dialogos, libreta, guardado y fundido; la logica de la mision esta en mission_defs.lua.
-- Los requires de los dialogos van dentro de las funciones (dialogues.lua pide este modulo).
-- Docs: games/quebrada/docs/missions.md
local ws = require("world_state")
local missions = require("missions")
local save = require("save")
local libreta = require("libreta")
local dialogue = require("dialogue")
local fade = require("fade")
local tod = require("time_of_day")

local M = {}

-- Destino que se lleva al terminar la conversacion: "church" = fundido a la iglesia
local pending = nil

-- La historia entra en la libreta aunque el jugador nunca la haya escuchado
local function record_story()
  if not ws.has("story.chequelo.started") then
    ws.set("story.chequelo.started", true)
    libreta.notify() -- historia nueva en la libreta (issue #80)
  end
end

-- "Mejor no": la historia queda en la libreta y se guarda la decision
function M.on_reject()
  record_story()
  save.autosave()
end

-- "Sí, voy esta noche": solo se anota; el fundido sale al terminar la conversacion
function M.go_to_church()
  pending = "church"
end

-- Fin de la conversacion con mama (dialogue.on_end). Si se acepto, fundido a la iglesia:
-- la llegada a walk_start (zona1) empieza la noche. Si la conversacion se corto a medias,
-- igualmente se va (pending ya esta puesto)
function M.after_talk()
  if pending ~= "church" then return end
  pending = nil
  record_story()
  if player_walker then player_walker.input = function() return 0, 0, false end end
  fade.start_out(function()
    ws.set_ctx({ arrival = { map = "maps/zona1.tmx", spawn = "default" } })
    save.autosave({ map = "maps/zona1.tmx", scene = "scenes/main.lua" })
    load_scene("scenes/main.lua")
  end)
end

-- Al entrar de dia y sin decidir: saludo de mama (una vez)
function M.maybe_greet()
  if tod.get() ~= "day" then return end
  local s = missions.state("chequelo")
  if s ~= "none" and s ~= "offered" then return end
  if ws.has("mama.saludada") then return end
  dialogue.start(dialogue.scripts.mama_saludo)
end

dialogue.on_end.mama = M.after_talk

return M
