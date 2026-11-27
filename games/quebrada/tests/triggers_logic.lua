-- Prueba de la logica de los triggers de mapa (issue #78).
-- Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/triggers_logic.lua
-- Sin motor: solo triggers_logic (y door_logic / missions_logic, que no tocan el motor).

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

local t = require("triggers_logic")

local function trig(name, id, x, y, w, h, props)
  local p = { trigger = id, mission = "chequelo" }
  for k, v in pairs(props or {}) do p[k] = v end
  return { name = name, type = "trigger", shape = "rect", rect = { x = x, y = y, w = w, h = h }, properties = p }
end

local function box(x, y) return { x = x, y = y, w = 10, h = 8 } end

-- index / group
local objs = {
  trig("a", "alfa", 0, 0, 32, 32, { requires = "mission.chequelo.night_active" }),
  trig("b1", "beta", 100, 0, 32, 32),
  trig("b2", "beta", 120, 0, 32, 32),
  { name = "sin_id", type = "trigger", shape = "rect", rect = { x = 0, y = 0, w = 1, h = 1 }, properties = { trigger = "" } },
  { name = "sin_props", type = "trigger", shape = "rect", rect = { x = 0, y = 0, w = 1, h = 1 } },
  { name = "punto", type = "trigger", shape = "point", x = 1, y = 1, properties = { trigger = "p" } },
  { name = "puerta", type = "door", shape = "rect", rect = { x = 0, y = 0, w = 1, h = 1 }, properties = { trigger = "x" } },
}
local list = t.index(objs)
eq(#list, 3, "index: solo triggers rect con id")
local groups, order = t.group(list)
eq(#order, 2, "group: dos ids")
eq(order[1], "alfa", "group: orden de aparicion")
eq(#groups.beta.rects, 2, "group: mismo id = union de rects")
eq(groups.alfa.props.mission, "chequelo", "group: props del primer rect")
eq(#t.index(nil), 0, "index(nil)")

-- step: enter, una sola vez por estancia, exit, reentrada
do
  local st = t.new_state()
  local ok = true
  local can = function() return ok end
  local ev = t.step(st, groups, order, box(200, 200), can)
  eq(#ev, 0, "fuera: sin eventos")
  ev = t.step(st, groups, order, box(10, 10), can)
  eq(#ev, 1, "dentro: enter")
  eq(ev[1].kind, "enter", "enter kind")
  eq(ev[1].group.id, "alfa", "enter group")
  ev = t.step(st, groups, order, box(12, 12), can)
  eq(#ev, 0, "sigue dentro: no repite")
  ev = t.step(st, groups, order, box(200, 200), can)
  eq(#ev, 1, "salir tras disparar: exit")
  eq(ev[1].kind, "exit", "exit kind")
  ev = t.step(st, groups, order, box(200, 200), can)
  eq(#ev, 0, "fuera otra vez: nada")
  ev = t.step(st, groups, order, box(10, 10), can)
  eq(#ev, 1, "reentrada: enter de nuevo")

  -- union: pasar de un rect a otro solapado no sale ni entra
  st = t.new_state()
  ev = t.step(st, groups, order, box(101, 5), can)
  eq(#ev, 1, "beta: enter por el primer rect")
  ev = t.step(st, groups, order, box(140, 5), can)
  eq(#ev, 0, "beta: del rect 1 al 2 sin eventos (se solapan)")
  ev = t.step(st, groups, order, box(300, 5), can)
  eq(#ev, 1, "beta: exit al salir de la union")
end

-- la condicion se cumple estando dentro: dispara entonces; exit solo si disparo
do
  local st = t.new_state()
  local ok = false
  local can = function() return ok end
  local ev = t.step(st, groups, order, box(10, 10), can)
  eq(#ev, 0, "condicion falsa: no entra")
  ev = t.step(st, groups, order, box(10, 10), can)
  eq(#ev, 0, "sigue falsa")
  ok = true
  ev = t.step(st, groups, order, box(10, 10), can)
  eq(#ev, 1, "la condicion pasa a verdadera dentro: enter")
  ok = false
  ev = t.step(st, groups, order, box(10, 10), can)
  eq(#ev, 0, "no hay exit mientras sigue dentro")
  ev = t.step(st, groups, order, box(200, 200), can)
  eq(#ev, 1, "exit tras haber disparado")

  st = t.new_state()
  t.step(st, groups, order, box(10, 10), function() return false end)
  ev = t.step(st, groups, order, box(200, 200), function() return true end)
  eq(#ev, 0, "salir sin haber disparado: sin exit")
end

-- condition_ok: compuerta de mision y requires
do
  local flags = { ["mission.chequelo.night_active"] = true, ["chequelo.light_appears"] = false }
  local flag_fn = function(n) return flags[n] end
  local state = "none"
  local state_fn = function() return state end
  local g_req = { props = { mission = "chequelo", requires = "mission.chequelo.night_active,!chequelo.light_appears" } }
  local g_empty = { props = { mission = "chequelo", requires = "" } }
  local g_nil = { props = { mission = "chequelo" } }
  for _, s in ipairs({ "none", "offered", "rejected", "done", "failed" }) do
    state = s
    eq(t.condition_ok(g_empty, flag_fn, state_fn), false, "mision en " .. s .. ": cerrado")
  end
  state = "accepted"
  eq(t.condition_ok(g_empty, flag_fn, state_fn), true, "accepted + requires vacio = verdadero")
  eq(t.condition_ok(g_nil, flag_fn, state_fn), true, "accepted + sin requires = verdadero")
  state = "night_active"
  eq(t.condition_ok(g_empty, flag_fn, state_fn), true, "night_active + requires vacio")
  eq(t.condition_ok(g_req, flag_fn, state_fn), true, "requires cumplido")
  flags["chequelo.light_appears"] = true
  eq(t.condition_ok(g_req, flag_fn, state_fn), false, "requires con flag negado falso")
  eq(t.condition_ok({ props = { requires = "mission.chequelo.night_active" } }, flag_fn, state_fn), true, "sin mision: solo requires")
end

-- outcome
eq(t.outcome(nil), "done", "outcome sin desvio")
eq(t.outcome(""), "done", "outcome vacio")
eq(t.outcome("detour_cafetal"), "detour_cafetal", "outcome con desvio")
eq(t.outcome("detour_door"), "detour_door", "outcome con desvio de la puerta")

-- interval_step
do
  local timer, fired = 0, false
  timer, fired = t.interval_step(timer, 4, 9)
  eq(fired, false, "interval: aun no")
  timer, fired = t.interval_step(timer, 4, 9)
  eq(fired, false, "interval: 8 s")
  timer, fired = t.interval_step(timer, 2, 9)
  eq(fired, true, "interval: 10 s dispara")
  eq(timer, 0, "interval: reinicia")
  timer, fired = t.interval_step(nil, 1, 9)
  eq(fired, false, "interval: timer nil cuenta como 0")
end

-- split_flags / validate
do
  local f = t.split_flags("a, b ,c")
  eq(#f, 3, "split_flags: tres")
  eq(f[2], "b", "split_flags: recorta espacios")
  eq(#t.split_flags(nil), 0, "split_flags(nil)")
  eq(#t.split_flags(""), 0, "split_flags('')")
  local errs = t.validate(groups, { "alfa", "beta" })
  eq(#errs, 0, "validate: completo")
  errs = t.validate(groups, { "alfa", "gamma" })
  eq(#errs, 1, "validate: falta gamma")
  local g2 = { x = { id = "x", rects = {}, props = {} } }
  eq(#t.validate(g2, {}), 1, "validate: sin mission")
end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("triggers_logic OK")
