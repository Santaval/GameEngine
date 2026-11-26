-- Prueba de la logica de puertas, zonas, fundido y world_state (issue #62).
-- Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/door_logic.lua
-- Sin motor: solo door_logic y world_state.

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

local d = require("door_logic")

-- eval_condition
do
  local flags = { a = true, b = false }
  local fn = function(n) return flags[n] end
  eq(d.eval_condition(nil, fn), false, "nil = false")
  eq(d.eval_condition("", fn), false, "vacio = false")
  eq(d.eval_condition("a", fn), true, "flag activo")
  eq(d.eval_condition("b", fn), false, "flag inactivo")
  eq(d.eval_condition("c", fn), false, "flag inexistente")
  eq(d.eval_condition("!a", fn), false, "negado de activo")
  eq(d.eval_condition("!b", fn), true, "negado de inactivo")
  eq(d.eval_condition("!c", fn), true, "negado de inexistente")
  eq(d.eval_condition("a,!b", fn), true, "AND verdadero")
  eq(d.eval_condition("a, b", fn), false, "AND con un falso (con espacios)")
  eq(d.eval_condition("!a,!b", fn), false, "AND con negado falso")
  eq(d.eval_condition(true, fn), true, "booleano true")
  eq(d.eval_condition(false, fn), false, "booleano false")
  eq(d.is_locked({ properties = { locked = "!house.chayo.open" } }, fn), true, "cerrada hasta que haya flag")
  flags["house.chayo.open"] = true
  eq(d.is_locked({ properties = { locked = "!house.chayo.open" } }, fn), false, "abierta con el flag")
  eq(d.is_locked({ properties = {} }, fn), false, "sin locked = abierta")
end

-- rect_overlap: solape estricto
do
  local a = { x = 0, y = 0, w = 10, h = 10 }
  eq(d.rect_overlap(a, { x = 5, y = 5, w = 10, h = 10 }), true, "solape")
  eq(d.rect_overlap(a, { x = 10, y = 0, w = 10, h = 10 }), false, "borde derecho tocando")
  eq(d.rect_overlap(a, { x = 0, y = 10, w = 10, h = 10 }), false, "borde inferior tocando")
  eq(d.rect_overlap(a, { x = -10, y = 0, w = 10, h = 10 }), false, "borde izquierdo tocando")
  eq(d.rect_overlap(a, { x = 9.5, y = 0, w = 10, h = 10 }), true, "medio px dentro")
  local f = d.foot_box(100, 50, { x = 3, y = 8, w = 10, h = 8 })
  eq(f.x, 103, "foot x"); eq(f.y, 58, "foot y"); eq(f.w, 10, "foot w"); eq(f.h, 8, "foot h")
end

-- find_door: la de mayor solape
do
  local doors = {
    { name = "a", rect = { x = 0, y = 0, w = 10, h = 10 } },
    { name = "b", rect = { x = 8, y = 0, w = 10, h = 10 } },
  }
  eq(d.find_door(doors, { x = 5, y = 0, w = 5, h = 4 }).name, "a", "gana el de mas solape (a)")
  eq(d.find_door(doors, { x = 10, y = 0, w = 6, h = 4 }).name, "b", "gana el de mas solape (b)")
  eq(d.find_door(doors, { x = 50, y = 50, w = 4, h = 4 }), nil, "ninguna puerta")
end

-- find_zone: anidadas (gana la menor) y borde
do
  local zones = {
    { name = "big", rect = { x = 0, y = 0, w = 100, h = 100 }, properties = {} },
    { name = "small", rect = { x = 40, y = 40, w = 20, h = 20 }, properties = {} },
  }
  eq(d.find_zone(zones, 50, 50).name, "small", "anidada: gana la pequena")
  eq(d.find_zone(zones, 10, 10).name, "big", "fuera de la pequena: la grande")
  eq(d.find_zone(zones, 40, 40).name, "small", "borde superior izquierdo dentro")
  eq(d.find_zone(zones, 60, 50).name, "big", "borde derecho fuera de la pequena")
  eq(d.find_zone(zones, 100, 50), nil, "borde derecho fuera de la grande")
  eq(d.find_zone(zones, -1, 50), nil, "fuera por la izquierda")
end

-- facing_away: cuatro direcciones y empate vertical
do
  eq(d.facing_away(0, 0, 0, -10), "up", "arriba")
  eq(d.facing_away(0, 0, 0, 10), "down", "abajo")
  eq(d.facing_away(0, 0, 10, 0), "right", "derecha")
  eq(d.facing_away(0, 0, -10, 0), "left", "izquierda")
  eq(d.facing_away(0, 0, 5, -5), "up", "empate hacia arriba = vertical")
  eq(d.facing_away(0, 0, 5, 5), "down", "empate hacia abajo = vertical")
  eq(d.facing_away(0, 0, -20, 5), "left", "domina el eje x")
  eq(d.facing_away(0, 0, 0, 0), "down", "mismo punto")
end

-- door_target: @return
do
  local ctx = { return_map = "maps/town.tmx", return_spawn = "exit_mama" }
  local door = { properties = { target_map = "@return", target_spawn = "@return" } }
  local m, s = d.door_target(door, ctx)
  eq(m, "maps/town.tmx", "@return mapa"); eq(s, "exit_mama", "@return spawn")
  local m2, s2, e2 = d.door_target(door, {})
  eq(m2, nil, "@return sin ctx: mapa nil"); eq(s2, nil, "@return sin ctx: spawn nil")
  check(e2 ~= nil, "@return sin ctx: da error")
  local m3, s3 = d.door_target({ properties = { target_spawn = "shed_out" } }, {})
  eq(m3, nil, "mismo mapa = nil"); eq(s3, "shed_out", "spawn del mismo mapa")
  local m4, s4 = d.door_target({ properties = { target_map = "", target_spawn = "x" } }, {})
  eq(m4, nil, "target_map vacio = mismo mapa"); eq(s4, "x", "spawn con target_map vacio")
  local _, _, e5 = d.door_target({ properties = {} }, {})
  check(e5 ~= nil, "sin target_spawn: error")
end

-- spawn_to_position e index_objects / resolve_spawn
do
  local box = { x = 3, y = 8, w = 10, h = 8 }
  local px, py = d.spawn_to_position(128, 188, box)
  eq(px, 120, "spawn -> px"); eq(py, 176, "spawn -> py")
  local f = d.foot_box(px, py, box)
  eq(f.x + f.w / 2, 128, "la caja queda centrada en x"); eq(f.y + f.h / 2, 188, "la caja queda centrada en y")

  local map = { objects = {
    { name = "d1", type = "door", shape = "rect", rect = { x = 1, y = 2, w = 3, h = 4 }, properties = { prompt = "E" } },
    { name = "z1", type = "zone", shape = "rect", rect = { x = 0, y = 0, w = 9, h = 9 }, properties = { zone = "plaza" } },
    { name = "s1", type = "spawn", shape = "point", x = 5, y = 6, properties = { facing = "up" } },
    { name = "s2", type = "spawn", shape = "point", x = 7, y = 8, properties = {} },
    { name = "w", type = "", shape = "rect", rect = { x = 0, y = 0, w = 1, h = 1 }, properties = {} },
  } }
  local idx = d.index_objects(map)
  eq(#idx.doors, 1, "una puerta"); eq(#idx.zones, 1, "una zona")
  eq(idx.doors[1].name, "d1", "nombre de puerta")
  local x, y, fc = d.resolve_spawn(idx.spawns, "s1")
  eq(x, 5, "spawn x"); eq(y, 6, "spawn y"); eq(fc, "up", "spawn facing")
  local _, _, fc2 = d.resolve_spawn(idx.spawns, "s2")
  eq(fc2, nil, "spawn sin facing")
  local nx, err = d.resolve_spawn(idx.spawns, "nope")
  eq(nx, nil, "spawn inexistente"); check(err ~= nil, "spawn inexistente da mensaje")
end

-- Fundido: out 0->255, hold, done una vez, in 255->0, recorte de dt
do
  local f = d.new_fade({ out_time = 0.3, in_time = 0.3, hold = 0.05 })
  eq(d.fade_alpha(f), 0, "idle = 0")
  local a, ev = d.fade_step(f, 0.1)
  eq(a, 0, "idle no avanza"); eq(ev, nil, "idle sin evento")

  d.fade_start_out(f)
  eq(d.fade_alpha(f), 0, "out empieza en 0")
  a, ev = d.fade_step(f, 0.15)
  eq(a, 128, "out a la mitad"); eq(ev, nil, "out sin evento")
  a, ev = d.fade_step(f, 0.15)
  eq(a, 255, "out completo"); eq(ev, nil, "el evento llega tras el hold")
  a, ev = d.fade_step(f, 0.02)
  eq(a, 255, "hold a 255"); eq(ev, nil, "hold sin evento aun")
  a, ev = d.fade_step(f, 0.04)
  eq(a, 255, "fin de hold"); eq(ev, "out_done", "out_done al acabar hold")
  a, ev = d.fade_step(f, 0.5)
  eq(a, 255, "black se mantiene"); eq(ev, nil, "out_done solo una vez")
  a, ev = d.fade_step(f, 0.5)
  eq(a, 255, "black sigue"); eq(ev, nil, "sin segundo out_done")

  d.fade_start_in(f)
  eq(d.fade_alpha(f), 255, "in empieza en 255 (sin destello)")
  a, ev = d.fade_step(f, 0.15)
  eq(a, 128, "in a la mitad"); eq(ev, nil, "in sin evento")
  a, ev = d.fade_step(f, 0.15)
  eq(a, 0, "in completo"); eq(ev, "in_done", "in_done")
  a, ev = d.fade_step(f, 0.15)
  eq(a, 0, "idle tras in"); eq(ev, nil, "in_done solo una vez")

  -- dt enorme: se recorta, un cambio de estado por paso, nunca pasa de 255 ni baja de 0
  local g = d.new_fade({ out_time = 0.3, in_time = 0.3, hold = 0.05 })
  d.fade_start_out(g)
  a, ev = d.fade_step(g, 10)
  eq(a, 255, "dt grande en out: 255"); eq(ev, nil, "dt grande en out: sin evento aun")
  a, ev = d.fade_step(g, 10)
  eq(ev, "out_done", "dt grande en hold: out_done"); eq(a, 255, "dt grande: sigue 255")
  d.fade_start_in(g)
  a, ev = d.fade_step(g, 10)
  eq(a, 0, "dt grande en in: 0"); eq(ev, "in_done", "dt grande en in: in_done")

  -- fade_set_black: negro hasta start_in
  local h = d.new_fade({})
  d.fade_set_black(h)
  eq(d.fade_alpha(h), 255, "set_black = 255")
  a, ev = d.fade_step(h, 1)
  eq(a, 255, "set_black se mantiene"); eq(ev, nil, "set_black sin evento")
end

-- world_state: set notifica solo si cambia; take_arrival se consume una vez
do
  local ws = require("world_state")
  ws.flags = {}
  ws.clear_listeners()
  local calls = {}
  ws.on_change(function(name, new, old) calls[#calls + 1] = { name, new, old } end)

  eq(ws.has("house.chayo.open"), false, "flag sin definir")
  eq(ws.get("house.chayo.open", "x"), "x", "get con default")
  ws.set("house.chayo.open", true)
  eq(#calls, 1, "set notifica el cambio")
  eq(calls[1][1], "house.chayo.open", "nombre notificado")
  eq(calls[1][2], true, "valor nuevo"); eq(calls[1][3], nil, "valor viejo nil")
  ws.set("house.chayo.open", true)
  eq(#calls, 1, "set sin cambio no notifica")
  eq(ws.has("house.chayo.open"), true, "has tras set")
  ws.set("house.chayo.open", false)
  eq(#calls, 2, "cambio a false notifica"); eq(calls[2][3], true, "valor viejo true")
  eq(ws.has("house.chayo.open"), false, "has con false")

  ws.clear_listeners()
  ws.set("otro", 1)
  eq(#calls, 2, "tras clear_listeners no hay avisos")

  eq(ws.take_arrival(), nil, "sin llegada")
  ws.set_ctx({ arrival = { map = "m", spawn = "s" }, return_map = "r" })
  eq(ws.ctx().return_map, "r", "ctx() ve set_ctx")
  local a1 = ws.take_arrival()
  eq(a1 and a1.spawn, "s", "take_arrival devuelve la llegada")
  eq(ws.take_arrival(), nil, "take_arrival se consume una vez")
  eq(ws.ctx().return_map, "r", "take_arrival no toca el resto del ctx")

  -- el global sobrevive a un nuevo require (como en load_scene)
  package.loaded["world_state"] = nil
  local again = require("world_state")
  eq(again.has("otro"), true, "los flags sobreviven al re-require")
end

if failures == 0 then
  print("door_logic: todo OK")
else
  print("door_logic: " .. failures .. " fallos")
  os.exit(1)
end
