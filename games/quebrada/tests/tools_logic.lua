-- Prueba de la logica pura de las herramientas (issue #53).
-- Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/tools_logic.lua
package.path = "./games/quebrada/scripts/?.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg)
  check(a == b, msg .. " (esperado " .. tostring(b) .. ", obtenido " .. tostring(a) .. ")")
end

local t = require("tools_logic")

local defs = { { id = "foco" }, { id = "rosario" }, { id = "sal" }, { id = "machete" }, { id = "cables" } }
local flags = {}
local function has(f) return flags[f] and true or false end

-- owned: orden de las definiciones, no el de obtencion
do
  eq(#t.owned(defs, has), 0, "owned: sin herramientas")
  flags["tool.sal"] = true
  flags["tool.foco"] = true
  local o = t.owned(defs, has)
  eq(#o, 2, "owned: dos")
  eq(o[1].id, "foco", "owned: orden de definicion (1)")
  eq(o[2].id, "sal", "owned: orden de definicion (2)")
  eq(t.flag("sal"), "tool.sal", "flag")
end

-- seleccion
do
  local o = t.owned(defs, has)
  local st = {}
  eq(t.ensure_selected(st, o).id, "foco", "ensure: elige la primera")
  eq(st.selected, "foco", "ensure: guarda")
  check(t.select(st, o, 2), "select 2")
  eq(st.selected, "sal", "select: sal")
  eq(t.selected_index(st, o), 2, "selected_index")
  check(not t.select(st, o, 3), "select: casilla vacia")
  check(not t.select(st, o, 0), "select: 0")
  check(not t.select(st, o, 5), "select: fuera de la barra")
  check(not t.select(st, o, "a"), "select: no numero")
  eq(st.selected, "sal", "select: no cambia al fallar")
  -- se pierde la seleccionada (consumida): vuelve a la primera
  flags["tool.sal"] = nil
  o = t.owned(defs, has)
  eq(t.ensure_selected(st, o).id, "foco", "ensure: seleccionada perdida")
  flags["tool.foco"] = nil
  o = t.owned(defs, has)
  eq(t.ensure_selected(st, o), nil, "ensure: sin herramientas")
  eq(st.selected, nil, "ensure: limpia")
end

-- maximo 4 en la barra
do
  for _, d in ipairs(defs) do flags["tool." .. d.id] = true end
  local o = t.owned(defs, has)
  eq(#o, 5, "owned: cinco")
  local st = { selected = "cables" } -- quinta: no cabe en la barra
  eq(t.ensure_selected(st, o).id, "foco", "ensure: la quinta no es seleccionable")
  check(not t.select(st, o, 5), "select: quinta no cabe")
  eq(#t.slot_layout(5, 480, 270), 4, "layout: maximo 4")
  flags = {}
end

-- check_use
do
  check(not t.check_use(nil, has), "use: sin definicion")
  check(not t.check_use({ id = "x" }, has), "use: sin use")
  check(t.check_use({ use = {} }, has), "use: sin condicion")
  local machete = { use = { when = "mona.battle", blocked = "Aun no" } }
  local ok, why = t.check_use(machete, has)
  check(not ok, "use: machete bloqueado")
  eq(why, "Aun no", "use: motivo propio")
  flags["mona.battle"] = true
  check(t.check_use(machete, has), "use: machete en la batalla")
  local _, why2 = t.check_use({ use = { when = "nunca" } }, has)
  eq(why2, "No es para esto", "use: motivo por defecto")
  check(t.check_use({ use = { when = "!nunca" } }, has), "use: negacion")
  flags = {}
end

-- layout
do
  eq(#t.slot_layout(0, 480, 270), 0, "layout: vacia")
  local l = t.slot_layout(2, 480, 270)
  eq(#l, 2, "layout: dos")
  local total = 2 * t.SLOT_W + t.GAP
  eq(l[1].x, math.floor((480 - total) / 2), "layout: centrada")
  eq(l[2].x - l[1].x, t.SLOT_W + t.GAP, "layout: separacion")
  eq(l[1].y, 270 - t.SLOT_H - 4, "layout: abajo")
  check(l[2].x + l[2].w <= 480, "layout: dentro de la pantalla")
end

if failures > 0 then print(failures .. " fallos"); os.exit(1) end
print("tools_logic: todo OK")
