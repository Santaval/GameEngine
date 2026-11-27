-- Logica pura de interaccion por proximidad (issue #49): sin llamadas al motor.
-- interaction.lua hace de pegamento (registro, dibujo, entrada).
local M = {}

-- Vector unitario de cada orientacion del walker
M.FACING = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- cos minimo entre la mirada y la direccion al objetivo (0.5 = cono de +-60 grados)
M.MIN_DOT = 0.5

-- Distancia del punto al borde del rect (0 si esta dentro)
function M.dist_to_rect(px, py, r)
  local dx = math.max(r.x - px, 0, px - (r.x + r.w))
  local dy = math.max(r.y - py, 0, py - (r.y + r.h))
  return math.sqrt(dx * dx + dy * dy)
end

function M.center(r)
  return r.x + r.w / 2, r.y + r.h / 2
end

-- true si el centro (cx,cy) queda delante de quien mira en `facing`.
-- Sin orientacion valida no se filtra; a menos de 4 px cuenta como delante.
function M.in_front(px, py, facing, cx, cy, min_dot)
  local f = M.FACING[facing]
  if not f then return true end
  local dx, dy = cx - px, cy - py
  local len = math.sqrt(dx * dx + dy * dy)
  if len <= 4 then return true end
  return (dx * f[1] + dy * f[2]) / len >= (min_dot or M.MIN_DOT)
end

-- Elige el candidato mas cercano en rango y delante del jugador.
-- cands: array de { rect = {x,y,w,h}, radius = n, ... } (enabled ya filtrado).
-- Desempate: distancia al borde, luego al centro, luego orden de registro.
function M.pick(cands, px, py, facing, min_dot)
  local best, best_d, best_c = nil, nil, nil
  for _, c in ipairs(cands) do
    local d = M.dist_to_rect(px, py, c.rect)
    if d <= c.radius then
      local cx, cy = M.center(c.rect)
      if M.in_front(px, py, facing, cx, cy, min_dot) then
        local ddx, ddy = cx - px, cy - py
        local cd = ddx * ddx + ddy * ddy
        if best == nil or d < best_d or (d == best_d and cd < best_c) then
          best, best_d, best_c = c, d, cd
        end
      end
    end
  end
  return best
end

-- Flanco de subida: devuelve pressed, down (guardar down para el frame siguiente)
function M.edge(was_down, down)
  down = down and true or false
  return (down and not was_down), down
end

-- "r,g,b" -> r, g, b (0-255) o nil si el texto no es valido
function M.parse_color(s)
  if type(s) ~= "string" then return nil end
  local r, g, b = s:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
  if not r then return nil end
  r, g, b = tonumber(r), tonumber(g), tonumber(b)
  if r > 255 or g > 255 or b > 255 then return nil end
  return r, g, b
end

return M
