-- Logica pura del guardado (issue #52). Sin motor: no llama a save_data/load_data.
-- Docs: games/quebrada/docs/save.md
--
-- Forma del guardado (JSON en disco, ver save.lua):
--   version  numero de formato (VERSION). Si cambia el formato, se sube y se agrega
--            una migracion en MIGRATIONS
--   flags    snapshot de world_state (misiones, historias, pistas, desbloqueos, dia...)
--   time     { phase }            fase del dia (day|dusk|night|dawn)
--   foco     { battery }          bateria del foco (segundos)
--   place    { map, scene, ctx }  mapa y escena donde se guardo, y el contexto de
--                                 transicion (arrival, return_*) para reaparecer igual
local M = {}

M.VERSION = 1

-- MIGRATIONS[n] convierte un guardado de la version n en uno de la n + 1 (recibe y
-- devuelve la tabla; no hace falta tocar `version`, migrate() la sube). Ejemplo para
-- cuando el formato pase a 2:
--   MIGRATIONS[1] = function(d) d.flags["day"] = d.flags["day"] or 1; return d end
M.MIGRATIONS = {}

local PHASES = { day = true, dusk = true, night = true, dawn = true }
local MAX_BATTERY = 90 -- igual que foco_logic.MAX_BATTERY (este modulo no depende de el)

-- Copia solo valores escalares y subtablas de un nivel (arrival): lo que sobrevive a JSON
local function copy_ctx(ctx)
  local out = {}
  for k, v in pairs(ctx or {}) do
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then
      out[k] = v
    elseif t == "table" then
      local sub = {}
      for k2, v2 in pairs(v) do
        local t2 = type(v2)
        if t2 == "string" or t2 == "number" or t2 == "boolean" then sub[k2] = v2 end
      end
      out[k] = sub
    end
  end
  return out
end
M.copy_ctx = copy_ctx

-- parts: { flags, phase, battery, map, scene, ctx }
function M.build(parts)
  return {
    version = M.VERSION,
    flags = parts.flags or {},
    time = { phase = parts.phase or "day" },
    foco = { battery = parts.battery or MAX_BATTERY },
    place = { map = parts.map, scene = parts.scene, ctx = copy_ctx(parts.ctx) },
  }
end

-- Sube un guardado antiguo a la version actual. Devuelve la tabla, o nil y el motivo
-- (no es una tabla, version futura o desconocida, falta una migracion o fallo una)
function M.migrate(data, migrations)
  migrations = migrations or M.MIGRATIONS
  if type(data) ~= "table" then return nil, "el guardado no es una tabla" end
  local v = data.version
  if math.type and math.type(v) == "float" and v == math.floor(v) then v = math.tointeger(v) end
  if type(v) ~= "number" or v < 0 or v ~= math.floor(v) then
    return nil, "version de guardado invalida: " .. tostring(data.version)
  end
  if v > M.VERSION then
    return nil, "el guardado es de una version mas nueva (" .. v .. " > " .. M.VERSION .. ")"
  end
  while v < M.VERSION do
    local fn = migrations[v]
    if not fn then return nil, "no hay migracion de la version " .. v end
    local ok, res = pcall(fn, data)
    if not ok then return nil, "fallo la migracion " .. v .. ": " .. tostring(res) end
    if type(res) ~= "table" then return nil, "la migracion " .. v .. " no devolvio una tabla" end
    data = res
    v = v + 1
    data.version = v
  end
  return data
end

-- Extrae del guardado (ya migrado) lo que se aplica al juego, con valores saneados.
-- Devuelve { flags, phase, battery, map, scene, ctx } o nil y el motivo
function M.parts(data)
  if type(data) ~= "table" then return nil, "el guardado no es una tabla" end
  if type(data.flags) ~= "table" then return nil, "el guardado no tiene flags" end
  local place = type(data.place) == "table" and data.place or {}
  if type(place.map) ~= "string" or type(place.scene) ~= "string" then
    return nil, "el guardado no dice donde estaba el jugador"
  end

  local phase = type(data.time) == "table" and data.time.phase or nil
  if not PHASES[phase] then phase = "day" end

  local battery = type(data.foco) == "table" and data.foco.battery or nil
  if type(battery) ~= "number" then battery = MAX_BATTERY end
  battery = math.max(0, math.min(MAX_BATTERY, battery))

  local ctx = copy_ctx(place.ctx)
  -- sin llegada pendiente (se guardo en pleno mapa): aparece en el spawn por defecto
  if type(ctx.arrival) ~= "table" then
    ctx.arrival = { map = place.map, spawn = "default" }
  end

  return {
    flags = data.flags,
    phase = phase,
    battery = battery,
    map = place.map,
    scene = place.scene,
    ctx = ctx,
  }
end

return M
