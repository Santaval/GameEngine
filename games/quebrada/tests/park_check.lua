-- Validacion de la hoja del parque (tilesets/park.{tsx,png}). Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/park_check.lua
-- Sin motor: parsea el XML con patrones de cadena (como buildings_check.lua). Convenciones en games/quebrada/docs/park.md.

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end
local function read_file(path)
  local f = assert(io.open(path, "rb"), "no se pudo abrir " .. path)
  local s = f:read("a")
  f:close()
  return s
end
local function attr(s, name) return s:match(name .. '="([^"]*)"') end

local PTSX, PPNG = "games/quebrada/tilesets/park.tsx", "games/quebrada/tilesets/park.png"
local LAYERS = { ground = true, overlay = true, ysort = true, above = true }
local SURFACES = { lastre = true, zacate = true, madera = true, concreto = true }

local tsx = read_file(PTSX)
local head = tsx:match("<tileset ([^>]*)>")
local tw, th = tonumber(attr(head, "tilewidth")), tonumber(attr(head, "tileheight"))
local columns, tilecount = tonumber(attr(head, "columns")), tonumber(attr(head, "tilecount"))
check(tw == 16 and th == 16, "el tamano de tile debe ser 16x16")
local img_w = tonumber(tsx:match('<image source="[^"]*" width="(%d+)"'))
local img_h = tonumber(tsx:match('<image source="[^"]*" width="%d+" height="(%d+)"'))
check(img_w == columns * tw and img_h == math.ceil(tilecount / columns) * th, "tamano de la imagen != columnas/filas del tsx")
check(tsx:match('<image source="park%.png"') ~= nil, "el tsx debe apuntar a park.png")
local png = read_file(PPNG)
check(png:sub(1, 8) == "\137PNG\r\n\26\n", "park.png no tiene firma PNG")
local pw, ph = string.unpack(">I4I4", png, 17)
check(pw == img_w and ph == img_h, "park.png (" .. pw .. "x" .. ph .. ") no coincide con el tsx")

-- firstgid del mapa = tilecount(town) + tilecount(buildings) + 1
local function count_of(path) return tonumber(attr(read_file(path):match("<tileset ([^>]*)>"), "tilecount")) end
local firstgid = count_of("games/quebrada/tilesets/town.tsx") + count_of("games/quebrada/tilesets/buildings.tsx") + 1
local tmx = read_file("games/quebrada/maps/zona1.tmx")
check(tmx:match('<tileset firstgid="' .. firstgid .. '" source="%.%./tilesets/park%.tsx"/>') ~= nil, "zona1.tmx debe declarar park.tsx con firstgid " .. firstgid)

local by_name, n_tiles = {}, 0
for tid, body in tsx:gmatch('<tile id="(%d+)">(.-)</tile>') do
  local t = { id = tonumber(tid), props = {} }
  for name, rest in body:gmatch('<property name="([^"]+)"([^>]*)/>') do
    local v = rest:match('value="([^"]*)"')
    local ty = rest:match('type="([^"]*)"')
    if ty == "bool" then v = (v == "true") elseif ty == "int" then v = tonumber(v) end
    t.props[name] = v
  end
  n_tiles = n_tiles + 1
  local n = t.props.name
  check(n ~= nil and n:match("^park_") ~= nil, "tile " .. tid .. ": el nombre debe empezar por park_ (" .. tostring(n) .. ")")
  check(not by_name[n or ""], "nombre repetido: " .. tostring(n))
  by_name[n or ""] = t
  check(t.id >= 0 and t.id < tilecount, "id fuera del tileset: " .. tid)
  local layer = t.props.layer
  check(LAYERS[layer] == true, "tile " .. tostring(n) .. ": layer invalida " .. tostring(layer))
  if layer == "ground" and not t.props.solid then
    check(SURFACES[t.props.surface] == true, "ground sin surface valida: " .. tostring(n))
  else
    check(t.props.surface == nil, "solo el suelo lleva surface: " .. tostring(n))
  end
  if t.props.solid then check(layer == "ysort" or layer == "ground", "solid solo en ground (agua) o ysort: " .. tostring(n)) end
  if t.props.solid then check(layer == "ysort", "el parque no tiene agua: solid solo en ysort: " .. tostring(n)) end
  if layer == "above" then check(not t.props.solid, "solid en tile above: " .. tostring(n)) end
end
check(n_tiles > 0, "park.tsx sin tiles")

for _, n in ipairs({ "park_skate_plain", "park_skate_cracked", "park_skate_line_h", "park_bank_n", "park_bank_in_ne", "park_bank_out_sw", "park_rail_l", "park_box",
                     "park_sand_a", "park_swing_0_0", "park_swing_0_1", "park_slide_0_1", "park_climb_1_1", "park_bench", "park_seesaw_l",
                     "park_court_green_a", "park_court_blue_a", "park_walk_a", "park_line_ew", "park_line_nsew", "park_hoop_l_0_0", "park_hoop_l_0_1",
                     "park_goal_l_0_0", "park_goal_r_0_4" }) do
  check(by_name[n] ~= nil, "falta el tile requerido " .. n)
end
-- superficies pedidas: skate/cancha concreto, arena lastre
check(by_name.park_skate_plain and by_name.park_skate_plain.props.surface == "concreto", "park_skate_plain: surface concreto")
check(by_name.park_court_green_a and by_name.park_court_green_a.props.surface == "concreto", "park_court_green_a: surface concreto")
check(by_name.park_sand_a and by_name.park_sand_a.props.surface == "lastre", "park_sand_a: surface lastre")
-- equipo solido: bases de columpio (extremos), aros y arcos; la celda del medio de los columpios no es solida
for _, n in ipairs({ "park_swing_0_1", "park_swing_2_1", "park_slide_0_1", "park_climb_0_1", "park_hoop_l_0_1", "park_hoop_r_0_1", "park_goal_l_0_0", "park_goal_l_0_4", "park_rail_m", "park_box" }) do
  check(by_name[n] and by_name[n].props.solid == true and by_name[n].props.layer == "ysort", n .. " debe ser ysort y solid")
end
check(by_name.park_swing_1_1 and not by_name.park_swing_1_1.props.solid, "park_swing_1_1 (entre los postes) no debe ser solid")
for _, n in ipairs({ "park_swing_0_0", "park_hoop_l_0_0", "park_slide_1_0", "park_climb_0_0" }) do
  check(by_name[n] and by_name[n].props.layer == "above", n .. " debe ser above")
end
-- las rampas son transitables (ground, sin solid)
for n, t in pairs(by_name) do
  if n:match("^park_bank_") or n:match("^park_line_") or n:match("^park_court_") then check(t.props.layer == "ground" and not t.props.solid, n .. " debe ser ground transitable") end
end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("park_check OK")
