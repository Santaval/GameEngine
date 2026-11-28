-- Validacion de la hoja del Ebais (tilesets/ebais.{tsx,png}). Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/ebais_check.lua
-- Sin motor: parsea el XML con patrones de cadena (como school_check.lua). Convenciones en games/quebrada/docs/ebais.md.

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

local ETSX, EPNG = "games/quebrada/tilesets/ebais.tsx", "games/quebrada/tilesets/ebais.png"
local LAYERS = { ground = true, overlay = true, ysort = true, above = true }
local SURFACES = { lastre = true, zacate = true, madera = true, concreto = true }

local tsx = read_file(ETSX)
local head = tsx:match("<tileset ([^>]*)>")
local tw, th = tonumber(attr(head, "tilewidth")), tonumber(attr(head, "tileheight"))
local columns, tilecount = tonumber(attr(head, "columns")), tonumber(attr(head, "tilecount"))
check(tw == 16 and th == 16, "el tamano de tile debe ser 16x16")
local img_w = tonumber(tsx:match('<image source="[^"]*" width="(%d+)"'))
local img_h = tonumber(tsx:match('<image source="[^"]*" width="%d+" height="(%d+)"'))
check(img_w == columns * tw and img_h == math.ceil(tilecount / columns) * th, "tamano de la imagen != columnas/filas del tsx")
check(tsx:match('<image source="ebais%.png"') ~= nil, "el tsx debe apuntar a ebais.png")
local png = read_file(EPNG)
check(png:sub(1, 8) == "\137PNG\r\n\26\n", "ebais.png no tiene firma PNG")
local pw, ph = string.unpack(">I4I4", png, 17)
check(pw == img_w and ph == img_h, "ebais.png (" .. pw .. "x" .. ph .. ") no coincide con el tsx")

-- firstgid del mapa = tilecount(town) + tilecount(buildings) + tilecount(park) + tilecount(school) + 1
local function count_of(path) return tonumber(attr(read_file(path):match("<tileset ([^>]*)>"), "tilecount")) end
local firstgid = 1
for _, n in ipairs({ "town", "buildings", "park", "school" }) do firstgid = firstgid + count_of("games/quebrada/tilesets/" .. n .. ".tsx") end
local tmx = read_file("games/quebrada/maps/zona1.tmx")
check(tmx:match('<tileset firstgid="' .. firstgid .. '" source="%.%./tilesets/ebais%.tsx"/>') ~= nil, "zona1.tmx debe declarar ebais.tsx con firstgid " .. firstgid)

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
  check(n ~= nil and n:match("^ebais_") ~= nil, "tile " .. tid .. ": el nombre debe empezar por ebais_ (" .. tostring(n) .. ")")
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
  if t.props.solid then check(layer == "ysort", "el Ebais no tiene agua: solid solo en ysort: " .. tostring(n)) end
  if layer == "above" then check(not t.props.solid, "solid en tile above: " .. tostring(n)) end
end
check(n_tiles > 0, "ebais.tsx sin tiles")

for _, n in ipairs({ "ebais_piso_a", "ebais_piso_b", "ebais_piso_grieta", "ebais_parqueo_linea", "ebais_banca", "ebais_maceta", "ebais_basurero",
                     "ebais_rotulo_0_0", "ebais_rotulo_1_0", "ebais_edificio_0_3", "ebais_edificio_11_4", "ebais_edificio_techo_0_0", "ebais_edificio_techo_11_2" }) do
  check(by_name[n] ~= nil, "falta el tile requerido " .. n)
end
-- suelos: concreto y transitables (sin solid)
for _, n in ipairs({ "ebais_piso_a", "ebais_piso_b", "ebais_piso_grieta", "ebais_parqueo_linea" }) do
  check(by_name[n] and by_name[n].props.layer == "ground" and by_name[n].props.surface == "concreto" and not by_name[n].props.solid, n .. ": ground concreto transitable")
end
-- bancas, macetas, basurero y rotulo (2x1): ysort y solid
for _, n in ipairs({ "ebais_banca", "ebais_maceta", "ebais_basurero", "ebais_rotulo_0_0", "ebais_rotulo_1_0" }) do
  check(by_name[n] and by_name[n].props.layer == "ysort" and by_name[n].props.solid == true, n .. " debe ser ysort y solid")
end
-- edificio 12x7: celdas de pared <name>_<cx>_<cy> (ysort: solid salvo las 16 celdas abiertas del porche, cols 2-9 filas 5-6, con sort_offset -16),
-- celdas de techo <name>_techo_<cx>_<cy> (above, nunca solid: filas 0-2 techo principal, filas 5-6 techo bajo del porche), celdas lit (ysort, sin solid)
do
  local b = "ebais_edificio"
  local wall, open, roof, lit = 0, 0, 0, 0
  for n, t in pairs(by_name) do
    local cx, cy = n:match("^" .. b .. "_(%d+)_(%d+)$")
    if cx then
      cx, cy = tonumber(cx), tonumber(cy)
      check(cx < 12 and cy < 7, n .. ": fuera del edificio 12x7")
      local porch = cy >= 5 and cx >= 2 and cx <= 9
      if porch then
        open = open + 1
        check(t.props.layer == "ysort" and not t.props.solid and t.props.sort_offset == -16, n .. ": el porche es ysort, caminable, sort_offset -16")
      else
        wall = wall + 1
        check(t.props.layer == "ysort" and t.props.solid == true, n .. ": la pared es ysort y solid")
      end
    else
      cx, cy = n:match("^" .. b .. "_techo_(%d+)_(%d+)$")
      if cx then
        roof = roof + 1
        check(t.props.layer == "above" and not t.props.solid and t.props.surface == nil, n .. ": el techo es above y no solid")
      elseif n:match("^" .. b .. "_lit_%d+_%d+$") then
        lit = lit + 1
        check(t.props.layer == "ysort" and not t.props.solid and t.props.surface == nil, n .. ": celda lit ysort sin solid")
      end
    end
  end
  check(wall == 24 and open == 16, b .. ": celdas de pared / porche abierto (" .. wall .. "/" .. open .. ")")
  check(roof >= 36 + 8, b .. ": celdas de techo (" .. roof .. ")")
  check(lit >= 4, b .. ": celdas de ventanas encendidas (" .. lit .. ")")
end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("ebais_check OK")
