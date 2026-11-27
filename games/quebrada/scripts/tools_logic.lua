-- Logica pura de las herramientas (issue #53). Sin motor: ni flags reales ni dibujo.
-- Docs: games/quebrada/docs/tools.md
-- La posesion es un flag `tool.<id>` en world_state; aqui solo se ordena, se selecciona,
-- se comprueba si se puede usar y se calcula la barra del HUD.
local door_logic = require("door_logic")

local M = {}

M.MAX_SLOTS = 4
M.SLOT_W, M.SLOT_H, M.GAP = 24, 18, 3

function M.flag(id) return "tool." .. id end

-- Herramientas que se tienen, en el orden de la lista de definiciones.
-- defs: lista { id = ... }; has(flag) -> bool
function M.owned(defs, has)
  local out = {}
  for _, d in ipairs(defs) do
    if has(M.flag(d.id)) then out[#out + 1] = d end
  end
  return out
end

-- Deja state.selected apuntando a una herramienta que se tenga (o nil si no hay ninguna)
function M.ensure_selected(state, owned)
  for i, d in ipairs(owned) do
    if i > M.MAX_SLOTS then break end
    if d.id == state.selected then return d end
  end
  local first = owned[1]
  state.selected = first and first.id or nil
  return first
end

-- Selecciona la n-esima herramienta de la barra (1..MAX_SLOTS). false si no existe
function M.select(state, owned, n)
  if type(n) ~= "number" or n < 1 or n > M.MAX_SLOTS then return false end
  local d = owned[n]
  if not d then return false end
  state.selected = d.id
  return true
end

-- Indice de la herramienta seleccionada en la barra (nil si ninguna)
function M.selected_index(state, owned)
  for i, d in ipairs(owned) do
    if i > M.MAX_SLOTS then break end
    if d.id == state.selected then return i end
  end
  return nil
end

-- ¿Se puede usar ahora? `use.when` es una condicion de flags ("a,!b"). Devuelve true,
-- o false y el motivo (use.blocked o un texto por defecto)
function M.check_use(def, has)
  local use = def and def.use
  if not use then return false, "No sirve para nada ahora" end
  if use.when ~= nil and use.when ~= "" and not door_logic.eval_condition(use.when, has) then
    return false, use.blocked or "No es para esto"
  end
  return true
end

-- Posicion de las casillas, centradas abajo. Devuelve { {x,y,w,h}, ... } (n <= MAX_SLOTS)
function M.slot_layout(n, sw, sh)
  n = math.min(n, M.MAX_SLOTS)
  local out = {}
  if n <= 0 then return out end
  local total = n * M.SLOT_W + (n - 1) * M.GAP
  local x0 = math.floor((sw - total) / 2)
  local y = sh - M.SLOT_H - 4
  for i = 1, n do
    out[i] = { x = x0 + (i - 1) * (M.SLOT_W + M.GAP), y = y, w = M.SLOT_W, h = M.SLOT_H }
  end
  return out
end

return M
