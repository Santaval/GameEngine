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

-- Lito, en el patio de su casa (lastre delante de la puerta de maps/zona1.tmx, LITO_AT). Esta mientras la mision
-- `lito` este activa o terminada (de dia). Hablarle: flag lito.visitado (llegar tarde con las papas) y la historia
M.LITO = { id = "lito", x = 5356, y = 2678, dir = "down" }
local lito, lito_item = nil, nil

-- Tio Enrique, en el patio de su casa (casa_2 al sur de la calle principal, puerta en x 8368-8400, y 2160). Esta
-- mientras la mision `escalera` o `camisa_blanca` este activa o terminada (de dia). Hablarle: presta la escalera
-- (flag escalera.conseguida) y cuenta la historia de la camisa blanca (legends/camisa_blanca.lua)
M.ENRIQUE = { id = "enrique", x = 8408, y = 2156, dir = "down" }
local enrique, enrique_item = nil, nil

local entity = nil
local papa, papa_item = nil, nil

local function should_exist()
  return missions.state("papas") == "accepted" and tod.get() == "day"
end

local function tick_enrique()
  local want = false
  for _, id in ipairs({ "escalera", "camisa_blanca" }) do
    local st = missions.state(id)
    if st == "accepted" or st == "done" then want = true end
  end
  want = want and tod.get() == "day"
  if want and not enrique then
    enrique = npc.spawn(M.ENRIQUE)
    enrique_item = interaction.register({
      entity = enrique, size = { npc.SPRITE_W, npc.SPRITE_H }, radius = 40, label = "Hablar", target = "Tío Enrique",
      on_interact = function()
        if dialogue.is_open() then return end
        ws.set("escalera.conseguida", true) -- presta la escalera de papa
        require("story").listen("camisa_blanca")
      end,
    })
  elseif not want and enrique then
    interaction.unregister(enrique_item)
    pcall(destroy_entity, enrique)
    enrique, enrique_item = nil, nil
  end
end

local function tick_lito()
  local st = missions.state("lito")
  local want = (st == "accepted" or st == "done") and tod.get() == "day"
  if want and not lito then
    lito = npc.spawn(M.LITO)
    lito_item = interaction.register({
      entity = lito, size = { npc.SPRITE_W, npc.SPRITE_H }, radius = 40, label = "Hablar", target = "Lito",
      on_interact = function()
        if dialogue.is_open() then return end
        ws.set("lito.visitado", true) -- fue donde Lito: si aun no entrego las papas, llega tarde (mandados.lua)
        require("story").listen("come_monos")
      end,
    })
  elseif not want and lito then
    interaction.unregister(lito_item)
    pcall(destroy_entity, lito)
    lito, lito_item = nil, nil
  end
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
  if not papa or not player_entity then return end
  if dialogue.is_open() or tod.is_busy() then return end
  local px, py = get_position(player_entity)
  local dx, dy = (px + 12) - (M.PAPA.x + 12), (py + 32) - (M.PAPA.y + 34)
  if dx * dx + dy * dy > M.PAPA.near ^ 2 then return end
  if missions.state("papa") == "accepted" and not ws.has("papa.avisado") then
    ws.set("papa.avisado", true)
    dialogue.start(dialogue.scripts.papa_patio, { on_end = require("mandados").after_papa })
  elseif missions.state("escalera") == "accepted" and ws.has("escalera.conseguida") and not ws.has("papa.escalera") then
    -- Vuelve con la escalera: se cierra la mision y papa abre la charla del hombre de camisa blanca
    ws.set("papa.escalera", true)
    dialogue.start(dialogue.scripts.papa_mono, { on_end = require("mandados").after_papa_escalera })
  end
end

function M.tick(dt)
  require("mandados").tick()
  -- Tras el teletransporte al centro del pueblo (mandados.go_pay_maria) se hace de noche
  if ws.has("noche.pendiente") and not tod.is_busy() and not require("fade").is_active() then
    ws.set("noche.pendiente", nil)
    tod.set("night", { title = "Esa noche..." })
  end
  tick_papa()
  tick_lito()
  tick_enrique()
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
