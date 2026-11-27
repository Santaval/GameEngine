-- Logica pura del foco del jugador (issue #67). Sin motor: ni luces ni dibujo.
-- La bateria se gasta solo con el foco encendido y se recarga en el cargador o al dormir.
local M = {}

M.MAX_BATTERY = 90  -- segundos de bateria
M.LOW = 0.2         -- por debajo de este nivel (0..1) la luz se debilita

-- Distancias (px) desde el centro de los pies, radios y multiplicador de intensidad de los 3 circulos
local BEAM_DIST = { 14, 30, 48 }
local BEAM_RADIUS = { 22, 30, 38 }
local BEAM_K = { 1.0, 0.85, 0.6 }

local UNIT = {
  up = { 0, -1 },
  down = { 0, 1 },
  left = { -1, 0 },
  right = { 1, 0 },
}

function M.new()
  return { on = false, battery = M.MAX_BATTERY }
end

-- Bateria restante en 0..1
function M.level(s)
  return s.battery / M.MAX_BATTERY
end

-- Enciende o apaga el foco. Sin bateria no se puede encender: devuelve false
function M.toggle(s)
  if s.battery <= 0 then
    s.on = false
  else
    s.on = not s.on
  end
  return s.on
end

-- Gasta bateria mientras el foco esta encendido. Al agotarse, se apaga
function M.drain(s, dt)
  if s.on then
    s.battery = math.max(0, s.battery - dt)
    if s.battery <= 0 then s.on = false end
  end
  return s.on
end

function M.recharge(s)
  s.battery = M.MAX_BATTERY
end

-- Fuerza de la luz en 0..1: 0 apagado; con poca bateria se debilita hasta 0.3
function M.strength(s)
  if not s.on then return 0 end
  local lv = M.level(s)
  if lv >= M.LOW then return 1 end
  return math.max(0.3, 0.3 + 0.7 * (lv / M.LOW))
end

-- Tres circulos delante del jugador: { dx, dy, r, k } relativos al centro de los pies
function M.beam(facing)
  local u = UNIT[facing] or UNIT.down
  local out = {}
  for i = 1, 3 do
    out[i] = {
      dx = BEAM_DIST[i] * u[1],
      dy = BEAM_DIST[i] * u[2],
      r = BEAM_RADIUS[i],
      k = BEAM_K[i],
    }
  end
  return out
end

-- Ancho en px (entero) de la barra de bateria
function M.bar(s, width)
  return math.floor(M.level(s) * width + 0.5)
end

return M
