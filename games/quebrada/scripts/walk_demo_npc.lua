-- NPC del demo de walker: patrulla un rectangulo con input por funcion (derecha 2s,
-- abajo 1s, izquierda 2s, arriba 1s). Mismo walker, sin camara.
-- El timer vive en el closure: cada entidad con este script tiene el suyo.
local t = 0
local legs = {
  { dx = 1, dy = 0, time = 2 },
  { dx = 0, dy = 1, time = 1 },
  { dx = -1, dy = 0, time = 2 },
  { dx = 0, dy = -1, time = 1 },
}
local total = 0
for _, leg in ipairs(legs) do total = total + leg.time end

local function patrol(entity, dt)
  t = (t + dt) % total
  local acc = 0
  for _, leg in ipairs(legs) do
    acc = acc + leg.time
    if t < acc then return leg.dx, leg.dy, false end
  end
  return 0, 0, false
end

update = require("walker").make_update({
  walk_speed = 40,
  input = patrol,
})
