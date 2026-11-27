-- Estado de mundo minimo (compatible con los flags del issue #51): flags por
-- nombre ("house.chayo.open") y contexto de transicion entre escenas.
--
-- Es un GLOBAL a proposito: load_scene descarga los modulos de require pero los
-- globales de Lua sobreviven (Aval hace lo mismo con current_game_scene). El
-- modulo se vuelve a ejecutar en cada escena y reutiliza la tabla existente.
--
-- Los flags se leen siempre en el momento (nunca se cachean): una puerta se abre
-- en cuanto cambia el flag. set(name, nil) borra un flag. snapshot/restore son
-- los ganchos del sistema de guardado (issue #51): aun no se escribe ningun archivo.
world_state = world_state or { flags = {}, ctx_table = {}, listeners = {} }

local M = world_state

-- Valor del flag o default si no existe
function M.get(name, default)
  local v = M.flags[name]
  if v == nil then return default end
  return v
end

-- Cambia un flag y avisa a los listeners solo si el valor cambio
function M.set(name, value)
  local old = M.flags[name]
  if old == value then return end
  M.flags[name] = value
  -- copia: un listener puede registrar otros mientras se notifica
  local snapshot = {}
  for i, fn in ipairs(M.listeners) do snapshot[i] = fn end
  for _, fn in ipairs(snapshot) do fn(name, value, old) end
end

-- true si el flag es verdadero (no nil ni false)
function M.has(name)
  return M.flags[name] and true or false
end

-- fn(name, nuevo, viejo)
function M.on_change(fn)
  M.listeners[#M.listeners + 1] = fn
end

-- Llamar al empezar cada escena: los closures de la escena anterior ya no existen
function M.clear_listeners()
  M.listeners = {}
end

-- Contexto de transicion: { arrival = {map, spawn, facing}, return_map,
-- return_spawn, return_facing, zone }
function M.ctx()
  return M.ctx_table
end

-- Sustituye el contenido del contexto (la referencia de ctx() se conserva)
function M.set_ctx(t)
  local c = M.ctx_table
  for k in pairs(c) do c[k] = nil end
  for k, v in pairs(t or {}) do c[k] = v end
end

-- Devuelve la llegada pendiente y la borra (solo se consume una vez)
function M.take_arrival()
  local c = M.ctx_table
  local a = c.arrival
  c.arrival = nil
  return a
end

-- Flags transitorios de interfaz: no se guardan ni se restauran
M.TRANSIENT = { ["dialogue.open"] = true, ["libreta.open"] = true, ["story.open"] = true }

local function persistable(name, v)
  local t = type(v)
  return not M.TRANSIENT[name] and (t == "boolean" or t == "number" or t == "string")
end

-- Suma n (1 por defecto) a un contador; si el flag no es numero, parte de 0
function M.add(name, n)
  local cur = M.flags[name]
  if type(cur) ~= "number" then cur = 0 end
  M.set(name, cur + (n or 1))
  return M.flags[name]
end

-- Copia pura de los flags persistibles (sin io, sin ctx, sin transitorios).
-- El sistema de guardado escribe esta tabla.
function M.snapshot()
  local out = {}
  for k, v in pairs(M.flags) do
    if persistable(k, v) then out[k] = v end
  end
  return out
end

-- Sustituye los flags persistibles por los de t (los que no estan en t se borran).
-- Pasa por M.set: los listeners se enteran de cada cambio.
function M.restore(t)
  t = t or {}
  local stale = {}
  for k in pairs(M.flags) do
    if not M.TRANSIENT[k] and t[k] == nil then stale[#stale + 1] = k end
  end
  for _, k in ipairs(stale) do M.set(k, nil) end
  for k, v in pairs(t) do
    if persistable(k, v) then M.set(k, v) end
  end
end

return M
