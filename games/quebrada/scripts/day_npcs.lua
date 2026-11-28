-- Vecinos del dia en la zona 1. Por ahora: el que grita "come mono" en el camino al abastecedor
-- mientras la mision de las papas esta activa. Al acercarse el jugador salta solo un dialogo
-- (una vez); el jugador piensa su respuesta. tick(dt) lo llama el controlador (cfg.on_tick).
local ws = require("world_state")
local missions = require("missions")
local tod = require("time_of_day")
local dialogue = require("dialogue")
local npc = require("npc_placeholder")

local M = {}

-- Acera norte de la calle principal, unos 400 px antes del abastecedor viniendo de la casa de mama
M.COME_MONO = { id = "vecino", x = 5788, y = 1782, dir = "right", near = 150 }

local entity = nil

local function should_exist()
  return missions.state("papas") == "accepted" and tod.get() == "day"
end

function M.tick(dt)
  local want = should_exist()
  if want and not entity then
    entity = npc.spawn(M.COME_MONO)
  elseif not want and entity then
    pcall(destroy_entity, entity)
    entity = nil
  end
  if not entity or ws.has("papas.comemono") or not player_entity then return end
  if dialogue.is_open() or tod.is_busy() then return end
  local px, py = get_position(player_entity)
  local dx, dy = (px + 12) - (M.COME_MONO.x + 12), (py + 32) - (M.COME_MONO.y + 34)
  if dx * dx + dy * dy <= M.COME_MONO.near ^ 2 then
    ws.set("papas.comemono", true)
    dialogue.start(dialogue.scripts.come_mono)
  end
end

return M
