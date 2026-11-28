-- Mision "Volver a casa (de noche)" (volver_casa): tras pagar a Doña Maria el jugador camina de noche hasta la casa
-- de mama; al pisar la franja de la entrada de los Caliles sale el simio (simio.lua) y hay que vencerlo; vencido,
-- llegar a la puerta de mama lleva a la casa (chequelo_day.go_home -> mama_simio -> amanecer).
-- Todo en Lua con rects fijos (walkback_logic.lua): no hay triggers ni TMX nuevos. El estado vive en flags de ws:
--   volver.simio_visto, volver.simio_vencido, volver.pendiente (llego a casa), volver.cerrado.
-- tick(dt, idx) y on_door(door) los llama zona1_scene.lua (cfg.on_tick / cfg.on_door).
local ws = require("world_state")
local missions = require("missions")
local tod = require("time_of_day")
local fade = require("fade")
local dialogue = require("dialogue")
local logic = require("walkback_logic")
local simio = require("simio")

local M = {}

local inited = false
local was_in = false
local going = false

local function clear()
  local ok, story = pcall(require, "story")
  local story_open = ok and story.is_open() or false
  return not (dialogue.is_open() or story_open or tod.is_busy() or fade.is_active())
end

function M.active() return missions.state("volver_casa") == "accepted" end

function M.tick(dt, idx)
  if not inited then
    inited = true
    if ws.has("mona.battle") then ws.set("mona.battle", nil) end -- una pelea no se guarda: al cargar se limpia
  end
  simio.tick(dt)
  if not M.active() or not player_entity then was_in = false; return end
  local px, py = get_position(player_entity)
  local fx, fy = px + 12, py + 32
  if not ws.has("volver.simio_vencido") then
    local inb = logic.in_band(fx, fy)
    if inb and not was_in then
      -- Por flanco (was_in nace en false: cargar dentro de la franja tambien empieza la pelea)
      if not simio.is_fighting() and clear() then
        was_in = true
        simio.start(ws.has("volver.simio_visto"))
      end
    elseif not inb then
      was_in = false
    end
  elseif logic.in_home(fx, fy) and not going and clear() then
    going = true
    ws.set("volver.pendiente", true)
    missions.jump("volver_casa", "done", "Le hiciste frente al simio")
    require("chequelo_day").go_home() -- fundido a la casa; autoguarda con volver.pendiente
  end
end

-- La puerta de mama sigue cerrada mientras el simio siga en la entrada de los Caliles
function M.on_door(door)
  if door and door.name == "door_mama" and M.active() and not ws.has("volver.simio_vencido") then
    dialogue.start({ { speaker = "", text = "(No... esa cosa sigue en la entrada de los Caliles. No la voy a traer hasta la casa.)" } })
    return true
  end
  return false
end

return M
