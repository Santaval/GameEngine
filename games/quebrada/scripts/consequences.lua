-- Consecuencias de las decisiones (issue #70). Docs: games/quebrada/docs/consequences.md
-- El dia es el flag `day` (world_state, se guarda con snapshot). Los comentarios de NPC son
-- datos de consequences_data.lua y se anteponen al guion base en dialogue.attach.
local ws = require("world_state")
local missions = require("missions")
local mlogic = require("missions_logic")
local logic = require("consequences_logic")

local M = {}
M.entries = require("consequences_data")

function M.day() return missions.day() end

-- Llamar al cargar la escena: garantiza que el flag `day` existe (visible en F3)
function M.init()
  if ws.get(mlogic.DAY_KEY) == nil then ws.set(mlogic.DAY_KEY, 1) end
end

-- Pasa al dia siguiente (lo llama la tecla N al pasar de noche a dia; un futuro "dormir" tambien)
function M.advance_day()
  return ws.add(mlogic.DAY_KEY, 1)
end

-- Cada frame: publica mission.<id>.next_day (true o ausente) para poder leerlo desde Tiled
function M.tick()
  local now = M.day()
  for _, id in ipairs(missions.ids()) do
    local v = mlogic.next_day(missions.state(id), ws.get(mlogic.key(id, "day")), now)
    ws.set(mlogic.key(id, "next_day"), v or nil)
  end
end

-- Guion final de un NPC: comentarios que se cumplen + guion base. nil si no hay nada.
-- Las entradas `once` se marcan vistas al construirse (comment.<id>.seen).
function M.build_script(npc, base)
  local lines, matched = logic.pick(M.entries, npc, missions.check,
    function(id) return ws.has(logic.key_seen(id)) end)
  if #lines == 0 then return base end
  for _, e in ipairs(matched) do
    if e.once then ws.set(logic.key_seen(e.id), true) end
  end
  local out = {}
  for _, l in ipairs(lines) do out[#out + 1] = l end
  for _, l in ipairs(base or {}) do out[#out + 1] = l end
  return out
end

function M.validate()
  local errors, warns = logic.validate(M.entries)
  for _, e in ipairs(errors) do print("[consequences] ERROR: " .. e) end
  for _, w in ipairs(warns) do print("[consequences] aviso: " .. w) end
  return #errors == 0
end

return M
