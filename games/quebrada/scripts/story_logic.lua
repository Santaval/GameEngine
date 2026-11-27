-- Logica pura de historias narradas (issue #68): umbral de "escuchada", progreso,
-- formato mm:ss, maquina de estados del reproductor y pistas (una sola vez).
-- Sin motor, sin os ni io. story.lua hace de pegamento.
local M = {}

M.DEFAULT_HEARD_AT = 0.8  -- fraccion a partir de la cual la historia cuenta como escuchada
M.END_MARGIN = 1.0        -- segundos antes del final que cuentan como fin natural
M.CLUE_TIME = 4.0         -- segundos que se muestra una pista
M.CLUE_QUEUE_MAX = 4

function M.key(id, field) return "story." .. id .. "." .. field end
function M.clue_id(legend_id, clue_id) return legend_id .. "." .. clue_id end

function M.clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

-- Fraccion reproducida (0 si no se conoce la duracion)
function M.fraction(pos, dur)
  if type(pos) ~= "number" or type(dur) ~= "number" or dur <= 0 then return 0 end
  return M.clamp01(pos / dur)
end

-- Umbral de la leyenda (0 < h <= 1) o el valor por defecto
function M.heard_at(legend)
  local h = legend and legend.heard_at
  if type(h) ~= "number" or h <= 0 or h > 1 then return M.DEFAULT_HEARD_AT end
  return h
end

-- "none" | "started" | "heard" segun la fraccion alcanzada
function M.status(frac, heard_at)
  if frac >= heard_at then return "heard" end
  if frac > 0 then return "started" end
  return "none"
end

local RANK = { none = 0, started = 1, heard = 2 }
-- El estado nunca retrocede
function M.merge_status(a, b)
  if (RANK[b] or 0) > (RANK[a] or 0) then return b end
  return a or "none"
end

-- "m:ss"
function M.fmt_time(sec)
  if type(sec) ~= "number" or sec < 0 then sec = 0 end
  sec = math.floor(sec)
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

function M.percent(frac) return math.floor(M.clamp01(frac) * 100 + 0.5) end
function M.bar_fill(w, frac) return math.floor(w * M.clamp01(frac) + 0.5) end

-- true si el sonido llego (casi) al final: distingue fin natural de handle perdido
function M.is_natural_end(pos, dur)
  if type(pos) ~= "number" or type(dur) ~= "number" or dur <= 0 then return false end
  return dur - pos <= M.END_MARGIN
end

-- ---- maquina de estados del reproductor ----
M.TRANSITIONS = {
  start  = { idle = "playing", stopped = "playing", ended = "playing" },
  pause  = { playing = "paused" },
  resume = { paused = "playing" },
  stop   = { playing = "stopped", paused = "stopped" },
  finish = { playing = "ended" },
}

-- Nuevo estado, o nil si la transicion no existe
function M.next_state(state, event)
  local row = M.TRANSITIONS[event]
  return row and row[state or "idle"] or nil
end

-- Se puede ofrecer "Escuchar la historia"?
-- state: none|started|heard; busy: ya hay una sonando; repeatable: se puede repetir
function M.can_listen(state, requires_ok, busy, repeatable)
  if busy or not requires_ok then return false end
  if state == "heard" and not repeatable then return false end
  return true
end

-- ---- pistas ----
-- Una pista necesita al menos un disparador
function M.has_trigger(c)
  return c.map ~= nil or c.zone ~= nil or c.time ~= nil or c.near ~= nil or c.when ~= nil
end

-- ctx = { x, y, zone, time, map, check = fn(when) -> bool }
-- Todos los campos presentes deben cumplirse (AND).
function M.clue_matches(c, ctx)
  if c.map and c.map ~= ctx.map then return false end
  if c.zone and c.zone ~= ctx.zone then return false end
  if c.time and c.time ~= ctx.time then return false end
  if c.near then
    if ctx.x == nil or ctx.y == nil then return false end
    local dx, dy = ctx.x - c.near.x, ctx.y - c.near.y
    local r = c.near.r or 24
    if dx * dx + dy * dy > r * r then return false end
  end
  if c.when ~= nil and not (ctx.check and ctx.check(c.when)) then return false end
  return true
end

-- Cola FIFO sin table.*
function M.queue_push(q, item, max)
  if #q >= (max or M.CLUE_QUEUE_MAX) then return false end
  q[#q + 1] = item
  return true
end

function M.queue_pop(q)
  local first = q[1]
  if first == nil then return nil end
  for i = 1, #q - 1 do q[i] = q[i + 1] end
  q[#q] = nil
  return first
end

return M
