-- Validacion de la hoja de la escuela (tilesets/school.{tsx,png}). Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/school_check.lua
-- Sin motor: parsea el XML con patrones de cadena (como buildings_check.lua). Convenciones en games/quebrada/docs/school.md.

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

local STSX, SPNG = "games/quebrada/tilesets/school.tsx", "games/quebrada/tilesets/school.png"
local LAYERS = { ground = true, overlay = true, ysort = true, above = true }
local SURFACES = { lastre = true, zacate = true, madera = true, concreto = true }

local tsx = read_file(STSX)
local head = tsx:match("<tileset ([^>]*)>")
local tw, th = tonumber(attr(head, "tilewidth")), tonumber(attr(head, "tileheight"))
local columns, tilecount = tonumber(attr(head, "columns")), tonumber(attr(head, "tilecount"))
check(tw == 16 and th == 16, "el tamano de tile debe ser 16x16")
local img_w = tonumber(tsx:match('<image source="[^"]*" width="(%d+)"'))
local img_h = tonumber(tsx:match('<image source="[^"]*" width="%d+" height="(%d+)"'))
check(img_w == columns * tw and img_h == math.ceil(tilecount / columns) * th, "tamano de la imagen != columnas/filas del tsx")
check(tsx:match('<image source="school%.png"') ~= nil, "el tsx debe apuntar a school.png")
local png = read_file(SPNG)
check(png:sub(1, 8) == "\137PNG\r\n\26\n", "school.png no tiene firma PNG")
local pw, ph = string.unpack(">I4I4", png, 17)
check(pw == img_w and ph == img_h, "school.png (" .. pw .. "x" .. ph .. ") no coincide con el tsx")

-- firstgid del mapa = tilecount(town) + tilecount(buildings) + tilecount(park) + 1
local function count_of(path) return tonumber(attr(read_file(path):match("<tileset ([^>]*)>"), "tilecount")) end
local firstgid = count_of("games/quebrada/tilesets/town.tsx") + count_of("games/quebrada/tilesets/buildings.tsx") + count_of("games/quebrada/tilesets/park.tsx") + 1
local tmx = read_file("games/quebrada/maps/zona1.tmx")
check(tmx:match('<tileset firstgid="' .. firstgid .. '" source="%.%./tilesets/school%.tsx"/>') ~= nil, "zona1.tmx debe declarar school.tsx con firstgid " .. firstgid)

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
  check(n ~= nil and n:match("^escuela_") ~= nil, "tile " .. tid .. ": el nombre debe empezar por escuela_ (" .. tostring(n) .. ")")
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
  if t.props.solid then check(layer == "ysort", "la escuela no tiene agua: solid solo en ysort: " .. tostring(n)) end
  if layer == "above" then check(not t.props.solid, "solid en tile above: " .. tostring(n)) end
end
check(n_tiles > 0, "school.tsx sin tiles")

for _, n in ipairs({ "escuela_patio_a", "escuela_patio_b", "escuela_patio_grieta", "escuela_cerca_h", "escuela_cerca_v", "escuela_pilar",
                     "escuela_asta_0_0", "escuela_asta_0_1", "escuela_asta_0_2", "escuela_rotulo_0_0", "escuela_rotulo_1_0", "escuela_rotulo_0_1", "escuela_rotulo_1_1",
                     "escuela_aulas_a_0_0", "escuela_aulas_a_9_5", "escuela_aulas_b_0_0", "escuela_aulas_b_9_5" }) do
  check(by_name[n] ~= nil, "falta el tile requerido " .. n)
end
-- suelos: concreto y transitables (sin solid)
for _, n in ipairs({ "escuela_patio_a", "escuela_patio_b", "escuela_patio_grieta" }) do
  check(by_name[n] and by_name[n].props.layer == "ground" and by_name[n].props.surface == "concreto" and not by_name[n].props.solid, n .. ": ground concreto transitable")
end
-- cerca y pilar: ysort y solid
for _, n in ipairs({ "escuela_cerca_h", "escuela_cerca_v", "escuela_pilar" }) do
  check(by_name[n] and by_name[n].props.layer == "ysort" and by_name[n].props.solid == true, n .. " debe ser ysort y solid")
end
-- asta (1x3): las dos celdas de arriba above, la base ysort solid; rotulo (2x2): arriba above, postes ysort solid
check(by_name.escuela_asta_0_0.props.layer == "above" and by_name.escuela_asta_0_1.props.layer == "above", "asta: las celdas superiores son above")
check(by_name.escuela_asta_0_2.props.layer == "ysort" and by_name.escuela_asta_0_2.props.solid == true, "asta: la base es ysort y solid")
for _, n in ipairs({ "escuela_rotulo_0_0", "escuela_rotulo_1_0" }) do check(by_name[n].props.layer == "above", n .. " debe ser above") end
for _, n in ipairs({ "escuela_rotulo_0_1", "escuela_rotulo_1_1" }) do check(by_name[n].props.layer == "ysort" and by_name[n].props.solid == true, n .. " debe ser ysort y solid") end
-- bloques de aulas: filas 0-3 techo (above, nunca solid), fila 4 pared (solid), fila 5 corredor (caminable, sort_offset), celdas lit (ysort, sin solid)
for _, b in ipairs({ "escuela_aulas_a", "escuela_aulas_b" }) do
  local roof, wall, corridor, lit = 0, 0, 0, 0
  for n, t in pairs(by_name) do
    local cx, cy = n:match("^" .. b .. "_(%d+)_(%d+)$")
    if cx then
      cy = tonumber(cy)
      if cy < 4 then roof = roof + 1; check(t.props.layer == "above" and not t.props.solid, n .. ": el techo es above y no solid")
      elseif cy == 4 then wall = wall + 1; check(t.props.layer == "ysort" and t.props.solid == true, n .. ": la pared es ysort y solid")
      else corridor = corridor + 1; check(t.props.layer == "ysort" and not t.props.solid and t.props.sort_offset == -16, n .. ": el corredor es ysort, caminable, sort_offset -16") end
    elseif n:match("^" .. b .. "_lit_%d+_%d+$") then
      lit = lit + 1
      check(t.props.layer == "ysort" and not t.props.solid and t.props.surface == nil, n .. ": celda lit ysort sin solid")
    end
  end
  check(roof >= 30 and wall == 10 and corridor == 10, b .. ": celdas de techo / pared / corredor (" .. roof .. "/" .. wall .. "/" .. corridor .. ")")
  check(lit >= 4, b .. ": celdas de ventanas encendidas (" .. lit .. ")")
end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("school_check OK")
