-- Prueba de la logica de la hora del dia (issue #66).
-- Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/time_of_day_logic.lua
-- Sin motor: solo time_of_day_logic.

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

local t = require("time_of_day_logic")

-- base y valid
do
  eq(t.base("day"), "day", "base day")
  eq(t.base("dusk"), "day", "base dusk")
  eq(t.base("night"), "night", "base night")
  eq(t.base("dawn"), "night", "base dawn")
  check(t.valid("dusk") and not t.valid("noon"), "valid")
end

-- visible
do
  eq(t.visible(nil, "night"), true, "sin only = visible")
  eq(t.visible("", "night"), true, "only vacio = visible")
  eq(t.visible("night", "night"), true, "night en night")
  eq(t.visible("night", "dawn"), true, "night por hora gruesa en dawn")
  eq(t.visible("night", "day"), false, "night no en day")
  eq(t.visible("day", "dusk"), true, "day por hora gruesa en dusk")
  eq(t.visible("dusk", "dusk"), true, "dusk exacto")
  eq(t.visible("dusk", "day"), false, "dusk no en day")
  eq(t.visible("dusk, night", "dusk"), true, "lista con espacios: dusk")
  eq(t.visible("dusk, night", "night"), true, "lista con espacios: night")
  eq(t.visible("dusk,night", "day"), false, "lista no en day")
  eq(t.visible("dawn", "night"), false, "dawn exacto no en night")
end

-- path
do
  local p = t.path("day", "night")
  eq(#p, 2, "day->night 2 pasos"); eq(p[1], "dusk", "pasa por dusk"); eq(p[2], "night", "termina en night")
  p = t.path("night", "day")
  eq(#p, 2, "night->day 2 pasos"); eq(p[1], "dawn", "pasa por dawn"); eq(p[2], "day", "termina en day")
  p = t.path("day", "dusk")
  eq(#p, 1, "day->dusk 1 paso")
  p = t.path("day", "dawn")
  eq(#p, 1, "day->dawn directo (el ciclo seria de 3 pasos)"); eq(p[1], "dawn", "directo a dawn")
  eq(#t.path("night", "night"), 0, "misma fase: vacio")
  eq(#t.path("night", "noon"), 0, "fase invalida: vacio")
end

-- card_alpha
do
  eq(t.card_alpha(0, 4), 0, "alfa inicial 0")
  eq(t.card_alpha(4, 4), 0, "alfa final 0")
  eq(t.card_alpha(2, 4), 1, "alfa en el centro 1")
  check(math.abs(t.card_alpha(0.4, 4) - 0.5) < 1e-9, "mitad del fundido de entrada")
  check(math.abs(t.card_alpha(3.6, 4) - 0.5) < 1e-9, "mitad del fundido de salida")
  eq(t.card_alpha(1, 0), 0, "duracion 0")
end

-- flags
do
  local f = t.flags("dawn")
  eq(f.time, "dawn", "flag time")
  eq(f["time.dawn"], true, "time.dawn")
  eq(f["time.dusk"], false, "time.dusk apagado")
  eq(f["time.night"], true, "dawn es hora gruesa night")
  eq(f["time.day"], false, "dawn no es day")
  f = t.flags("dusk")
  eq(f["time.day"], true, "dusk es hora gruesa day")
end

-- color
do
  local r, g, b = t.color("night")
  eq(r, 6, "night r"); eq(g, 8, "night g"); eq(b, 18, "night b")
  r = t.color("zzz")
  eq(r, 255, "fase desconocida = dia")
end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("time_of_day_logic: todo OK")
