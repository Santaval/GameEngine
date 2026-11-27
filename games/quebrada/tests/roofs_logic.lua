-- Prueba de la logica de los techos que se desvanecen (issue #71).
-- Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/roofs_logic.lua
-- Sin motor: solo roofs_logic.

package.path = "./games/quebrada/scripts/?.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. " (esperado " .. tostring(b) .. ", obtenido " .. tostring(a) .. ")")
end

local function near(a, b, eps, msg)
  check(math.abs(a - b) <= eps, msg .. " (esperado " .. tostring(b) .. ", obtenido " .. tostring(a) .. ")")
end

local r = require("roofs_logic")

local function roof(name, of, x, y, w, h, props)
  local p = { roof_of = of }
  for k, v in pairs(props or {}) do p[k] = v end
  return { name = name, type = "roof", shape = "rect", rect = { x = x, y = y, w = w, h = h }, properties = p }
end

-- index
do
  local objs = {
    roof("roof_a", "casa_a", 0, 0, 96, 80),
    roof("roof_b", "casa_b", 100, 0, 96, 80, { min_alpha = 40 }),
    { name = "no_of", type = "roof", shape = "rect", rect = { x = 0, y = 0, w = 1, h = 1 }, properties = {} },
    roof("empty_of", "", 0, 0, 1, 1),
    { name = "punto", type = "roof", shape = "point", x = 1, y = 1, properties = { roof_of = "x" } },
    { name = "puerta", type = "door", shape = "rect", rect = { x = 0, y = 0, w = 1, h = 1 }, properties = { roof_of = "x" } },
  }
  local list = r.index(objs)
  eq(#list, 2, "index: solo los rects de tipo roof con roof_of")
  eq(list[1].roof_of, "casa_a", "index: roof_of")
  eq(list[1].min_alpha, 0, "index: min_alpha por defecto 0")
  eq(list[2].min_alpha, 40, "index: min_alpha de la propiedad")
  eq(#r.index(nil), 0, "index: nil = vacio")
end

-- targets
do
  local list = r.index({ roof("a", "casa_a", 0, 0, 96, 80), roof("b", "casa_b", 200, 0, 96, 80, { min_alpha = 60 }) })
  local inside = { x = 10, y = 10, w = 10, h = 8 }
  local t = r.targets(list, inside)
  eq(t.casa_a, 0, "targets: dentro de casa_a -> 0")
  eq(t.casa_b, 255, "targets: fuera de casa_b -> 255")
  t = r.targets(list, { x = 210, y = 10, w = 10, h = 8 })
  eq(t.casa_a, 255, "targets: fuera de casa_a")
  eq(t.casa_b, 60, "targets: dentro de casa_b -> min_alpha")
  t = r.targets(list, { x = 96, y = 10, w = 10, h = 8 })
  eq(t.casa_a, 255, "targets: tocar solo el borde no cuenta")
  t = r.targets(list, nil)
  eq(t.casa_a, 255, "targets: foot nil -> opaco")
  eq(t.casa_b, 255, "targets: foot nil -> opaco (b)")
  -- dos rects del mismo roof_of: gana el mas bajo
  local two = r.index({
    roof("p1", "iglesia", 0, 0, 50, 50),
    roof("p2", "iglesia", 100, 0, 50, 50, { min_alpha = 90 }),
  })
  t = r.targets(two, { x = 110, y = 10, w = 4, h = 4 })
  eq(t.iglesia, 90, "targets: un rect cubierto")
  t = r.targets(two, { x = 10, y = 10, w = 4, h = 4 })
  eq(t.iglesia, 0, "targets: el otro rect")
  eq(#r.index({}), 0, "index vacio")
  eq(next(r.targets({}, inside)), nil, "targets: sin techos")
end

-- step
do
  eq(r.step(255, 0, 0.1, 600), 195, "step: baja a velocidad")
  eq(r.step(10, 0, 0.1, 600), 0, "step: no pasa del objetivo (abajo)")
  eq(r.step(250, 255, 0.1, 600), 255, "step: no pasa del objetivo (arriba)")
  eq(r.step(100, 100, 0.1, 600), 100, "step: igual se queda")
  eq(r.step(300, 400, 0.1, 600), 255, "step: acota a 255")
  eq(r.step(-5, -10, 0.1, 600), 0, "step: acota a 0")
  -- llega de 255 a 0 en ~0.43 s a 600/s
  local v, t, dt = 255, 0, 1 / 60
  while v > 0 and t < 2 do v = r.step(v, 0, dt, r.ROOF_SPEED); t = t + dt end
  near(t, 255 / 600, 0.03, "step: tiempo de desvanecido ~0.43 s")
  eq(r.ROOF_SPEED, 600, "ROOF_SPEED")
  eq(r.WINDOW_SPEED, 170, "WINDOW_SPEED")
end

-- window_target
do
  eq(r.window_target(true), 255, "window_target: noche")
  eq(r.window_target(false), 0, "window_target: dia")
end

if failures == 0 then
  print("roofs_logic: todo OK")
else
  print("roofs_logic: " .. failures .. " fallos")
  os.exit(1)
end
