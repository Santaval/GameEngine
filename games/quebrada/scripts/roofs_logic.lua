-- Logica pura de los techos que se desvanecen (issue #71): sin llamadas al motor.
-- Los objetos de la capa "roofs" del TMX (class "roof", rect, propiedad roof_of y
-- min_alpha opcional) dicen donde el jugador "esta dentro" de un edificio; mientras
-- su caja de pies toque ese rect, las capas con ese roof_of bajan a min_alpha.
-- scripts/roofs.lua es el pegamento con el motor. Prueba: tests/roofs_logic.lua.
local M = {}

M.ROOF_SPEED = 600   -- alpha (0-255) por segundo: ~0.43 s de opaco a transparente
M.WINDOW_SPEED = 170 -- las ventanas encendidas aparecen / se apagan mas despacio (~1.5 s)

local function clamp(v) return math.max(0, math.min(255, v)) end

-- Reparte map.objects (lista plana de load_tmx) en techos:
-- { name, roof_of, rect, min_alpha }. Se ignoran los que no son rect o no tienen roof_of.
function M.index(objects)
  local list = {}
  for _, o in ipairs(objects or {}) do
    if o.type == "roof" and o.shape == "rect" then
      local props = o.properties or {}
      local of = props.roof_of
      if type(of) == "string" and of ~= "" then
        list[#list + 1] = {
          name = o.name,
          roof_of = of,
          rect = o.rect,
          min_alpha = clamp(tonumber(props.min_alpha) or 0),
        }
      end
    end
  end
  return list
end

local function overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Alpha objetivo por roof_of: min_alpha si la caja de pies toca algun rect de ese
-- techo, 255 si no. Con varios rects del mismo roof_of gana el alpha mas bajo.
-- foot = nil (jugador sin colocar) deja todos los techos opacos.
function M.targets(roofs, foot)
  local out = {}
  for _, r in ipairs(roofs or {}) do
    local a = 255
    if foot and overlap(r.rect, foot) then a = r.min_alpha end
    if out[r.roof_of] == nil or a < out[r.roof_of] then out[r.roof_of] = a end
  end
  return out
end

-- Un paso de rampa de cur hacia target a speed (alpha/s), acotado a 0-255
function M.step(cur, target, dt, speed)
  local d = speed * dt
  local v
  if cur < target then v = math.min(cur + d, target)
  elseif cur > target then v = math.max(cur - d, target)
  else v = cur end
  return clamp(v)
end

-- Alpha objetivo de la capa windows_lit: 255 si es de noche / atardecer, 0 si no
function M.window_target(lit)
  return lit and 255 or 0
end

return M
