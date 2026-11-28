-- Validacion de la hoja del rio (tilesets/rio.{tsx,png}): agua rapida y profunda, orillas (esquinas interiores), grava, el puente de concreto (suelo del
-- tablero, barandas amarillas oxidadas, poste, estribos) y las rocas del cauce. Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/rio_check.lua
-- Sin motor: parsea el XML con patrones de cadena (como monte_check.lua). Convenciones en games/quebrada/docs/rio.md.

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

local RTSX, RPNG = "games/quebrada/tilesets/rio.tsx", "games/quebrada/tilesets/rio.png"
local LAYERS = { ground = true, overlay = true, ysort = true, above = true }
local SURFACES = { lastre = true, zacate = true, madera = true, concreto = true }

local tsx = read_file(RTSX)
local head = tsx:match("<tileset ([^>]*)>")
local tw, th = tonumber(attr(head, "tilewidth")), tonumber(attr(head, "tileheight"))
local columns, tilecount = tonumber(attr(head, "columns")), tonumber(attr(head, "tilecount"))
check(tw == 16 and th == 16, "el tamano de tile debe ser 16x16")
check(columns == 16 and tilecount == 64, "la hoja es de 16 x 4 tiles (64 ids), tiene " .. tostring(columns) .. " columnas y tilecount " .. tostring(tilecount))
local img_w = tonumber(tsx:match('<image source="[^"]*" width="(%d+)"'))
local img_h = tonumber(tsx:match('<image source="[^"]*" width="%d+" height="(%d+)"'))
check(img_w == columns * tw and img_h == math.ceil(tilecount / columns) * th, "tamano de la imagen != columnas/filas del tsx")
check(tsx:match('<image source="rio%.png"') ~= nil, "el tsx debe apuntar a rio.png")
local png = read_file(RPNG)
check(png:sub(1, 8) == "\137PNG\r\n\26\n", "rio.png no tiene firma PNG")
local pw, ph = string.unpack(">I4I4", png, 17)
check(pw == img_w and ph == img_h, "rio.png (" .. pw .. "x" .. ph .. ") no coincide con el tsx")

-- firstgid del mapa = suma de los tilecount de town, buildings, park, school, ebais y monte + 1 (ver games/quebrada/tests/zona1_consts.lua)
local function count_of(path) return tonumber(attr(read_file(path):match("<tileset ([^>]*)>"), "tilecount")) end
local firstgid = 1
for _, n in ipairs({ "town", "buildings", "park", "school", "ebais", "monte" }) do firstgid = firstgid + count_of("games/quebrada/tilesets/" .. n .. ".tsx") end
local Z = dofile("games/quebrada/tests/zona1_consts.lua")
check(firstgid == Z.RIO_FIRSTGID, "firstgid del rio debe ser " .. Z.RIO_FIRSTGID .. " (zona1_consts.lua), calculado " .. firstgid)
local tmx = read_file("games/quebrada/maps/zona1.tmx")
check(tmx:match('<tileset firstgid="' .. firstgid .. '" source="%.%./tilesets/rio%.tsx"/>') ~= nil, "zona1.tmx debe declarar rio.tsx con firstgid " .. firstgid)

-- los nombres de town y monte no se repiten
local taken = {}
for _, f in ipairs({ "town", "monte" }) do
  for body in read_file("games/quebrada/tilesets/" .. f .. ".tsx"):gmatch('<tile id="%d+">(.-)</tile>') do taken[body:match('name="name" value="([^"]*)"') or ""] = true end
end

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
  check(n ~= nil and n:match("^rio_") ~= nil, "tile " .. tid .. ": el nombre debe empezar por rio_ (" .. tostring(n) .. ")")
  check(not by_name[n or ""], "nombre repetido: " .. tostring(n))
  check(not taken[n or ""], "el nombre choca con un tile de town / monte: " .. tostring(n))
  by_name[n or ""] = t
  check(t.id >= 0 and t.id < tilecount, "id fuera del tileset: " .. tid)
  local layer = t.props.layer
  check(LAYERS[layer] == true, "tile " .. tostring(n) .. ": layer invalida " .. tostring(layer))
  if layer == "ground" and not t.props.solid then
    check(SURFACES[t.props.surface] == true, "ground sin surface valida: " .. tostring(n))
  else
    check(t.props.surface == nil, "solo el suelo transitable lleva surface: " .. tostring(n))
  end
  if t.props.solid then check(layer == "ysort" or layer == "ground", "solid solo en ysort o en el agua (ground): " .. tostring(n)) end
  if layer == "above" then check(not t.props.solid, "solid en tile above: " .. tostring(n)) end
end
check(n_tiles >= 19, "rio.tsx con pocos tiles (" .. n_tiles .. ")")

-- agua: suelo solido sin surface (el agua no se camina)
for _, n in ipairs({ "rio_water_rapids_a", "rio_water_rapids_b", "rio_water_dark" }) do
  local t = by_name[n]
  check(t and t.props.layer == "ground" and t.props.solid == true and t.props.surface == nil, n .. ": agua = ground solido sin surface")
end
-- orillas y grava: suelo transitable (lastre)
for _, n in ipairs({ "rio_bank_inner_ne", "rio_bank_inner_nw", "rio_bank_inner_se", "rio_bank_inner_sw", "rio_gravel_a", "rio_gravel_b" }) do
  local t = by_name[n]
  check(t and t.props.layer == "ground" and t.props.surface == "lastre" and not t.props.solid, n .. ": ground lastre transitable")
end
-- puente: suelo del tablero (concreto, transitable), barandas / poste / estribos solidos (ysort)
for _, n in ipairs({ "rio_deck_curb_w", "rio_deck_curb_e" }) do
  local t = by_name[n]
  check(t and t.props.layer == "ground" and t.props.surface == "concreto" and not t.props.solid, n .. ": ground concreto transitable")
end
for _, n in ipairs({ "rio_rail_w", "rio_rail_e", "rio_post", "rio_abutment_w", "rio_abutment_e", "rio_boulder_a", "rio_boulder_b", "rio_boulder_c" }) do
  local t = by_name[n]
  check(t and t.props.layer == "ysort" and t.props.solid == true, n .. ": ysort y solid")
end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("rio_check OK")
