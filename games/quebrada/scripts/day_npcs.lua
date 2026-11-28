-- Vecinos del dia en la zona 1. Por ahora: el que grita "come mono" en el camino al abastecedor
-- mientras la mision de las papas esta activa. Al acercarse el jugador salta solo un dialogo
-- (una vez); el jugador piensa su respuesta. tick(dt) lo llama el controlador (cfg.on_tick).
local ws = require("world_state")
local missions = require("missions")
local tod = require("time_of_day")
local dialogue = require("dialogue")
local npc = require("npc_placeholder")
local interaction = require("interaction")

local M = {}

-- Acera norte de la calle principal, unos 400 px antes del abastecedor viniendo de la casa de mama
M.COME_MONO = { id = "vecino", x = 5788, y = 1782, dir = "right", near = 150 }

-- Papa, en el patio de la casa de mama (yard de lastre al sur de la puerta, a la derecha de ella).
-- Esta mientras la mision `papa` (avisarle de la comida) o `escalera` este activa; al acercarse
-- con `papa` activa salta solo el dialogo (una vez) y mandados.after_papa abre la mision de la escalera
M.PAPA = { id = "papa", x = 9060, y = 2012, dir = "left", near = 70 }

local entity = nil
local papa, papa_item = nil, nil

local function should_exist()
  return missions.state("papas") == "accepted" and tod.get() == "day"
end

local function tick_papa()
  local want = (missions.state("papa") == "accepted" or missions.state("escalera") == "accepted") and tod.get() == "day"
  if want and not papa then
    papa = npc.spawn(M.PAPA)
    papa_item = interaction.register({
      entity = papa, size = { npc.SPRITE_W, npc.SPRITE_H }, radius = 40, label = "Hablar", target = "Papá",
      -- Solo se le habla (E) para el recordatorio de la escalera; antes de eso no hay nada que decir
      enabled = function() return missions.state("escalera") == "accepted" end,
      on_interact = function() dialogue.start(dialogue.scripts.papa) end,
    })
  elseif not want and papa then
    interaction.unregister(papa_item)
    pcall(destroy_entity, papa)
    papa, papa_item = nil, nil
  end
  if not papa or missions.state("papa") ~= "accepted" or ws.has("papa.avisado") or not player_entity then return end
  if dialogue.is_open() or tod.is_busy() then return end
  local px, py = get_position(player_entity)
  local dx, dy = (px + 12) - (M.PAPA.x + 12), (py + 32) - (M.PAPA.y + 34)
  if dx * dx + dy * dy <= M.PAPA.near ^ 2 then
    ws.set("papa.avisado", true)
    dialogue.start(dialogue.scripts.papa_patio, { on_end = require("mandados").after_papa })
  end
end

function M.tick(dt)
  tick_papa()
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
