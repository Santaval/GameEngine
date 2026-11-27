-- Misiones (issue #51). Docs: games/quebrada/docs/missions.md
-- El estado vive en world_state (sobrevive a las escenas y lo guarda snapshot()):
--   mission.<id>.state    "none"|"offered"|"accepted"|"rejected"|"night_active"|"done"|"failed"
--   mission.<id>.<estado> true solo para el estado actual (legible desde condiciones de Tiled)
--   mission.<id>.outcome  resultado al completar
-- Las definiciones (hooks) son datos de mission_defs.lua y se recargan con cada escena.
local ws = require("world_state")
local logic = require("missions_logic")

local M = {}
M.defs = require("mission_defs")

function M.define(id, def) M.defs[id] = def end

-- Estado actual ("none" si nunca se ofrecio)
function M.state(id) return ws.get(logic.key(id, "state"), "none") end

-- Ids conocidos (definidos o con estado guardado), ordenados
function M.ids()
  local def_ids = {}
  for id in pairs(M.defs) do def_ids[#def_ids + 1] = id end
  return logic.collect_ids(def_ids, ws.flags)
end

-- Escribe estado y booleanos derivados; el flag .state va al final para que los
-- listeners ya vean todo consistente. No ejecuta hooks.
local function set_state(id, state, outcome)
  for _, s in ipairs(logic.STATES) do
    if s ~= "none" then ws.set(logic.key(id, s), (s == state) or nil) end
  end
  if state == "done" then
    if outcome ~= nil then ws.set(logic.key(id, "outcome"), outcome) end
  else
    ws.set(logic.key(id, "outcome"), nil)
  end
  ws.set(logic.key(id, "state"), state)
end

local function fire(id, event, arg)
  local to, err = logic.next_state(M.state(id), event)
  if not to then
    print("[missions] " .. tostring(id) .. ": " .. err)
    return false, err
  end
  set_state(id, to, arg)
  local def = M.defs[id]
  local hook = def and def[logic.HOOKS[event]]
  if hook then
    local ok, e = pcall(hook, id, arg)
    if not ok then print("[missions] hook " .. logic.HOOKS[event] .. " fallo: " .. tostring(e)) end
  end
  return true
end

-- offer es idempotente: si la mision ya se ofrecio, no hace nada ni avisa
function M.offer(id)
  if M.state(id) ~= "none" then return false end
  return fire(id, "offer")
end
function M.accept(id) return fire(id, "accept") end
function M.reject(id) return fire(id, "reject") end
function M.start_night(id) return fire(id, "start_night") end
function M.complete(id, outcome) return fire(id, "complete", outcome) end
function M.fail(id) return fire(id, "fail") end

-- Depuracion: salta a cualquier estado SIN tabla de transiciones y SIN hooks
function M.jump(id, state, outcome)
  if not logic.is_state(state) then
    print("[missions] estado desconocido '" .. tostring(state) .. "'")
    return false
  end
  set_state(id, state, outcome)
  return true
end

-- ---- condiciones como datos: when = mission_done("mona_machete") ----
-- Todas devuelven function() -> bool, evaluada al momento (nunca cacheada).
function M.flag(name) return function() return ws.has(name) end end
function M.not_flag(name) return function() return not ws.has(name) end end

-- true si el estado actual es uno de los dados
function M.mission_is(id, ...)
  local states = { ... }
  return function()
    local s = M.state(id)
    for _, v in ipairs(states) do if v == s then return true end end
    return false
  end
end
-- "Se acepto alguna vez": accepted, night_active, done o failed
function M.mission_accepted(id)
  return M.mission_is(id, "accepted", "night_active", "done", "failed")
end
function M.mission_rejected(id) return M.mission_is(id, "rejected") end
function M.mission_failed(id) return M.mission_is(id, "failed") end
-- outcome opcional: mission_done("chequelo", "detour")
function M.mission_done(id, outcome)
  return function()
    if M.state(id) ~= "done" then return false end
    return outcome == nil or ws.get(logic.key(id, "outcome")) == outcome
  end
end

M.all, M.any, M.not_ = logic.all, logic.any, logic.negate

-- when de un dato (nil = siempre). Acepta function o texto "a,!b" sobre flags.
function M.check(when) return logic.test(when, ws.has) end

return M
