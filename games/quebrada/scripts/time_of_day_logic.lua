-- Logica pura de la hora del dia (issue #66). Sin motor: ni set_ambient ni dibujo.
-- La hora es de la historia, no un reloj: day -> dusk -> night -> dawn -> day.
local M = {}

M.PHASES = { "day", "dusk", "night", "dawn" }
M.STEP_TIME = 2.0   -- segundos que dura el cambio de ambiente entre fases
M.CARD_FADE = 0.8   -- fundido de entrada y de salida de la tarjeta de titulo

M.COLORS = {
  day = { 255, 255, 255 },
  dusk = { 150, 120, 130 },
  night = { 6, 8, 18 },
  dawn = { 70, 70, 100 },
}

local BASE = { day = "day", dusk = "day", night = "night", dawn = "night" }

local function index_of(phase)
  for i, p in ipairs(M.PHASES) do
    if p == phase then return i end
  end
  return nil
end

function M.valid(phase) return BASE[phase] ~= nil end

-- Hora "gruesa" que entienden el ambiente y las pistas de historia: day o night
function M.base(phase) return BASE[phase] end

function M.color(phase)
  local c = M.COLORS[phase] or M.COLORS.day
  return c[1], c[2], c[3]
end

-- `only` = "night" o lista "dusk,night". Visible si contiene la fase exacta o la hora
-- gruesa. Sin `only` (nil, vacio o no texto) siempre es visible
function M.visible(only, phase)
  if type(only) ~= "string" or only:match("^%s*$") then return true end
  local base = BASE[phase]
  for token in only:gmatch("[^,]+") do
    token = token:match("^%s*(.-)%s*$")
    if token == phase or token == base then return true end
  end
  return false
end

-- Fases por las que se pasa de `from` a `to` siguiendo el ciclo. Si el camino tiene mas
-- de 2 pasos va directo. Misma fase: lista vacia
function M.path(from, to)
  local i, j = index_of(from), index_of(to)
  if not i or not j or i == j then return {} end
  local chain = {}
  local k = i
  while k ~= j do
    k = k % #M.PHASES + 1
    chain[#chain + 1] = M.PHASES[k]
  end
  if #chain > 2 then return { to } end
  return chain
end

-- Opacidad (0..1) de la tarjeta en el instante t de una duracion total
function M.card_alpha(t, total)
  if total <= 0 or t <= 0 or t >= total then return 0 end
  local f = math.min(M.CARD_FADE, total / 2)
  if t < f then return t / f end
  if t > total - f then return (total - t) / f end
  return 1
end

-- Flags de world_state para una fase: `time` (texto), time.<fase> exacta y
-- time.day / time.night como hora gruesa (day = day o dusk; night = night o dawn)
function M.flags(phase)
  local f = { time = phase }
  for _, p in ipairs(M.PHASES) do f["time." .. p] = (p == phase) end
  local base = BASE[phase]
  f["time.day"] = (base == "day")
  f["time.night"] = (base == "night")
  return f
end

return M
