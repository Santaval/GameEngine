-- Prueba de la logica del foco del jugador (issue #67).
-- Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/foco_logic.lua
-- Sin motor: solo foco_logic.

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

local f = require("foco_logic")

-- new
do
  local s = f.new()
  eq(s.on, false, "nuevo: apagado")
  eq(s.battery, f.MAX_BATTERY, "nuevo: bateria llena")
  eq(f.level(s), 1, "nuevo: nivel 1")
end

-- drain
do
  local s = f.new()
  f.drain(s, 10)
  eq(s.battery, f.MAX_BATTERY, "apagado no gasta bateria")
  f.toggle(s)
  eq(s.on, true, "toggle enciende")
  f.drain(s, 10)
  eq(s.battery, f.MAX_BATTERY - 10, "encendido gasta dt")
  s.battery = 5
  f.drain(s, 10)
  eq(s.battery, 0, "drain no baja de 0")
  eq(s.on, false, "al agotarse se apaga")
  eq(f.toggle(s), false, "sin bateria no enciende")
  eq(s.on, false, "sin bateria sigue apagado")
end

-- recharge
do
  local s = f.new()
  s.battery = 3
  f.recharge(s)
  eq(s.battery, f.MAX_BATTERY, "recarga a tope")
end

-- level
do
  local s = f.new()
  s.battery = f.MAX_BATTERY / 2
  check(math.abs(f.level(s) - 0.5) < 1e-9, "nivel a mitad")
  s.battery = 0
  eq(f.level(s), 0, "nivel 0")
end

-- strength
do
  local s = f.new()
  eq(f.strength(s), 0, "apagado: fuerza 0")
  f.toggle(s)
  eq(f.strength(s), 1, "encendido con bateria llena: 1")
  s.battery = f.MAX_BATTERY * f.LOW + 1
  eq(f.strength(s), 1, "por encima de LOW: 1")
  s.battery = 0.0001
  local v = f.strength(s)
  check(v >= 0.3 and v < 0.31, "casi 0 encendido: 0.3")
  s.battery = f.MAX_BATTERY * f.LOW / 2
  check(math.abs(f.strength(s) - 0.65) < 1e-9, "a mitad de LOW: 0.65")
  s.battery = 0
  s.on = true
  check(math.abs(f.strength(s) - 0.3) < 1e-9, "bateria 0 con on forzado: 0.3")
end

-- beam
do
  local dirs = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local dists = { 14, 30, 48 }
  for name, u in pairs(dirs) do
    local b = f.beam(name)
    eq(#b, 3, name .. ": 3 circulos")
    for i = 1, 3 do
      eq(b[i].dx, dists[i] * u[1], name .. " dx " .. i)
      eq(b[i].dy, dists[i] * u[2], name .. " dy " .. i)
    end
    eq(b[1].r, 22, name .. " radio 1")
    eq(b[2].r, 30, name .. " radio 2")
    eq(b[3].r, 38, name .. " radio 3")
    eq(b[1].k, 1.0, name .. " k 1")
    eq(b[3].k, 0.6, name .. " k 3")
  end
  local r = f.beam("right")
  check(r[1].dx > 0, "right: dx positivo")
  eq(f.beam("zzz")[1].dy, 14, "facing desconocido = down")
end

-- bar
do
  local s = f.new()
  eq(f.bar(s, 38), 38, "bateria llena: barra completa")
  s.battery = f.MAX_BATTERY / 2
  eq(f.bar(s, 38), 19, "mitad: 19 px")
  s.battery = 0
  eq(f.bar(s, 38), 0, "vacia: 0 px")
end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("foco_logic: todo OK")
