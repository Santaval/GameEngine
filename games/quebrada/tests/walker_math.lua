-- Prueba de la matematica del walker (issue #61): input, velocidad, facing,
-- cruce de frames y camara. Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/walker_math.lua
-- Sin motor: solo walker_math.

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

local w = require("walker_math")

-- normalize_input: la diagonal mide 1, el eje simple se queda en 1, el analogico se conserva
do
  local x, y = w.normalize_input(1, 1)
  near(math.sqrt(x * x + y * y), 1, 1e-9, "diagonal de largo 1")
  local ax, ay = w.normalize_input(1, 0)
  eq(ax, 1, "eje simple x"); eq(ay, 0, "eje simple y")
  local bx, by = w.normalize_input(0.5, 0)
  eq(bx, 0.5, "analogico x conservado"); eq(by, 0, "analogico y conservado")
end

-- step_velocity: aceleracion desde el reposo
do
  local vx, vy = 0, 0
  local prev = 0
  local reached = nil
  for i = 1, 6 do
    vx, vy = w.step_velocity(vx, vy, 1, 0, 60, 0.08, 0.05, 0.016)
    check(vx >= prev, "velocidad monotona en el paso " .. i)
    check(vx <= 60, "no supera el objetivo en el paso " .. i)
    eq(vy, 0, "sin deriva en y en el paso " .. i)
    prev = vx
    if i == 5 then reached = vx end
  end
  near(reached, 60, 1e-9, "tras 5 pasos de 0.016 ya llega a walk_speed")
  eq(vx, 60, "tras 6 pasos es exactamente walk_speed")
end

-- step_velocity: frenado exacto a 0,0
do
  local vx, vy = 60, 0
  local dt, decel = 0.016, 0.05
  local limit = math.ceil(decel / dt) + 1
  local steps = 0
  while (vx ~= 0 or vy ~= 0) and steps < 100 do
    vx, vy = w.step_velocity(vx, vy, 0, 0, 60, 0.08, decel, dt)
    steps = steps + 1
  end
  eq(vx, 0, "frena en x exactamente"); eq(vy, 0, "frena en y exactamente")
  check(steps <= limit, "frena en " .. steps .. " pasos (max " .. limit .. ")")
end

-- step_velocity: tiempo 0 o nil = instantaneo
do
  local vx, vy = w.step_velocity(0, 0, 1, 0, 60, 0, 0.05, 0.016)
  eq(vx, 60, "accel_time 0 salta a la velocidad"); eq(vy, 0, "accel_time 0 y")
  vx, vy = w.step_velocity(0, 0, 0, -1, 60, nil, nil, 0.016)
  eq(vx, 0, "tiempos nil x"); eq(vy, -60, "tiempos nil saltan a la velocidad")
  vx, vy = w.step_velocity(60, 0, 0, 0, 60, 0.08, 0, 0.016)
  eq(vx, 0, "decel_time 0 para de golpe")
end

-- pick_facing
do
  eq(w.pick_facing(1, 0, "down"), "right", "solo derecha")
  eq(w.pick_facing(-1, 0, "down"), "left", "solo izquierda")
  eq(w.pick_facing(0, 1, "left"), "down", "solo abajo")
  eq(w.pick_facing(0, -1, "left"), "up", "solo arriba")
  eq(w.pick_facing(1, 1, "right"), "right", "right y luego right+down sigue right")
  eq(w.pick_facing(0, 1, "right"), "down", "soltar right con down pulsado da down")
  eq(w.pick_facing(0, 0, "up"), "up", "sin input conserva")
  eq(w.pick_facing(0.05, 0, "left"), "left", "bajo la zona muerta conserva")
  eq(w.pick_facing(1, 1, "up"), "right", "diagonal con prev up -> right")
  eq(w.pick_facing(-1, 1, "up"), "left", "diagonal con prev up -> left")
  eq(w.pick_facing(-1, -1, "up"), "up", "diagonal conserva prev si esta pulsado")
end

-- anim_tag
eq(w.anim_tag("", "walk", "left"), "walk_left", "tag sin prefijo")
eq(w.anim_tag("hero_", "idle", "up"), "hero_idle_up", "tag con prefijo")

-- crossed_frame
do
  local set = { [1] = true, [3] = true }
  eq(w.crossed_frame(0, 1, set), true, "dispara al entrar en 1")
  eq(w.crossed_frame(1, 1, set), false, "no dispara si se queda en 1")
  eq(w.crossed_frame(1, 2, set), false, "no dispara en 2")
  eq(w.crossed_frame(2, 3, set), true, "dispara al entrar en 3")
  eq(w.crossed_frame(3, 0, set), false, "no dispara en 0")
end

-- smooth_factor
do
  local f = w.smooth_factor(10, 0.016)
  check(f > 0 and f < 1, "factor entre 0 y 1")
  eq(w.smooth_factor(0, 0.016), 1, "k = 0 pega la camara")
  eq(w.smooth_factor(nil, 0.016), 1, "k nil pega la camara")
  local half = w.smooth_factor(10, 0.008)
  near(1 - (1 - half) * (1 - half), f, 1e-12, "dos medios pasos = un paso")
end

-- camara
local SW, SH = 480, 270
local cfg = { deadzone = { w = 24, h = 16 }, smooth = 0 }
local big = { x = 0, y = 0, w = 2000, h = 1500 }
do
  local st = {}
  local x, y = w.camera_step(st, 1000, 700, cfg, SW, SH, big, 0.016)
  eq(x, 760, "primer frame pega x al objetivo"); eq(y, 565, "primer frame pega y")

  x, y = w.camera_step(st, 1010, 705, cfg, SW, SH, big, 0.016)
  eq(x, 760, "objetivo dentro de la deadzone no mueve x"); eq(y, 565, "idem y")

  x, y = w.camera_step(st, 1020, 700, cfg, SW, SH, big, 0.016)
  eq(x, 768, "fuera de la deadzone sigue con holgura 12")
  eq((1020) - (x + SW / 2), 12, "offset objetivo-centro == medio ancho de deadzone")
end

-- limites: esquinas de un mapa grande
do
  local st = {}
  local x, y = w.camera_step(st, 0, 0, cfg, SW, SH, big, 0.016)
  eq(x, 0, "esquina sup-izq x"); eq(y, 0, "esquina sup-izq y")
  eq(st.cx, SW / 2, "el centro se reescribe limitado (x)")
  eq(st.cy, SH / 2, "el centro se reescribe limitado (y)")
  x, y = w.camera_step(st, 2000, 1500, cfg, SW, SH, big, 0.016)
  eq(x, 2000 - SW, "esquina inf-der x"); eq(y, 1500 - SH, "esquina inf-der y")
  eq(st.cx, 2000 - SW / 2, "centro re-limitado en cada paso")
end

-- mapa mas pequeno que la pantalla en un eje: se centra
do
  local st = {}
  local x, y = w.camera_step(st, 100, 700, cfg, SW, SH, { x = 0, y = 0, w = 200, h = 1500 }, 0.016)
  eq(x, (200 - SW) / 2, "mapa de 200 con pantalla 480 se centra en -140")
  eq(y, 565, "el otro eje sigue normal")
end

-- sin limites: no hay clamp
do
  local st = {}
  local x, y = w.camera_step(st, 0, 0, cfg, SW, SH, nil, 0.016)
  eq(x, -SW / 2, "sin bounds x sin clamp"); eq(y, -SH / 2, "sin bounds y sin clamp")
end

-- suavizado: converge hacia el objetivo sin pasarse
do
  local st = {}
  local scfg = { deadzone = { w = 0, h = 0 }, smooth = 10 }
  w.camera_step(st, 1000, 700, scfg, SW, SH, big, 0.016)
  local x = w.camera_step(st, 1100, 700, scfg, SW, SH, big, 0.016)
  check(x > 760 and x < 860, "con smooth la camara avanza sin llegar de golpe")
end

if failures == 0 then
  print("walker_math: all passed")
else
  print("walker_math: " .. failures .. " failures")
  os.exit(1)
end
