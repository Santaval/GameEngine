-- Prueba de la logica pura del guardado (issue #52).
-- Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/save_logic.lua
-- Sin motor: solo save_logic (el ida y vuelta a disco lo prueba engine/tests/SaveFileTest.cpp).

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

local s = require("save_logic")

-- build: forma y copia de ctx
do
  local ctx = {
    arrival = { map = "maps/house_mama.tmx", spawn = "door", facing = "up", fn = print },
    return_map = "maps/town.tmx",
    zone = "calle",
    junk = print,
  }
  local d = s.build({
    flags = { ["day"] = 2, ["house.chayo.open"] = true },
    phase = "night", battery = 42.5,
    map = "maps/house_mama.tmx", scene = "scenes/house_demo.lua", ctx = ctx,
  })
  eq(d.version, s.VERSION, "build: version")
  eq(d.flags.day, 2, "build: flags")
  eq(d.time.phase, "night", "build: fase")
  eq(d.foco.battery, 42.5, "build: bateria")
  eq(d.place.map, "maps/house_mama.tmx", "build: mapa")
  eq(d.place.scene, "scenes/house_demo.lua", "build: escena")
  eq(d.place.ctx.arrival.spawn, "door", "build: ctx.arrival")
  eq(d.place.ctx.arrival.fn, nil, "build: ctx descarta funciones (subtabla)")
  eq(d.place.ctx.junk, nil, "build: ctx descarta funciones")
  eq(d.place.ctx.zone, "calle", "build: ctx.zone")
  check(d.place.ctx.arrival ~= ctx.arrival, "build: ctx es una copia")

  local e = s.build({ map = "m", scene = "s" })
  eq(e.time.phase, "day", "build: fase por defecto")
  eq(e.foco.battery, 90, "build: bateria por defecto")
  check(type(e.flags) == "table", "build: flags vacios")
end

-- migrate: version actual, futura, invalida
do
  local d = { version = s.VERSION, flags = {} }
  check(s.migrate(d) == d, "migrate: version actual pasa igual")
  local r, err = s.migrate({ version = s.VERSION + 1 })
  check(r == nil and err ~= nil, "migrate: version futura se rechaza")
  r, err = s.migrate("hola")
  check(r == nil and err ~= nil, "migrate: no es tabla")
  r, err = s.migrate({})
  check(r == nil and err ~= nil, "migrate: sin version")
  r, err = s.migrate({ version = -1 })
  check(r == nil and err ~= nil, "migrate: version negativa")
  r = s.migrate({ version = s.VERSION + 0.0, flags = {} })
  check(r ~= nil, "migrate: version float entera vale")
end

-- migrate: cadena de migraciones (se simula con una tabla de migraciones propia)
do
  -- Con VERSION = 1, un guardado v0 necesita MIGRATIONS[0]
  local migrations = {
    [0] = function(d)
      d.flags = d.flags or {}
      d.flags["day"] = 1
      return d
    end,
  }
  local r = s.migrate({ version = 0 }, migrations)
  check(r ~= nil, "migrate: v0 -> actual")
  if r then
    eq(r.version, s.VERSION, "migrate: version subida")
    eq(r.flags.day, 1, "migrate: aplico la migracion")
  end

  local r2, err = s.migrate({ version = 0 }, {})
  check(r2 == nil and err ~= nil, "migrate: falta una migracion")

  local boom = { [0] = function() error("mal") end }
  r2, err = s.migrate({ version = 0 }, boom)
  check(r2 == nil and err ~= nil, "migrate: una migracion que falla se reporta")

  local bad = { [0] = function() return nil end }
  r2, err = s.migrate({ version = 0 }, bad)
  check(r2 == nil and err ~= nil, "migrate: una migracion sin tabla se reporta")
end

-- parts: saneado
do
  local d = s.build({
    flags = { a = 1 }, phase = "dawn", battery = 12,
    map = "maps/town.tmx", scene = "scenes/town_demo.lua", ctx = {},
  })
  local p = s.parts(d)
  check(p ~= nil, "parts: guardado valido")
  eq(p.phase, "dawn", "parts: fase")
  eq(p.battery, 12, "parts: bateria")
  eq(p.map, "maps/town.tmx", "parts: mapa")
  eq(p.scene, "scenes/town_demo.lua", "parts: escena")
  eq(p.ctx.arrival.spawn, "default", "parts: sin arrival -> spawn default")
  eq(p.ctx.arrival.map, "maps/town.tmx", "parts: arrival en el mapa guardado")

  d.place.ctx = { arrival = { map = "maps/house_mama.tmx", spawn = "door", facing = "up" }, return_map = "maps/town.tmx" }
  p = s.parts(d)
  eq(p.ctx.arrival.spawn, "door", "parts: arrival guardado se conserva")
  eq(p.ctx.return_map, "maps/town.tmx", "parts: return_map se conserva")

  d.time.phase = "noon"
  eq(s.parts(d).phase, "day", "parts: fase invalida -> day")
  d.foco.battery = 9999
  eq(s.parts(d).battery, 90, "parts: bateria se limita al maximo")
  d.foco.battery = -5
  eq(s.parts(d).battery, 0, "parts: bateria no baja de 0")
  d.foco = nil
  eq(s.parts(d).battery, 90, "parts: sin foco -> bateria llena")

  local bad, err = s.parts({ flags = {}, place = {} })
  check(bad == nil and err ~= nil, "parts: sin lugar se rechaza")
  bad, err = s.parts({ place = { map = "m", scene = "s" } })
  check(bad == nil and err ~= nil, "parts: sin flags se rechaza")
  bad, err = s.parts(nil)
  check(bad == nil and err ~= nil, "parts: nil se rechaza")
end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("save_logic: todo OK")
