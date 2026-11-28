-- Validacion de la hoja "vida" (tilesets/vida.{tsx,png}): rotulos con el nombre de las casas de la calle principal y (despues) la vida de la calle.
-- Se corre desde la raiz del repo:
--   lua games/quebrada/tests/vida_check.lua
-- Sin motor: parsea el XML con patrones de cadena (como rio_check.lua). Convenciones en games/quebrada/docs/vida.md.

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

local VTSX, VPNG = "games/quebrada/tilesets/vida.tsx", "games/quebrada/tilesets/vida.png"
local LAYERS = { ground = true, overlay = true, ysort = true, above = true }
local SURFACES = { lastre = true, zacate = true, madera = true, concreto = true }

local tsx = read_file(VTSX)
local head = tsx:match("<tileset ([^>]*)>")
local tw, th = tonumber(attr(head, "tilewidth")), tonumber(attr(head, "tileheight"))
local columns, tilecount = tonumber(attr(head, "columns")), tonumber(attr(head, "tilecount"))
check(tw == 16 and th == 16, "el tamano de tile debe ser 16x16")
check(columns == 16 and tilecount == 256, "la hoja es de 16 x 16 tiles (256 ids), tiene " .. tostring(columns) .. " columnas y tilecount " .. tostring(tilecount))
local img_w = tonumber(tsx:match('<image source="[^"]*" width="(%d+)"'))
local img_h = tonumber(tsx:match('<image source="[^"]*" width="%d+" height="(%d+)"'))
check(img_w == columns * tw and img_h == math.ceil(tilecount / columns) * th, "tamano de la imagen != columnas/filas del tsx")
check(tsx:match('<image source="vida%.png"') ~= nil, "el tsx debe apuntar a vida.png")
local png = read_file(VPNG)
check(png:sub(1, 8) == "\137PNG\r\n\26\n", "vida.png no tiene firma PNG")
local pw, ph = string.unpack(">I4I4", png, 17)
check(pw == img_w and ph == img_h, "vida.png (" .. pw .. "x" .. ph .. ") no coincide con el tsx")

-- firstgid del mapa = suma de los tilecount de town, buildings, park, school, ebais, monte y rio + 1 (ver games/quebrada/tests/zona1_consts.lua)
local function count_of(path) return tonumber(attr(read_file(path):match("<tileset ([^>]*)>"), "tilecount")) end
local firstgid = 1
for _, n in ipairs({ "town", "buildings", "park", "school", "ebais", "monte", "rio" }) do firstgid = firstgid + count_of("games/quebrada/tilesets/" .. n .. ".tsx") end
local Z = dofile("games/quebrada/tests/zona1_consts.lua")
check(firstgid == Z.VIDA_FIRSTGID, "firstgid de vida debe ser " .. Z.VIDA_FIRSTGID .. " (zona1_consts.lua), calculado " .. firstgid)
local tmx = read_file("games/quebrada/maps/zona1.tmx")
check(tmx:match('<tileset firstgid="' .. firstgid .. '" source="%.%./tilesets/vida%.tsx"/>') ~= nil, "zona1.tmx debe declarar vida.tsx con firstgid " .. firstgid)

-- los nombres de las demas hojas no se repiten (todos los de vida llevan el prefijo vida_, asi que solo se comprueba el prefijo y la unicidad)
local by_name, n_tiles, by_id = {}, 0, {}
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
  check(n ~= nil and n:match("^vida_") ~= nil, "tile " .. tid .. ": el nombre debe empezar por vida_ (" .. tostring(n) .. ")")
  check(not by_name[n or ""], "nombre repetido: " .. tostring(n))
  by_name[n or ""] = t
  by_id[t.id] = t
  check(t.id >= 0 and t.id < tilecount, "id fuera del tileset: " .. tid)
  local layer = t.props.layer
  check(LAYERS[layer] == true, "tile " .. tostring(n) .. ": layer invalida " .. tostring(layer))
  if layer == "ground" and not t.props.solid then
    check(SURFACES[t.props.surface] == true, "ground sin surface valida: " .. tostring(n))
  else
    check(t.props.surface == nil, "solo el suelo transitable lleva surface: " .. tostring(n))
  end
  if t.props.solid then check(layer == "ysort", "solid solo en ysort: " .. tostring(n)) end
  if layer == "above" then check(not t.props.solid, "solid en tile above: " .. tostring(n)) end
end
check(n_tiles >= 36, "vida.tsx con pocos tiles (" .. n_tiles .. ")")

-- rotulos: ids 0-63, ysort y solidos, celdas seguidas de izquierda a derecha (vida_rotulo_<clave>_<cx>_0), de 3 o 4 tiles de ancho
local plaques = {}
for n, t in pairs(by_name) do
  local key, cx = n:match("^vida_rotulo_(.-)_(%d+)_0$")
  if key then
    check(t.id < 64, n .. ": los rotulos usan los ids 0-63")
    check(t.props.layer == "ysort" and t.props.solid == true, n .. ": ysort y solid")
    plaques[key] = plaques[key] or {}
    plaques[key][tonumber(cx)] = t.id
  end
end
local n_plaques = 0
for key, cells in pairs(plaques) do
  n_plaques = n_plaques + 1
  local w = 0
  while cells[w] do w = w + 1 end
  check(w >= 3 and w <= 4, "rotulo " .. key .. ": debe tener 3 o 4 celdas seguidas, tiene " .. w)
  for cx = 1, w - 1 do check(cells[cx] == cells[cx - 1] + 1, "rotulo " .. key .. ": ids seguidos en la hoja") end
end
check(n_plaques == 10, "deben ser 10 rotulos, hay " .. n_plaques)

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("vida_check OK")
