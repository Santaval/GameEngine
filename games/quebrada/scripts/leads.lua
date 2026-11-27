-- Pistas de boca en boca (issue #69). Docs: games/quebrada/docs/leads.md
-- Al resolverse una leyenda se elige su regla `next`, se aplican los unlocks como flags,
-- se anota la pista en la libreta y se muestra la linea. Todo el estado vive en world_state.
local logic = require("leads_logic")
local slogic = require("story_logic")
local ws = require("world_state")
local missions = require("missions")
local libreta = require("libreta")

local M = {}
M.say = nil -- fn(texto): la conecta el controlador en cada escena
M.legends = require("legend_index")

local function by_id(id)
  for _, lg in ipairs(M.legends) do if lg.id == id then return lg end end
  return nil
end

function M.is_resolved(id) return ws.has(logic.key_resolved(id)) end
function M.has_unlock(key) return ws.has(logic.key_unlock(key)) end

-- Resuelve una leyenda una sola vez. Devuelve true si aplico algo nuevo.
function M.resolve(id)
  local lg = by_id(id)
  if not lg or M.is_resolved(id) then return false end
  ws.set(logic.key_resolved(id), true) -- primero: idempotente aunque algo falle despues
  local idx, rule = logic.pick_rule(logic.rules(lg.next), missions.check)
  if not rule then return false end
  ws.set(logic.key_rule(id), idx)
  for _, k in ipairs(rule.unlocks or {}) do
    if logic.valid_unlock_key(k) then
      ws.set(logic.key_unlock(k), true)
      ws.set(logic.key_mark(k), true)
    else
      print("[leads] unlock invalido '" .. tostring(k) .. "' en " .. id)
    end
  end
  if rule.person then ws.set(logic.key_person(rule.person), true) end
  if rule.line and rule.line ~= "" then
    if rule.person then libreta.add_lead(id, rule.line, rule.person, id) end
    if M.say then M.say(rule.line) else print("[leads] " .. rule.line) end
  end
  return true
end

-- Por frame. ctx.hidden = pantalla ocupada (no se resuelve: la linea no debe pisar el
-- dialogo). Como mucho una leyenda por frame.
function M.tick(ctx)
  if ctx.hidden then return end
  for _, lg in ipairs(M.legends) do
    if lg.id and not M.is_resolved(lg.id) then
      local st = { heard = ws.has(slogic.key(lg.id, "heard")) }
      if lg.mission_offer then st.mission_state = missions.state(lg.mission_offer) end
      if lg.resolve_when ~= nil then st.when_ok = missions.check(lg.resolve_when) end
      if logic.should_resolve(lg, st) then
        M.resolve(lg.id)
        return
      end
    end
  end
end

-- Visitar una puerta o zona con marcador apaga el marcador (key = "house.x" | "zone.x")
function M.visit(key)
  if ws.has(logic.key_mark(key)) and not ws.has(logic.key_seen(key)) then
    ws.set(logic.key_seen(key), true)
  end
end

-- Marcador sutil: puntito que sube y baja sobre el objeto. markers viene de logic.index_map
function M.draw_markers(markers, t)
  for _, mk in ipairs(markers) do
    if logic.marker_visible(mk.key, ws.has) then
      draw_rect_world(math.floor(mk.x) - 1, math.floor(mk.y) - 8 + logic.marker_bob(t), 3, 3,
                      255, 220, 80, logic.marker_alpha(t), true)
    end
  end
end

-- Validacion al arrancar: avisa por consola (el validador offline hace lo mismo con mas detalle)
function M.validate()
  local errors, warns = logic.validate(M.legends, logic.ROOT)
  for _, e in ipairs(errors) do print("[leads] ERROR: " .. e) end
  for _, w in ipairs(warns) do print("[leads] aviso: " .. w) end
  return #errors == 0
end

return M
