-- Prueba de la logica de la pelea contra el simio (volver a casa de noche).
-- Se corre desde la raiz del repo:
--   lua games/quebrada/tests/simio_logic.lua
-- Sin motor: solo simio_logic (y tests/zona1_consts.lua para las constantes del mapa).

package.path = "./games/quebrada/scripts/?.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg) check(a == b, msg .. " (esperado " .. tostring(b) .. ", obtenido " .. tostring(a) .. ")") end

local L = require("simio_logic")
local C = L.CONFIG

local function has(evs, name)
  for _, e in ipairs(evs) do if e == name then return true end end
  return false
end
local function count(evs, name)
  local n = 0
  for _, e in ipairs(evs) do if e == name then n = n + 1 end end
  return n
end
-- Simio ya en persecucion en (sx, sy)
-- Las pruebas usan coordenadas relativas al centro de la arena (OX, OY): ARENA recorta al simio
local OX, OY = 7500, 1850
local function chasing(sx, sy)
  local st = L.new(C, OX + sx, OY + sy)
  st.phase = "chase"
  return st
end
local function inp(px, py, slash, facing) return { px = OX + px, py = OY + py, slash = slash or false, facing = facing or "right" } end
local function put(st, sx, sy) st.sx, st.sy = OX + sx, OY + sy end

-- slash_hits: las 4 orientaciones, delante / detras / lejos / de lado
do
  local P = { 100, 100 }
  eq(L.slash_hits(100, 100, "right", 120, 100, C), true, "derecha: delante")
  eq(L.slash_hits(100, 100, "right", 80, 100, C), false, "derecha: detras")
  eq(L.slash_hits(100, 100, "right", 160, 100, C), false, "derecha: lejos")
  eq(L.slash_hits(100, 100, "right", 120, 130, C), false, "derecha: de lado")
  eq(L.slash_hits(100, 100, "left", 80, 105, C), true, "izquierda: delante")
  eq(L.slash_hits(100, 100, "left", 120, 100, C), false, "izquierda: detras")
  eq(L.slash_hits(100, 100, "up", 105, 80, C), true, "arriba: delante")
  eq(L.slash_hits(100, 100, "up", 100, 120, C), false, "arriba: detras")
  eq(L.slash_hits(100, 100, "down", 95, 120, C), true, "abajo: delante")
  eq(L.slash_hits(100, 100, "down", 100, 80, C), false, "abajo: detras")
  local _ = P
end

-- enfriamiento: dos golpes en 0,2 s dan un solo simio_hit y un cooldown
do
  local st = chasing(20, 0)
  local e1 = L.step(st, C, 0.016, inp(0, 0, true, "right"))
  eq(count(e1, "simio_hit"), 1, "primer golpe pega")
  eq(st.hp, C.simio_hp - 1, "primer golpe baja un punto")
  local e2 = L.step(st, C, 0.2, inp(0, 0, true, "right"))
  eq(count(e2, "simio_hit"), 0, "segundo golpe en enfriamiento no pega")
  eq(count(e2, "cooldown"), 1, "segundo golpe: cooldown")
  eq(st.hp, C.simio_hp - 1, "el enfriamiento no baja vida")
end

-- invulnerabilidad del simio: con el enfriamiento forzado a 0 el segundo golpe no baja vida
do
  local st = chasing(20, 0)
  L.step(st, C, 0.016, inp(0, 0, true))
  st.slash_cd = 0
  st.phase = "chase"
  local e = L.step(st, C, 0.016, inp(0, 0, true))
  eq(st.hp, C.simio_hp - 1, "iframes del simio")
  eq(count(e, "miss"), 1, "golpe en iframes cuenta como fallo")
end

-- un golpe fallido da miss
do
  local st = chasing(100, 0)
  eq(has(L.step(st, C, 0.016, inp(0, 0, true)), "miss"), true, "golpe al aire: miss")
end

-- la persecucion es mas lenta que caminar: se acerca si el jugador esta quieto, se aleja si camina
do
  local st = chasing(200, 0)
  local d0 = 200 - 0
  for _ = 1, 30 do L.step(st, C, 1 / 60, inp(0, 0)) end
  check(math.abs(st.sx - OX) < d0, "quieto: el simio se acerca")
  local st2 = chasing(100, 0)
  local px = 0
  for _ = 1, 120 do px = px - 130 / 60; L.step(st2, C, 1 / 60, inp(px, 0)) end
  check(math.abs((st2.sx - OX) - px) > 100, "caminando a 130 px/s: el simio se queda atras")
  check(C.chase_speed < 130 and C.chase_speed_furia < 130, "persecucion siempre bajo la velocidad de caminar")
end

-- windup -> lunge: no hay player_hit antes de windup + margen; la embestida que falla no pega
do
  local st = chasing(40, 0)
  local evs = L.step(st, C, 1 / 60, inp(0, 0))
  eq(has(evs, "windup"), true, "dentro de engage_dist empieza el windup")
  local t, hit = 0, false
  while t < C.windup - 0.05 do
    for _, e in ipairs(L.step(st, C, 1 / 60, inp(0, 0))) do if e == "player_hit" then hit = true end end
    t = t + 1 / 60
  end
  eq(hit, false, "sin golpe durante el windup")
  -- el jugador esquiva 60 px de lado antes de la embestida
  local pxx, pyy = 0, 60
  local got = false
  for _ = 1, 60 do
    for _, e in ipairs(L.step(st, C, 1 / 60, inp(pxx, pyy))) do if e == "player_hit" then got = true end end
  end
  eq(got, false, "embestida esquivada: sin golpe")
end

-- iframes del jugador: embestidas seguidas no pegan dos veces en 1 s
do
  local st = chasing(20, 0)
  st.phase, st.t, st.ldx, st.ldy = "lunge", 0, -1, 0
  put(st, 20, 0)
  local e1 = L.step(st, C, 0.05, inp(0, 0))
  eq(count(e1, "player_hit"), 1, "la embestida pega")
  eq(st.php, C.player_hp - 1, "baja un punto de vida")
  st.phase, st.t, st.ldx, st.ldy = "lunge", 0, -1, 0
  put(st, 20, 0)
  local e2 = L.step(st, C, 0.05, inp(0, 0))
  eq(count(e2, "player_hit"), 0, "no pega dos veces dentro de player_iframes")
end

-- cinco impactos dan player_down y la fase lost; despues step no hace nada
do
  local st = chasing(20, 0)
  local downs = 0
  for _ = 1, C.player_hp do
    st.phase, st.t, st.ldx, st.ldy, st.pinv = "lunge", 0, -1, 0, 0
    put(st, 20, 0)
    for _, e in ipairs(L.step(st, C, 0.05, inp(0, 0))) do if e == "player_down" then downs = downs + 1 end end
  end
  eq(downs, 1, "player_down una vez")
  eq(st.phase, "lost", "fase lost")
  eq(#L.step(st, C, 0.1, inp(0, 0, true)), 0, "tras lost, step es un no-op")
end

-- seis golpes dan simio_down, flee y gone; luego done
do
  local st = chasing(20, 0)
  local down, gone = false, false
  for i = 1, C.simio_hp do
    st.slash_cd, st.inv, st.phase = 0, 0, "chase"
    put(st, 20, 0)
    for _, e in ipairs(L.step(st, C, 0.016, inp(0, 0, true))) do if e == "simio_down" then down = true end end
  end
  eq(down, true, "seis golpes tiran al simio")
  eq(st.phase, "flee", "fase flee")
  for _ = 1, 200 do
    for _, e in ipairs(L.step(st, C, 1 / 60, inp(0, 0))) do if e == "gone" then gone = true end end
  end
  eq(gone, true, "gone al terminar flee_time")
  eq(st.phase, "done", "fase done")
end

-- un golpe a media embestida no la interrumpe
do
  local st = chasing(20, 0)
  st.phase, st.t, st.ldx, st.ldy = "lunge", 0, 0, 1
  put(st, 20, 0)
  L.step(st, C, 0.016, inp(0, 0, true))
  eq(st.phase, "lunge", "la embestida sigue tras el golpe")
  eq(st.hp, C.simio_hp - 1, "pero el golpe cuenta")
end

-- limites de ARENA
do
  local st = chasing(0, 0)
  for _ = 1, 600 do L.step(st, C, 1 / 60, inp(-5000, -5000)) end
  check(st.sx >= C.ARENA.x and st.sy >= C.ARENA.y, "el simio no sale de ARENA por arriba / izquierda")
end

-- leashed
eq(L.leashed(C, 7600, 1800), true, "dentro del area: leashed")
eq(L.leashed(C, 9000, 1800), false, "lejos: no leashed")

-- furia: ventana de windup mas corta con poca vida
do
  local st = chasing(20, 0)
  st.hp = C.furia_hp
  eq(L.furia(st, C), true, "furia con vida <= furia_hp")
  st.phase, st.t = "windup", C.windup_furia
  L.step(st, C, 0.001, inp(0, 0))
  eq(st.phase, "lunge", "en furia embiste tras windup_furia")
end

-- appear: sube hasta la calle y avisa
do
  local st = L.new(C, 7712, 2044)
  local seen = false
  for _ = 1, 600 do
    for _, e in ipairs(L.step(st, C, 1 / 60, { px = 7712, py = 1830, slash = false, facing = "right" })) do if e == "appeared" then seen = true end end
  end
  eq(seen, true, "appeared")
  check(st.phase ~= "appear", "sale de la fase appear")
end

-- constantes del mapa (las escribe el generador en tests/zona1_consts.lua)
do
  local Z = dofile("./games/quebrada/tests/zona1_consts.lua")
  eq(Z.CALILES_X * 16, 7680, "CALILES_X en px (franja de los Caliles)")
  local W = require("walkback_logic")
  check(W.BAND.x <= 7680 and W.BAND.x + W.BAND.w >= 7744, "la franja cubre x 7680-7744")
  eq(W.HOME.x, 8984, "HOME x"); eq(W.HOME.y, 2012, "HOME y"); eq(W.HOME.w, 64, "HOME w"); eq(W.HOME.h, 44, "HOME h")
  check(W.in_band(7700, 1840), "in_band: pies en la calle sobre el cruce")
  check(not W.in_band(7000, 1840), "in_band: lejos al este")
  check(W.in_home(9000, 2030), "in_home: frente a la puerta")
end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("simio_logic OK")
