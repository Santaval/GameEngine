-- Logica pura de misiones (issue #51): tabla de transiciones, claves de flags,
-- ordenacion, filas del overlay y combinadores de condiciones. Sin motor, sin os ni io.
local door_logic = require("door_logic")

local M = {}

M.STATES = { "none", "offered", "accepted", "rejected", "night_active", "done", "failed" }

-- evento -> { estado_actual = estado_nuevo }
M.TRANSITIONS = {
  offer       = { none = "offered" },
  accept      = { offered = "accepted" },
  reject      = { offered = "rejected" },
  start_night = { accepted = "night_active" },
  complete    = { night_active = "done" },
  fail        = { accepted = "failed", night_active = "failed" },
}

-- evento -> nombre del hook en la definicion de la mision
M.HOOKS = {
  offer = "on_offer", accept = "on_accept", reject = "on_reject",
  start_night = "on_start_night", complete = "on_complete", fail = "on_fail",
}

-- Nuevo estado, o nil + mensaje si la transicion no existe
function M.next_state(state, event)
  local row = M.TRANSITIONS[event]
  if not row then return nil, "evento desconocido '" .. tostring(event) .. "'" end
  state = state or "none"
  local to = row[state]
  if not to then
    return nil, "no se puede '" .. event .. "' desde '" .. state .. "'"
  end
  return to
end

function M.is_state(s)
  for _, v in ipairs(M.STATES) do if v == s then return true end end
  return false
end

-- Siguiente (dir=1) o anterior (dir=-1) estado, dando la vuelta (para el overlay)
function M.cycle_state(state, dir)
  local i = 1
  for k, s in ipairs(M.STATES) do if s == state then i = k end end
  return M.STATES[(i - 1 + dir) % #M.STATES + 1]
end

-- Clave de flag: mission.<id>.<campo>
function M.key(id, field) return "mission." .. id .. "." .. field end

-- Ordenacion por insercion (no hay table.sort)
function M.sort_strings(list)
  for i = 2, #list do
    local v = list[i]
    local j = i - 1
    while j >= 1 and list[j] > v do
      list[j + 1] = list[j]
      j = j - 1
    end
    list[j + 1] = v
  end
  return list
end

-- Ids conocidos: los de las definiciones mas los que aparecen como
-- mission.<id>.state en los flags. Ordenados y sin repetir.
function M.collect_ids(def_ids, flags)
  local seen, out = {}, {}
  for _, id in ipairs(def_ids or {}) do
    if not seen[id] then seen[id] = true; out[#out + 1] = id end
  end
  for name in pairs(flags or {}) do
    local id = type(name) == "string" and name:match("^mission%.(.+)%.state$")
    if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
  end
  return M.sort_strings(out)
end

-- Filas del overlay: misiones primero y luego flags ordenados. Los flags
-- mission.* se ocultan (ya se ven como filas de mision).
-- kind = "mission" (id) | "flag" (name); text es lo que se dibuja.
function M.build_rows(ids, state_of, flags)
  local rows = {}
  for _, id in ipairs(ids) do
    rows[#rows + 1] = { kind = "mission", id = id, text = "[M] " .. id .. " : " .. state_of(id) }
  end
  local names = {}
  for k in pairs(flags) do
    if type(k) == "string" and not k:match("^mission%.") then names[#names + 1] = k end
  end
  M.sort_strings(names)
  for _, k in ipairs(names) do
    rows[#rows + 1] = { kind = "flag", name = k, text = "[F] " .. k .. " = " .. tostring(flags[k]) }
  end
  return rows
end

-- Primera fila visible para que sel quede dentro de la ventana
function M.window_start(sel, n, visible)
  if visible < 1 or n <= visible then return 1 end
  local first = sel - math.floor(visible / 2)
  if first < 1 then first = 1 end
  if first > n - visible + 1 then first = n - visible + 1 end
  return first
end

-- Valor editable de un flag para el overlay: bool alterna, numero suma dir,
-- nil pasa a true, string no cambia
function M.step_value(v, dir)
  local t = type(v)
  if t == "boolean" then return not v end
  if t == "number" then return v + dir end
  if v == nil then return true end
  return v
end

-- ---- condiciones (`when`) ----

-- when: nil = true | boolean | function() | string ("a", "!a", "a,!b" con flag_fn)
function M.test(when, flag_fn)
  if when == nil then return true end
  local t = type(when)
  if t == "boolean" then return when end
  if t == "function" then
    local ok, r = pcall(when)
    if not ok then
      print("[missions] condicion fallo: " .. tostring(r))
      return false
    end
    return r and true or false
  end
  if t == "string" then return door_logic.eval_condition(when, flag_fn) end
  return false
end

function M.all(...)
  local fs = { ... }
  return function()
    for _, f in ipairs(fs) do if not f() then return false end end
    return true
  end
end

function M.any(...)
  local fs = { ... }
  return function()
    for _, f in ipairs(fs) do if f() then return true end end
    return false
  end
end

function M.negate(f) return function() return not f() end end

return M
