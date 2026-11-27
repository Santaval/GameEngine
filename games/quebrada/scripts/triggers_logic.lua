-- Logica pura de los triggers de mapa (issue #78). Sin motor, sin os ni io.
-- Un trigger es un objeto class="trigger" de la capa `triggers` con las propiedades:
--   trigger   id del trigger (NO `id`: choca con el id de Tiled). Varios rects con el mismo id = union
--   mission   mision a la que pertenece ("chequelo"); el trigger solo vale con la mision en ACTIVE
--   requires  condicion de flags como las puertas ("a,!b"); vacia = siempre verdadera
--   sets      flags que se ponen a true al entrar (separados por coma)
--   line      texto opcional que se dice al entrar
-- Dispara una sola vez por estancia: enter al pisarlo con la condicion cumplida (tambien si la
-- condicion se cumple ya estando dentro) y exit al salir, solo si habia disparado.
-- Docs: games/quebrada/docs/zona1.md
local door_logic = require("door_logic")

local M = {}

-- Estados de mision en los que los triggers estan vivos
M.ACTIVE = { accepted = true, night_active = true }

-- Triggers validos de map.objects: rect y propiedad `trigger` no vacia
function M.index(objects)
  local list = {}
  for _, o in ipairs(objects or {}) do
    local p = o.properties
    if o.type == "trigger" and o.shape == "rect" and o.rect and p and type(p.trigger) == "string" and p.trigger ~= "" then
      list[#list + 1] = o
    end
  end
  return list
end

-- Agrupa por id: groups[id] = { id, rects, props } (props del primer rect) y order = ids en orden de aparicion
function M.group(list)
  local groups, order = {}, {}
  for _, o in ipairs(list or {}) do
    local id = o.properties.trigger
    local g = groups[id]
    if not g then
      g = { id = id, rects = {}, props = o.properties }
      groups[id] = g
      order[#order + 1] = id
    end
    g.rects[#g.rects + 1] = o.rect
  end
  return groups, order
end

function M.new_state()
  return { inside = {}, fired = {} }
end

-- true si la caja toca algun rect del grupo
function M.overlaps(g, foot)
  for _, r in ipairs(g.rects) do
    if door_logic.rect_overlap(r, foot) then return true end
  end
  return false
end

-- Eventos de este paso: { { kind = "enter"|"exit", group = g }, ... }
-- can_fire(g) -> bool se evalua mientras el jugador esta dentro y el trigger no ha disparado
function M.step(st, groups, order, foot, can_fire)
  local events = {}
  for _, id in ipairs(order) do
    local g = groups[id]
    if M.overlaps(g, foot) then
      st.inside[id] = true
      if not st.fired[id] and can_fire(g) then
        st.fired[id] = true
        events[#events + 1] = { kind = "enter", group = g }
      end
    elseif st.inside[id] then
      st.inside[id] = nil
      if st.fired[id] then
        st.fired[id] = nil
        events[#events + 1] = { kind = "exit", group = g }
      end
    end
  end
  return events
end

-- Mision en un estado vivo Y `requires` cumplido (vacio = verdadero; eval_condition("") es falso)
-- flag_fn(name) -> bool; state_fn(mission_id) -> estado
function M.condition_ok(g, flag_fn, state_fn)
  local mission = g.props.mission
  if type(mission) == "string" and mission ~= "" then
    if not M.ACTIVE[state_fn(mission)] then return false end
  end
  local req = g.props.requires
  if req == nil or req == "" then return true end
  return door_logic.eval_condition(req, flag_fn)
end

-- Final del chequelo: el primer desvio tomado o "done"
function M.outcome(detour)
  if type(detour) == "string" and detour ~= "" then return detour end
  return "done"
end

-- Temporizador de un disparo cada `interval` s. Devuelve nuevo_timer, disparo
function M.interval_step(timer, dt, interval)
  timer = (timer or 0) + dt
  if timer >= interval then return 0, true end
  return timer, false
end

-- Nombres de flags de una lista "a,b"
function M.split_flags(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for term in s:gmatch("[^,]+") do
    term = term:match("^%s*(.-)%s*$")
    if term ~= "" then out[#out + 1] = term end
  end
  return out
end

-- Lista de errores: ids requeridos que faltan y grupos sin `mission`
function M.validate(groups, required_ids)
  local errs = {}
  for _, id in ipairs(required_ids or {}) do
    if not groups[id] then errs[#errs + 1] = "falta el trigger '" .. id .. "'" end
  end
  for id, g in pairs(groups) do
    local m = g.props.mission
    if type(m) ~= "string" or m == "" then errs[#errs + 1] = "el trigger '" .. id .. "' no tiene mission" end
  end
  return require("missions_logic").sort_strings(errs) -- el Lua del motor no trae table.sort
end

return M
