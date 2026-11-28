-- Validacion de la zona 1 (issue #78): maps/zona1.tmx. Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/zona1_check.lua
-- Sin motor: parsea el XML con patrones de cadena (como buildings_check.lua). Todo objeto del
-- TMX se escribe como <object ...>...</object> (nunca autocerrado): el patron de abajo lo necesita.
-- Convenciones en games/quebrada/docs/zona1.md.
-- DESPLAZAMIENTO (LEFT_PAD = 255): todo el layout original esta corrido 255 columnas a la derecha (sitio para los lotes de la escuela y la casa de Olguita al ESTE = izquierda de
-- la calle de asfalto, y para EL MONTE: 500 m = 250 tiles al este de la puerta de la iglesia). Las columnas de este archivo son PAD + (columna original); los literales que antes eran
-- absolutos (con PAD = 16) llevan + D, con D = PAD - 16. Mapa 700x187 (TOP_PAD = 93 filas nuevas arriba), ocho tilesets (town 1, buildings 145; los demas firstgids se calculan: ver zona1_consts.lua).
-- DESPLAZAMIENTO VERTICAL (TOP_PAD = 93, ver docs/rio.md): el rio, su tierra norte y el puente se agregaron ARRIBA. Los literales de FILA de este archivo siguen en el marco ORIGINAL (sin las 93 filas):
-- cell() suma TOP, los objetos del TMX se normalizan restando TOP * 16 px a su y (salvo los que abarcan todo el alto, listados abajo) y map_h es el alto ORIGINAL (94); real_h es el real (187).
-- Las filas nuevas (rio, orillas, puente, calle de asfalto prolongada) se validan con coordenadas absolutas en la seccion "la quebrada" al final.
-- EL MONTE (zona `monte`, cols 10-69, todo el alto), la carretera de asfalto que llega a el (filas 21-24, cols 0-259), el camino de las carretas (lastre) y los 6 AEROGENERADORES: ver la seccion "el monte" al final.
-- EL EBAIS (lote 21x21, cols 55-75 filas 70-90, al SUR de la calle sur) y la CALLE DE LASTRE que continua la calle oeste al sur (cols 77-80, filas 69-93): ver la seccion "el Ebais" mas abajo.
-- BASE ACTUAL (v2 + parque): la calle de adoquin de 100 m con aceras de 1 tile a cada lado, la iglesia al norte y el parque al sur (tileset park, firstgid 529).
-- (v2) la iglesia y su calle de adoquin de 100 m (escala comprimida: 2 m = 1 tile, 50 tiles).
-- LAYOUT DEL USUARIO (Chequelo): al fondo del lastre la casa de mama (sur), 50 m antes la de Chayo (casa_2, sur), en la mitad de la
-- ruta (50 m antes del fin del adoquin) el cafetal al norte; ruta de la iglesia a la puerta de mama, triggers y emisores.
-- Estos chequeos vuelven los de casas, cafetal, ruta, triggers, emisores y la puerta de mama (ver ELEMENTS en tools/tilegen/zona1_map.mjs).

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
local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end
local function attr(s, name) return s:match(name .. '="([^"]*)"') end
local function overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Constantes del mapa que escribe el generador (make tiles): firstgids, PAD, TOP, largo de la calle, cafetal, casas... Las filas ahi son ABSOLUTAS (restar TOP).
local Z = dofile("games/quebrada/tests/zona1_consts.lua")
local ZONA = "games/quebrada/maps/zona1.tmx"
local tmx = read_file(ZONA)

-- ---- mapa ----
local METRES_PER_TILE = 2
local PAD = Z.LEFT_PAD -- LEFT_PAD de tools/tilegen/zona1_map.mjs (el monte a 250 tiles = 500 m de la puerta de la iglesia, a >= 10 tiles del borde izquierdo)
local D = PAD - 16 -- desplazamiento respecto a los literales absolutos escritos con PAD = 16
-- Orientacion: OESTE = DERECHA de la pantalla, ESTE = IZQUIERDA, SUR = abajo, NORTE = arriba.
local EXT_PAVER_M, EXT_LASTRE_M = Z.EXT_PAVER_M, Z.EXT_LASTRE_M
local EXT_PAVER_T, EXT_LASTRE_T = EXT_PAVER_M // METRES_PER_TILE, EXT_LASTRE_M // METRES_PER_TILE -- 275, 100
local EXT_X0 = PAD + 60
local EXT_PAVER_X1 = EXT_X0 + EXT_PAVER_T - 1 -- 334
local LASTRE_X0, LASTRE_X1 = EXT_PAVER_X1 + 1, EXT_PAVER_X1 + EXT_LASTRE_T -- 335, 434
local TOP = Z.TOP_PAD -- TOP_PAD de tools/tilegen/zona1_map.mjs: filas nuevas encima del mapa original (el rio a 175 m de la iglesia queda ~88 tiles al norte; 6 filas de cesped sobre la orilla mas norte)
local MAP_W, MAP_H = LASTRE_X1 + 1 + 10, 94 + TOP -- 700 x 187 (PAD a la izquierda, 10 tiles de margen a la derecha; 3 filas de margen bajo el lote del Ebais, fila 90)
local STREET_X, STREET_Y, STREET_LEN, STREET_W = PAD + 10, 21, 50, 4 -- tiles; 50 tiles = 100 m; ancho 4 (~8 m reales, distorsion conocida)
local CHURCH_X, CHURCH_Y, CHURCH_W, CHURCH_H = PAD + 30, 6, 10, 12 -- tiles
local SIDEWALK_A, SIDEWALK_B = 49, 50 -- gids de sidewalk_a / sidewalk_b (tile ids 48 / 49)
-- firstgids: los declara el TMX; deben coincidir con el generador (zona1_consts.lua) y con 1 + la suma de los tilecount de los tilesets anteriores
local FG = {}
for g, n in tmx:gmatch('<tileset firstgid="(%d+)" source="%.%./tilesets/(%w+)%.tsx"/>') do FG[n] = tonumber(g) end
do
  local expect = 1
  for _, n in ipairs({ "town", "buildings", "park", "school", "ebais", "monte", "rio", "vida" }) do
    check(FG[n] == expect, "firstgid de " .. n .. " en el TMX = " .. tostring(FG[n]) .. ", esperado 1 + tilecounts anteriores = " .. expect)
    expect = expect + tonumber(attr(read_file("games/quebrada/tilesets/" .. n .. ".tsx"):match("<tileset ([^>]*)>"), "tilecount"))
  end
end
check(FG.park == Z.PARK_FIRSTGID and FG.school == Z.SCHOOL_FIRSTGID and FG.ebais == Z.EBAIS_FIRSTGID and FG.monte == Z.MONTE_FIRSTGID and FG.rio == Z.RIO_FIRSTGID and FG.vida == Z.VIDA_FIRSTGID, "los firstgids del TMX no coinciden con zona1_consts.lua (correr make tiles)")
FG = nil
local PARK_FIRSTGID, SCHOOL_FIRSTGID, EBAIS_FIRSTGID, MONTE_FIRSTGID = Z.PARK_FIRSTGID, Z.SCHOOL_FIRSTGID, Z.EBAIS_FIRSTGID, Z.MONTE_FIRSTGID
local PARK_X, PARK_Y, PARK_W, PARK_H = PAD + 10, 27, 50, 37 -- el parque: una cuadra (50 tiles), una fila de cesped bajo la acera sur
local PAVER_A, PAVER_B = 51, 52 -- gids de paver_a / paver_b (town firstgid 1, tile ids 50 / 51)
local head = tmx:match("<map ([^>]*)>")
local map_w, map_h = tonumber(attr(head, "width")), tonumber(attr(head, "height"))
check(map_w == MAP_W and map_h == MAP_H, "el mapa debe ser " .. MAP_W .. "x" .. MAP_H .. " (" .. tostring(map_w) .. "x" .. tostring(map_h) .. ")")
check(tonumber(attr(head, "tilewidth")) == 16 and tonumber(attr(head, "tileheight")) == 16, "tiles de 16x16")
check(STREET_LEN * METRES_PER_TILE == 100, "la calle debe medir 100 m")
check(tmx:match('<property name="metres_per_tile"[^>]-value="2"') ~= nil, "falta metres_per_tile=2 en el mapa")
check(tmx:match('<tileset firstgid="1" source="%.%./tilesets/town%.tsx"/>') ~= nil, "falta el tileset town (firstgid 1)")
check(tmx:match('<tileset firstgid="145" source="%.%./tilesets/buildings%.tsx"/>') ~= nil, "falta el tileset buildings (firstgid 145)")

check(tmx:match('<tileset firstgid="' .. PARK_FIRSTGID .. '" source="%.%./tilesets/park%.tsx"/>') ~= nil, "falta el tileset park (firstgid " .. PARK_FIRSTGID .. ")")
local _, n_tilesets = tmx:gsub("<tileset ", "")
check(tmx:match('<tileset firstgid="' .. SCHOOL_FIRSTGID .. '" source="%.%./tilesets/school%.tsx"/>') ~= nil, "falta el tileset school (firstgid " .. SCHOOL_FIRSTGID .. ")")
check(tmx:match('<tileset firstgid="' .. EBAIS_FIRSTGID .. '" source="%.%./tilesets/ebais%.tsx"/>') ~= nil, "falta el tileset ebais (firstgid " .. EBAIS_FIRSTGID .. ")")
check(tmx:match('<tileset firstgid="' .. MONTE_FIRSTGID .. '" source="%.%./tilesets/monte%.tsx"/>') ~= nil, "falta el tileset monte (firstgid " .. MONTE_FIRSTGID .. ")")
local RIO_FIRSTGID = Z.RIO_FIRSTGID
check(RIO_FIRSTGID == MONTE_FIRSTGID + 256, "rio firstgid = monte + 256 (capacidad 16 x 16 ids)")
check(tmx:match('<tileset firstgid="' .. RIO_FIRSTGID .. '" source="%.%./tilesets/rio%.tsx"/>') ~= nil, "falta el tileset rio (firstgid " .. RIO_FIRSTGID .. ")")
check(n_tilesets == 8, "el mapa debe declarar 8 tilesets (town, buildings, park, school, ebais, monte, rio, vida), tiene " .. n_tilesets)

local layers, ground = {}, {}
for lname, lbody in tmx:gmatch('<layer id="%d+" name="([^"]+)"[^>]*>(.-)</layer>') do
  local n = 0
  local cells = {}
  for v in lbody:match("<data[^>]*>(.-)</data>"):gmatch("%d+") do n = n + 1; cells[n] = tonumber(v) end
  check(n == map_w * map_h, "capa " .. lname .. " con " .. n .. " celdas, esperadas " .. map_w * map_h)
  local props = {}
  for k, v in lbody:gmatch('<property name="([^"]+)"[^>]-value="([^"]*)"') do props[k] = v end
  props._cells = cells
  layers[lname] = props
  if lname == "ground" then ground = cells end
end
for _, n in ipairs({ "ground", "overlay", "objects", "buildings", "windows_lit", "roof_iglesia", "roof_casa_mama", "roof_casa_2", "roof_casa_3", "roof_escuela_aulas_a", "roof_escuela_aulas_b", "roof_ebais_edificio", "canopy", "rotors" }) do
  check(layers[n] ~= nil, "falta la capa " .. n)
end
check(layers.objects and layers.objects.ysort == "true", "objects debe ser ysort")
check(layers.windows_lit and layers.windows_lit.ysort == "true", "windows_lit debe ser ysort")
check(layers.canopy and layers.canopy.above == "true", "canopy debe ser above")
check(layers.rotors and layers.rotors.above == "true", "rotors debe ser above (los rotores animados de los aerogeneradores)")
local real_h = map_h -- alto real (187); map_h pasa a ser el alto ORIGINAL (94): las filas de abajo estan en el marco original
map_h = real_h - TOP
local function rcell(layer, x, y) return layers[layer]._cells[y * map_w + x + 1] end -- x, y ABSOLUTOS (marco nuevo)
local function cell(layer, x, y) return layers[layer]._cells[(y + TOP) * map_w + x + 1] end -- x, y en tiles del marco ORIGINAL

-- clases de suelo por gid, leidas de town.tsx (nombre + propiedad surface)
local tsx = read_file("games/quebrada/tilesets/town.tsx")
local gid_name, gid_surface = {}, {}
for id, body in tsx:gmatch('<tile id="(%d+)">(.-)</tile>') do
  gid_name[tonumber(id) + 1] = body:match('name="name" value="([^"]*)"')
  gid_surface[tonumber(id) + 1] = body:match('name="surface" value="([^"]*)"')
end
local function kind(g)
  local n = gid_name[g]
  if not n then return "other" end
  if n:match("^paver_") then return "paver" end
  if n:match("^asphalt_") then return "asphalt" end
  if n:match("^lastre_") then return "lastre" end
  if n:match("^sidewalk_") then return "sidewalk" end
  if n:match("^grass_") then return "grass" end
  return "other"
end
local function kind_at(x, y) return kind(cell("ground", x, y)) end
-- superficies del tileset (propiedad surface): lastre -> "lastre", adoquin/asfalto/acera -> "concreto", cesped -> "zacate"
local SURF = { paver = "concreto", asphalt = "concreto", sidewalk = "concreto", lastre = "lastre", grass = "zacate" }
for _, y in ipairs({ 22, 70 }) do
  for _, x in ipairs({ PAD + 6, PAD + 62, PAD + 100, PAD + 340, PAD + 420 }) do
    local k = kind_at(x, y)
    check(SURF[k] == nil or gid_surface[cell("ground", x, y)] == SURF[k], "superficie inesperada en (" .. x .. "," .. y .. "): " .. k)
  end
end
local FOOTS = { n = {}, s = {} } -- columnas de caminos / pasillos / calles que cruzan la acera norte (n) o sur (s): lastre en vez de acera (las pone el generador)
for _, side in ipairs({ "n", "s" }) do for _, r in ipairs(Z.PLACE_FOOTS[side]) do for c = r[1], r[2] do FOOTS[side][c] = true end end end
for _, c in ipairs({ Z.CHAYO_FOOT_X, Z.CHAYO_FOOT_X + 1, Z.MAMA_FOOT_X, Z.MAMA_FOOT_X + 1 }) do FOOTS.s[c] = true end
local function rect_is(k, x0, y0, x1, y1, what, skip)
  for y = y0, y1 do for x = x0, x1 do
    if skip and skip[x] then -- columna con un camino que cruza la acera
    elseif kind_at(x, y) ~= k then check(false, what .. ": se esperaba " .. k .. " en (" .. x .. "," .. y .. "), hay " .. kind_at(x, y)); return end
  end end
end

-- ---- objetos ----
local objects, by_name = {}, {}
for ohead, body in tmx:gmatch("<object ([^>]*)>(.-)</object>") do
  local o = {
    id = tonumber(attr(ohead, "id")), name = attr(ohead, "name"), class = attr(ohead, "class"),
    x = tonumber(attr(ohead, "x")), y = tonumber(attr(ohead, "y")),
    w = tonumber(attr(ohead, "width")), h = tonumber(attr(ohead, "height")), props = {},
  }
  for k, rest in body:gmatch('<property name="([^"]+)"([^>]*)/>') do o.props[k] = rest:match('value="([^"]*)"') end
  objects[#objects + 1] = o
  if o.name then by_name[o.name] = o end
end
-- normalizar al marco original: y -= TOP * 16 px (salvo los objetos que abarcan todo el alto o viven en el borde superior)
local FULL_HEIGHT = { wall_top = true, wall_bottom = true, wall_left = true, wall_right = true, zone_zona1 = true, zone_monte = true, edge_calle_este_norte = true }
for _, o in ipairs(objects) do if o.y and not (o.name and FULL_HEIGHT[o.name]) then o.y = o.y - TOP * 16 end end
local function of_class(c)
  local out = {}
  for _, o in ipairs(objects) do if o.class == c then out[#out + 1] = o end end
  return out
end

-- el motor exige el cierre explicito de cada objeto
check(not tmx:find("<object [^>]-/>"), "hay objetos autocerrados (<object .../>): usar <object ...></object>")

-- ---- la calle de adoquin: 50 tiles = 100 m (2 m = 1 tile), horizontal ----
local street_cols = {}
for y = STREET_Y, STREET_Y + STREET_W - 1 do
  local n = 0
  for x = STREET_X, EXT_X0 - 1 do -- la calle original: cols 10-59
    local g = cell("ground", x, y)
    if g == PAVER_A or g == PAVER_B then n = n + 1; street_cols[x] = true end
  end
  check(n == STREET_LEN, "la fila " .. y .. " debe tener " .. STREET_LEN .. " adoquines en las cols 10-59, tiene " .. n)
end
for x = STREET_X, STREET_X + STREET_LEN - 1 do
  check(street_cols[x], "falta adoquin en la columna " .. x .. " de la calle")
end

-- ---- la extension al oeste (derecha): 310 m de adoquin + 200 m de lastre = 510 m = 255 tiles ----
check(EXT_PAVER_T == Z.EXT_PAVER_TILES and EXT_LASTRE_T == Z.EXT_LASTRE_TILES, "extension: " .. Z.EXT_PAVER_TILES .. " + " .. Z.EXT_LASTRE_TILES .. " tiles (zona1_consts.lua)")
check((EXT_PAVER_T + EXT_LASTRE_T) * METRES_PER_TILE == Z.EXT_PAVER_M + Z.EXT_LASTRE_M, "la extension debe medir " .. (Z.EXT_PAVER_M + Z.EXT_LASTRE_M) .. " m")
rect_is("paver", EXT_X0, STREET_Y, EXT_PAVER_X1, STREET_Y + STREET_W - 1, "extension de adoquin (310 m)")
rect_is("lastre", LASTRE_X0, STREET_Y, LASTRE_X1, STREET_Y + STREET_W - 1, "tramo de lastre (200 m)")
rect_is("grass", LASTRE_X1 + 1, STREET_Y, map_w - 1, STREET_Y + STREET_W - 1, "margen tras el lastre")
for y = STREET_Y, STREET_Y + STREET_W - 1 do
  local g = cell("ground", LASTRE_X0, y)
  check(gid_surface[g] == "lastre", "el lastre debe tener surface=lastre en (" .. LASTRE_X0 .. "," .. y .. ")")
  g = cell("ground", EXT_X0 + 10, y)
  check(gid_surface[g] == "concreto", "el adoquin debe tener surface=concreto")
end
-- el lastre no tiene aceras: filas 20 y 25 son cesped
rect_is("grass", LASTRE_X0, STREET_Y - 1, LASTRE_X1, STREET_Y - 1, "sin acera norte en el lastre", FOOTS.n)
-- caminos que arrancan en la fila sur: casas de Chayo y mama, la calle de Los Caliles y el pasillo de Tio Enrique (todo viene del generador)
do
for x = LASTRE_X0, LASTRE_X1 do -- fila 25: cesped salvo donde arrancan los caminos (FOOTS.s)
  local foot = FOOTS.s[x] == true
  check(kind_at(x, STREET_Y + STREET_W) == (foot and "lastre" or "grass"), "sin acera sur en el lastre (fila 25, col " .. x .. ")")
end
end
-- el lastre tiene rodadas (ruts) en las filas interiores
local ruts = 0
for x = LASTRE_X0, LASTRE_X1 do if gid_name[cell("ground", x, STREET_Y + 1)] == "lastre_ruts_h" then ruts = ruts + 1 end end
check(ruts > 50, "el lastre debe tener rodadas (" .. ruts .. ")")

-- ---- aceras de la extension de adoquin (filas 20 y 25, cols 60-334); la sur se abre en la T oeste (cols 61-64) ----
rect_is("sidewalk", EXT_X0, STREET_Y - 1, EXT_PAVER_X1, STREET_Y - 1, "acera norte de la extension", FOOTS.n)
rect_is("sidewalk", EXT_X0, STREET_Y + STREET_W, EXT_X0, STREET_Y + STREET_W, "acera sur (col 60)")
rect_is("paver", PAD + 61, STREET_Y + STREET_W, PAD + 64, STREET_Y + STREET_W, "union en T: sin acera en cols 61-64 de la fila 25 (+PAD)")
rect_is("sidewalk", PAD + 65, STREET_Y + STREET_W, EXT_PAVER_X1, STREET_Y + STREET_W, "acera sur tras la union", FOOTS.s)

-- ---- calles alrededor del parque ----
-- oeste (derecha del parque): adoquin cols 61-64, filas 25-68; acera solo del lado del parque (col 60, filas 25-64)
rect_is("paver", PAD + 61, 25, PAD + 64, 68, "calle oeste del parque")
rect_is("sidewalk", PAD + 60, 25, PAD + 60, 64, "acera de la calle oeste (lado del parque)")
rect_is("grass", PAD + 65, 26, PAD + 65, 68, "la calle oeste no tiene acera en el lado lejano")
-- sur (bajo el parque): adoquin filas 65-68, cols 9-60; acera solo del lado del parque (fila 64)
rect_is("paver", PAD + 9, 65, PAD + 64, 68, "calle sur del parque")
rect_is("sidewalk", PAD + 10, 64, PAD + 60, 64, "acera de la calle sur (lado del parque)")
-- fila 69 (verde): cesped salvo la entrada del Ebais (cols 57-58, concreto) y la calle de lastre (cols 77-80); 3 filas de margen (91-93) bajo el lote del Ebais
rect_is("grass", PAD + 10, 69, 56 + D, 69, "la calle sur no tiene acera en el lado lejano (fila 69, al este del Ebais)")
rect_is("grass", 59 + D, 69, PAD + 60, 69, "la calle sur no tiene acera en el lado lejano (fila 69, entre el Ebais y la calle de lastre)")
rect_is("grass", PAD + 10, 70, 54 + D, map_h - 1, "cesped al este del lote del Ebais")
rect_is("grass", PAD + 10, 91, PAD + 60, map_h - 1, "3 filas de margen bajo el lote del Ebais")
-- este (izquierda del parque): ASFALTO cols 5-8, toda la altura (filas 0-71), aceras en col 4 y col 9
for y = 0, map_h - 1 do
  for x = PAD + 5, PAD + 8 do check(kind_at(x, y) == "asphalt", "falta asfalto en (" .. x .. "," .. y .. ")") end
  -- la acera lejana (col 4 + PAD) esta abierta en las filas 21-24: ahi arranca la carretera del monte (asfalto, cruce limpio)
  local road_row = y >= STREET_Y and y <= STREET_Y + STREET_W - 1
  check(kind_at(PAD + 4, y) == (road_row and "asphalt" or "sidewalk"), "acera lejana (col 4 + PAD) en la fila " .. y .. ": " .. kind_at(PAD + 4, y))
  local mouth = (y >= 21 and y <= 24) or (y >= 65 and y <= 68)
  if mouth then check(kind_at(PAD + 9, y) == "paver", "la boca de la calle en (9+PAD," .. y .. ") debe ser adoquin (sin acera)")
  else check(kind_at(PAD + 9, y) == "sidewalk", "falta la acera del parque (col 9) en la fila " .. y) end
end
check(kind_at(PAD + 3, 30) == "grass" and kind_at(0, 10) == "grass" and kind_at(0, 50) == "grass", "el resto es cesped (el margen izquierdo de PAD columnas)")
-- linea amarilla doble (col 6): continua salvo en las dos uniones (filas 21-24 y 65-68)
for y = 0, map_h - 1 do
  local gap = (y >= 21 and y <= 24) or (y >= 65 and y <= 68)
  local is_line = gid_name[cell("ground", PAD + 6, y)] == "asphalt_line_v"
  check(is_line == not gap, "linea central en (6," .. y .. "): " .. tostring(is_line))
end
-- las esquinas de las uniones no tienen restos de acera dentro de la interseccion
rect_is("paver", PAD + 61, 21, PAD + 64, 25, "T norte: interseccion limpia")
rect_is("paver", PAD + 61, 65, PAD + 64, 68, "esquina sur-oeste limpia")

-- ---- aceras: 1 tile a cada lado de la calle (filas 20 y 25), cruzadas por el camino de la iglesia ----
for _, y in ipairs({ STREET_Y - 1, STREET_Y + STREET_W }) do
  for x = STREET_X, STREET_X + STREET_LEN - 1 do
    local g = cell("ground", x, y)
    local church_path = (y == STREET_Y - 1) and (x == CHURCH_X + 4 or x == CHURCH_X + 5)
    if church_path then
      check(g == PAVER_A or g == PAVER_B, "el camino de la iglesia debe cruzar la acera norte en (" .. x .. "," .. y .. ")")
    else
      check(g == SIDEWALK_A or g == SIDEWALK_B, "falta la acera en (" .. x .. "," .. y .. ")")
    end
  end
end

-- ---- la iglesia centrada en la calle ----
local ex, ey, ew, eh = CHURCH_X * 16, CHURCH_Y * 16, CHURCH_W * 16, CHURCH_H * 16
local iglesia_foot = by_name.iglesia_footprint
check(iglesia_foot ~= nil, "falta iglesia_footprint")
if iglesia_foot then
  check(iglesia_foot.x == ex and iglesia_foot.w == ew, "iglesia_footprint debe cubrir el ancho de la iglesia")
  check(iglesia_foot.y == ey + 4 * 16 and iglesia_foot.h == 4 * 16, "iglesia_footprint: filas 4-8 de la iglesia")
end
local door_center = ex + 80 -- la puerta (2 tiles) esta en las celdas 4-5: su centro a 5 tiles del borde izquierdo
local street_center = (STREET_X + STREET_LEN / 2) * 16
check(street_center == (PAD + 35) * 16, "el centro de la calle original debe estar en x=(PAD+35)*16 = 4640 px")
check(door_center == street_center, "la iglesia no esta centrada en la calle (puerta " .. door_center .. " px, calle " .. street_center .. " px)")
local puerta = by_name.iglesia_puerta
check(puerta ~= nil and puerta.class == "interactable", "falta la interactable iglesia_puerta")
if puerta then
  check(puerta.x + puerta.w / 2 == door_center, "iglesia_puerta debe estar centrada en la puerta")
  check(puerta.y == ey + eh, "iglesia_puerta debe estar justo bajo la iglesia")
end
local any_b, any_roof, any_lit = false, false, false
for y = CHURCH_Y, CHURCH_Y + CHURCH_H - 1 do
  for x = CHURCH_X, CHURCH_X + CHURCH_W - 1 do
    if cell("buildings", x, y) ~= 0 then any_b = true end
    if cell("roof_iglesia", x, y) ~= 0 then any_roof = true end
    if cell("windows_lit", x, y) ~= 0 then any_lit = true end
  end
end
check(any_b, "la capa buildings no tiene la iglesia en su sitio")
check(any_roof, "la capa roof_iglesia no tiene el techo de la iglesia en su sitio")
check(any_lit, "la capa windows_lit no tiene ventanas encendidas de la iglesia")
-- camino de adoquin de la puerta a la calle (las 2 columnas de la puerta)
for y = CHURCH_Y + 12, STREET_Y - 1 do
  for _, x in ipairs({ CHURCH_X + 4, CHURCH_X + 5 }) do
    local g = cell("ground", x, y)
    check(g == PAVER_A or g == PAVER_B, "falta adoquin del camino en (" .. x .. "," .. y .. ")")
  end
end
-- setos a los lados del camino
check(cell("objects", CHURCH_X + 1, CHURCH_Y + 12) ~= 0 and cell("objects", CHURCH_X + 8, CHURCH_Y + 12) ~= 0, "faltan los setos de la iglesia")

-- ---- techos ----
local roof_rects = {}
for _, o in ipairs(of_class("roof")) do roof_rects[o.props.roof_of or ""] = o end
check(roof_rects.iglesia ~= nil, "falta el rect roof de iglesia")
for lname, props in pairs(layers) do
  if lname:match("^roof_") then
    check(props.above == "true", lname .. " debe tener above=true")
    check(props.roof_of == lname:sub(6), lname .. ": roof_of distinto del nombre")
  end
end

-- ---- spawns ----
local spawn = {}
for _, o in ipairs(of_class("spawn")) do spawn[o.name] = o end
check(spawn.default ~= nil, "falta el spawn default")
if spawn.default then
  check(spawn.default.props.facing == "down", "default debe mirar hacia abajo")
  local dx, dy = spawn.default.x - door_center, spawn.default.y - (ey + eh)
  check(spawn.default.x == 816 + 16 * D and spawn.default.y == 308, "default debe estar en (4640,308)")
  check(dx == 0 and dy >= 0 and dy <= 64, "default debe estar justo delante de la puerta de la iglesia (" .. dx .. "," .. dy .. ")")
end

-- ---- bordes (extremos de la calle) y zonas ----
local edge = {}
for _, o in ipairs(of_class("edge")) do
  edge[o.props.edge or ""] = o
  check(o.props.connects_to ~= nil, "edge " .. tostring(o.props.edge) .. " sin connects_to")
end
for _, id in ipairs({ "calle_principal_oeste", "calle_principal_este", "calle_este_norte", "calle_este_sur", "calle_oeste_sur" }) do
  check(edge[id] ~= nil, "falta el borde " .. id)
  check(spawn["edge_" .. id] ~= nil, "falta el spawn edge_" .. id)
  local sp = spawn["edge_" .. id]
  check(sp == nil or (sp.x > 0 and sp.x < map_w * 16 and sp.y > 0 and sp.y < map_h * 16), "el spawn edge_" .. id .. " debe estar dentro del mapa")
end
check(edge.calle_oeste == nil and edge.calle_este == nil, "los bordes viejos calle_oeste/calle_este ya no existen")
if edge.calle_principal_oeste then
  check(edge.calle_principal_oeste.x + edge.calle_principal_oeste.w == (LASTRE_X1 + 1) * 16, "el borde de la calle principal debe estar en el extremo del lastre")
end
if edge.calle_este_norte then check(edge.calle_este_norte.y == 0 and edge.calle_este_norte.x == (PAD + 5) * 16 and edge.calle_este_norte.w == 4 * 16, "borde norte de la calle de asfalto") end
if edge.calle_oeste_sur then
  local e = edge.calle_oeste_sur
  check(e.x == (PAD + 61) * 16 and e.w == 4 * 16 and e.y + e.h == map_h * 16, "borde sur de la calle de lastre (cols 77-80, fila " .. (map_h - 1) .. ")")
  local sp = spawn.edge_calle_oeste_sur
  check(sp ~= nil and kind_at(sp.x // 16, sp.y // 16) == "lastre", "el spawn edge_calle_oeste_sur debe caer sobre el lastre")
end
if edge.calle_este_sur then check(edge.calle_este_sur.y + edge.calle_este_sur.h == map_h * 16 and edge.calle_este_sur.x == (PAD + 5) * 16, "borde sur de la calle de asfalto") end
local zones = {}
for _, o in ipairs(of_class("zone")) do zones[o.props.zone or ""] = o end
for _, id in ipairs({ "zona1", "iglesia", "parque", "ebais", "monte", "aerogeneradores" }) do check(zones[id] ~= nil, "falta la zona " .. id) end
if zones.parque then
  local z = zones.parque
  check(z.x == PARK_X * 16 and z.y == PARK_Y * 16 and z.w == PARK_W * 16 and z.h == PARK_H * 16, "la zona parque debe cubrir el parque (50x37 tiles desde (10,27))")
  check(z.props.title == "El parque" and z.props.ambience == "pueblo", "la zona parque: titulo 'El parque' y ambience pueblo")
end
if zones.zona1 then check(zones.zona1.w == map_w * 16 and zones.zona1.h == real_h * 16, "la zona zona1 debe cubrir todo el mapa") end

-- ---- el parque (tileset park) ----
local function is_park(g) return g >= PARK_FIRSTGID end
local function park_cells(layer, x0, y0, x1, y1)
  local n = 0
  for y = y0, y1 do for x = x0, x1 do if is_park(cell(layer, x, y)) then n = n + 1 end end end
  return n
end
-- el parque empieza al menos una fila de cesped bajo la acera sur
check(PARK_Y >= STREET_Y + STREET_W + 2, "el parque debe dejar una fila de verde bajo la acera sur")
check(map_h >= PARK_Y + PARK_H + 1 + 4 + 3, "el mapa debe dejar la acera, la calle sur (4) y 3 filas de margen bajo el parque")
-- esqueleto: skate (cols 11-22, filas 39-54), juegos (cols 24-35, filas 43-50), cancha con acera (cols 37-59, filas 52-63)
check(park_cells("ground", PAD + 11, 39, PAD + 22, 54) == 12 * 16, "el skate park debe ser 12x16 tiles del tileset park")
check(park_cells("ground", PAD + 24, 43, PAD + 35, 50) == 12 * 8, "los juegos de ninos deben ser 12x8 tiles de arena")
check(park_cells("ground", PAD + 37, 52, PAD + 59, 63) == 23 * 12, "la cancha (con su acera) debe ser 23x12 tiles del tileset park")
-- equipo: columpios (base solida), tobogan, trepador, aros y arcos en la capa objects (ysort)
for _, p in ipairs({ { 25, 45 }, { 27, 45 }, { 30, 45 }, { 31, 45 }, { 33, 46 }, { 34, 46 }, { 40, 58 }, { 56, 58 }, { 38, 55 }, { 38, 59 }, { 58, 55 }, { 58, 59 } }) do
  check(is_park(cell("objects", PAD + p[1], p[2])), "falta equipo del parque en objects (" .. PAD + p[1] .. "," .. p[2] .. ")")
end
-- los pasos entre los columpios deben ser transitables (la celda del medio no es solida)
check(is_park(cell("objects", PAD + 26, 45)), "la celda central de los columpios debe existir (sin solid)")
-- arboles: zona de arboles (cols 11-25, filas 27-38) con troncos en objects y copas en canopy
local trunks = 0 -- gids 129/131/132 = guanacaste/palm/monte_trunk (ids 128/130/131 + 1)
for y = 27, 38 do for x = PAD + 11, PAD + 25 do local g = cell("objects", x, y); if g == 129 or g == 131 or g == 132 then trunks = trunks + 1 end end end
check(trunks >= 8, "la zona de arboles debe tener arboles (troncos: " .. trunks .. ")")
-- camino de adoquin diagonal: arranca en la acera sur (fila 26) y llega a la esquina NE del skate park
local path_start, path_end = false, false
for x = PARK_X, PARK_X + PARK_W - 1 do
  local g = cell("ground", x, STREET_Y + STREET_W + 1)
  if g == PAVER_A or g == PAVER_B then path_start = true end
end
for y = 39, 42 do local g = cell("ground", PAD + 23, y); if g == PAVER_A or g == PAVER_B then path_end = true end end
check(path_start, "el camino diagonal debe tocar la acera sur (fila 26)")
check(path_end, "el camino diagonal debe llegar al skate park (col 23, filas 39-42)")
-- farolas: cada 50 m = 25 tiles en TODA la calle principal (cols 10 + 25k hasta el fin del lastre), norte (fila 19) y sur (fila 26); luces dusk,night
local lamp_x = {}
for _, o in ipairs(of_class("light")) do
  if o.name:match("^luz_farola_") then
    check(o.props.only == "dusk,night", o.name .. ": las farolas deben encender al atardecer y de noche (only=dusk,night)")
    local side, col = o.name:match("^luz_farola_([ns])_(%d+)$")
    if side then lamp_x[side .. col] = true end
  end
end
local n_lamps = 0
local LAMP = { n = {}, s = {}, skipped = 0, cols = 0 } -- columnas omitidas: las calcula el generador (camino de la iglesia, cafetal, calle oeste, edificios y caminos de las casas)
for _, c in ipairs(Z.LAMP_SKIP_N) do LAMP.n[c] = true end
for _, c in ipairs(Z.LAMP_SKIP_S) do LAMP.s[c] = true end
for col = PAD + 10, LASTRE_X1, 25 do
  LAMP.cols = LAMP.cols + 1
  for _, side in ipairs({ "n", "s" }) do
    local skipped = LAMP[side][col] == true
    if skipped then LAMP.skipped = LAMP.skipped + 1 end
    check((lamp_x[side .. col] == true) == (not skipped), "farola " .. side .. col .. (skipped and " debe omitirse" or " falta"))
    if lamp_x[side .. col] then
      n_lamps = n_lamps + 1
      local y = side == "n" and 19 or 26
      check(cell("objects", col, y) ~= 0, "falta el poste de la farola " .. side .. col)
    end
  end
end
check(n_lamps == LAMP.cols * 2 - LAMP.skipped, "deben ser " .. (LAMP.cols * 2 - LAMP.skipped) .. " farolas de calle (" .. LAMP.cols .. " columnas x 2 lados - " .. LAMP.skipped .. " omitidas), hay " .. n_lamps)
for x in pairs(lamp_x) do
  local col = tonumber(x:sub(2))
  check((col - PAD - 10) % 25 == 0, "farola fuera de la rejilla de 25 tiles: " .. x)
end
for x in pairs(lamp_x) do -- ninguna farola dentro de un edificio / camino de las casas y locales de la calle principal
  local side, col = x:sub(1, 1), tonumber(x:sub(2))
  for _, r in ipairs(Z.PLACE_RANGES[side]) do check(col < r[1] or col > r[2], "la farola " .. x .. " cae dentro de un edificio o camino (cols " .. r[1] .. "-" .. r[2] .. ")") end
end
do -- cables entre las cabezas de las farolas de la calle de lastre: solo hay power_wire en esos tramos
  local wires = 0
  for _, g in ipairs(layers.canopy._cells) do if g ~= 0 and gid_name[g] == "power_wire" then wires = wires + 1 end end
  check(wires == Z.WIRE_CELLS, "power_wire: deben ser " .. Z.WIRE_CELLS .. " celdas de cable, hay " .. wires)
end
do -- emisores de sonido: cada sonido esta registrado en la escena y los de animales de noche respetan la mision del Chequelo
  local scene = read_file("games/quebrada/scenes/zona1.lua")
  local n_vida, perros = 0, nil
  for _, o in ipairs(objects) do
    if o.class == "emitter" then
      local snd = o.props.sound
      check(scene:find('assetId = "' .. tostring(snd) .. '"', 1, true) ~= nil, "emisor " .. tostring(o.name) .. ": el sonido " .. tostring(snd) .. " no esta registrado en scenes/zona1.lua")
      if o.name and o.name:match("^gallinas_") then check(o.props.only == "day", o.name .. ": las gallinas suenan de dia") end
      if o.name and o.name:match("^gallo_") then check(o.props.only == "dawn", o.name .. ": los gallos suenan al amanecer") end
      if o.name == "perros_caliles" then perros = o end
      if o.name and (o.name:match("^gallinas_") or o.name:match("^gallo_") or o.name:match("^perro")) then n_vida = n_vida + 1 end
    end
  end
  check(n_vida >= 7, "faltan emisores de animales (" .. n_vida .. ")")
  check(perros ~= nil and perros.props.only == "night" and perros.props.when == "!mission.chequelo.night_active", "perros_caliles: de noche y apagado durante la mision del Chequelo")
end
do -- placas con el nombre de las casas (hoja vida): la primera celda de cada rotulo esta en su sitio, las siguientes seguidas, y ninguna cae sobre un camino
  local vid = {}
  for tid, body in read_file("games/quebrada/tilesets/vida.tsx"):gmatch('<tile id="(%d+)">(.-)</tile>') do vid[body:match('name="name" value="([^"]*)"')] = tonumber(tid) end
  local n = 0
  for key, at in pairs(Z.PLAQUE_AT) do
    n = n + 1
    local w = 0
    while vid["vida_rotulo_" .. key .. "_" .. w .. "_0"] do w = w + 1 end
    check(w >= 3, "rotulo " .. key .. ": falta en vida.tsx")
    for cx = 0, w - 1 do
      local want = Z.VIDA_FIRSTGID + (vid["vida_rotulo_" .. key .. "_" .. cx .. "_0"] or -1000)
      check(rcell("objects", at[1] + cx, at[2]) == want, "rotulo " .. key .. ": falta la celda " .. cx .. " en (" .. (at[1] + cx) .. "," .. at[2] .. ")")
      for _, side in ipairs({ "n", "s" }) do
        for _, r in ipairs(Z.PLACE_FOOTS[side]) do
          check(not (at[2] == (side == "n" and Z.SIDEWALK_N_Y - 1 or Z.SIDEWALK_S_Y + 1) and at[1] + cx >= r[1] and at[1] + cx <= r[2]) , "rotulo " .. key .. " cae sobre un camino (col " .. (at[1] + cx) .. ")")
        end
      end
    end
  end
  check(n == 10, "deben ser 10 rotulos de casas en el mapa, hay " .. n)
end
local lamps = 0
for _, o in ipairs(of_class("light")) do if o.name:match("^luz_farola_") then lamps = lamps + 1 end end
check(lamps >= LAMP.cols * 2 - LAMP.skipped, "faltan farolas (" .. lamps .. ")")

-- ================================================================ el Chequelo: cafetal, casas, ruta, triggers, emisores
local function gname(layer, x, y) return gid_name[cell(layer, x, y)] end
do -- el potrero norte (cerca de alambre con portón de lastre), las bancas de la calle y los emisores de las vacas
  local P = Z.POTRERO
  local y0, y1 = P.y0 - TOP, P.y1 - TOP
  for _, c in ipairs({ { P.x0, y0 }, { P.x1, y0 }, { P.x0, y1 }, { P.x1, y1 } }) do
    check((gname("objects", c[1], c[2]) or ""):match("^wire_corner") ~= nil, "potrero: falta la esquina de la cerca en (" .. c[1] .. "," .. c[2] .. ")")
  end
  for x = P.x0 + 1, P.x1 - 1 do
    check(gname("objects", x, y0) == "wire_h", "potrero: falta la cerca norte en col " .. x)
    local gap = x == P.gate[1] or x == P.gate[2]
    check(gname("objects", x, y1) == (gap and "fence_gap" or "wire_h"), "potrero: cerca sur / portón en col " .. x)
  end
  for y = y0 + 1, y1 - 1 do check(gname("objects", P.x0, y) == "wire_v" and gname("objects", P.x1, y) == "wire_v", "potrero: falta la cerca lateral en fila " .. y) end
  for y = y1, STREET_Y - 2 do for _, x in ipairs(P.gate) do check(kind_at(x, y) == "lastre", "potrero: el camino del portón debe ser de lastre en (" .. x .. "," .. y .. ")") end end
  for _, x in ipairs({ Z.AB_X + 1, Z.AB_X + 6, Z.BAR_X + 2, Z.BAR_X + 5 }) do check(gname("objects", x, STREET_Y - 2) == "bench", "falta la banca en (" .. x .. ", fila 19)") end
  local cows = 0
  for _, o in ipairs(objects) do if o.class == "emitter" and o.name and (o.name:match("^vacas_") or o.name:match("^caballo_")) then cows = cows + 1; check(o.props.only == "day", o.name .. ": suena de dia") end end
  check(cows == 3, "deben ser 3 emisores del potrero (vacas y caballo), hay " .. cows)
end
local function has_prefix(layer, x, y, prefix) local n = gname(layer, x, y); return n ~= nil and n:sub(1, #prefix) == prefix end
local function point_in(r, px, py) return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h end
local function of_name_prefix(prefix)
  local out = {}
  for _, o in ipairs(objects) do if o.name and o.name:sub(1, #prefix) == prefix then out[#out + 1] = o end end
  return out
end

-- ---- el cafetal: 25 tiles (50 m) de ancho, centrado 50 m antes del fin del adoquin (col 334 - 25 = 309), al norte de la calle ----
local CAF_X0, CAF_X1, CAF_Y0, CAF_Y1, GAP0, GAP1 = Z.CAF_X0, Z.CAF_X1, Z.CAF_Y0 - TOP, Z.CAF_Y1 - TOP, Z.CAF_GAP[1], Z.CAF_GAP[2]
check(CAF_X1 - CAF_X0 + 1 == 25, "el cafetal debe medir 25 tiles = 50 m de ancho")
check(CAF_X0 + (CAF_X1 - CAF_X0) // 2 == EXT_PAVER_X1 - 25, "el cafetal debe estar centrado 25 tiles (50 m) antes del fin del adoquin")
check(CAF_Y1 < STREET_Y - 2, "el cafetal deja una fila de cesped (19) entre su cerca y la acera norte (20)")
for x = CAF_X0 + 1, CAF_X1 - 1 do
  check(has_prefix("objects", x, CAF_Y0, "wire_h"), "falta la cerca norte del cafetal en (" .. x .. "," .. CAF_Y0 .. ")")
  local gap = x == GAP0 or x == GAP1
  check(gap == (gname("objects", x, CAF_Y1) == "fence_gap"), "cerca sur del cafetal: el hueco es solo en cols " .. GAP0 .. "-" .. GAP1 .. " (col " .. x .. ")")
  check(gap or gname("objects", x, CAF_Y1) == "wire_h", "falta la cerca sur del cafetal en col " .. x)
end
for y = CAF_Y0 + 1, CAF_Y1 - 1 do
  check(gname("objects", CAF_X0, y) == "wire_v" and gname("objects", CAF_X1, y) == "wire_v", "falta la cerca lateral del cafetal en fila " .. y)
end
local cafetos = 0
for y = CAF_Y0 + 1, CAF_Y1 - 1 do for x = CAF_X0 + 1, CAF_X1 - 1 do
  local n = gname("objects", x, y)
  if n == "cafeto_a" or n == "cafeto_b" then
    cafetos = cafetos + 1
    check(x ~= GAP0 and x ~= GAP1, "un cafeto bloquea el pasillo en (" .. x .. "," .. y .. ")")
  end
  local g = gname("ground", x, y)
  if x == GAP0 or x == GAP1 then check(g ~= nil and g:match("^lastre_"), "el pasillo del cafetal debe ser lastre en (" .. x .. "," .. y .. ")")
  else check(g == "soil" or g == "soil_terrace" or g == "soil_furrow", "terraza de tierra esperada en (" .. x .. "," .. y .. ")") end
end end
check(cafetos >= 80, "el cafetal debe tener filas de cafetos (" .. cafetos .. ")")
for y = CAF_Y1, STREET_Y - 2 do -- pasillo hasta la acera (fila 20, que el pasillo toca sin cruzar): lastre y sin objetos
  for _, x in ipairs({ GAP0, GAP1 }) do
    check(kind_at(x, y) == "lastre", "el pasillo del cafetal debe llegar a la acera: lastre en (" .. x .. "," .. y .. ")")
    check(y == CAF_Y1 and gname("objects", x, y) == "fence_gap" or cell("objects", x, y) == 0, "obstaculo en el pasillo del cafetal en (" .. x .. "," .. y .. ")")
  end
end
check(zones.cafetal ~= nil and zones.cafetal.props.title == "El cafetal" and zones.cafetal.props.ambience == "monte", "zona cafetal: titulo 'El cafetal' y ambience monte")
if zones.cafetal then
  local z = zones.cafetal
  check(z.x <= CAF_X0 * 16 and z.x + z.w >= (CAF_X1 + 1) * 16 and z.y <= CAF_Y0 * 16 and z.y + z.h >= (CAF_Y1 + 1) * 16, "la zona cafetal debe cubrir el cafetal")
end

-- ---- casas: mama (casa_mama, fondo del lastre, sur) y Chayo (casa_2, 50 m = 25 tiles antes, sur) ----
local MAMA_X0, MAMA_Y0, MAMA_W, MAMA_H = Z.MAMA_AT[1], Z.MAMA_AT[2] - TOP, 8, 6
local CHAYO_X0, CHAYO_Y0, CHAYO_W, CHAYO_H = Z.CHAYO_AT[1], Z.CHAYO_AT[2] - TOP, 6, 5
check((MAMA_X0 + MAMA_W / 2) - (CHAYO_X0 + CHAYO_W / 2) == 25, "la casa de Chayo debe estar 25 tiles (50 m) antes de la de mama, centro a centro")
check(MAMA_X0 + MAMA_W - 1 < LASTRE_X1, "la casa de mama termina antes del fin de la calle (col " .. LASTRE_X1 .. ")")
check(MAMA_Y0 >= STREET_Y + STREET_W + 2, "las casas dejan 2 filas de cesped bajo la calle de lastre")
local function find_obj(name, x, y) -- objeto del TMX con ese nombre en esa posicion (varias casas comparten modelo, by_name solo guarda la ultima)
  for _, o in ipairs(objects) do if o.name == name and o.x == x and (y == nil or o.y == y) then return o end end
end
local function house_checks(name, ox, oy, w, h, open_porch)
  local any_b, any_roof, any_lit = false, false, false
  for y = oy, oy + h - 1 do for x = ox, ox + w - 1 do
    if cell("buildings", x, y) ~= 0 then any_b = true end
    if cell("roof_" .. name, x, y) ~= 0 then any_roof = true end
    if cell("windows_lit", x, y) ~= 0 then any_lit = true end
  end end
  check(any_b, name .. ": la capa buildings no tiene la casa en su sitio")
  check(any_roof, name .. ": la capa roof_" .. name .. " no tiene el techo en su sitio")
  check(any_lit, name .. ": la capa windows_lit no tiene ventanas encendidas")
  local foot = find_obj(name .. "_footprint", ox * 16) -- hay varias casas del mismo modelo: se busca por posicion
  check(foot ~= nil and foot.x == ox * 16 and foot.w == w * 16 and foot.h > 0, name .. "_footprint debe cubrir el ancho de la casa")
  local roof = find_obj("roof_" .. name, ox * 16, oy * 16)
  check(roof ~= nil and roof.class == "roof" and roof.props.roof_of == name and roof.x == ox * 16 and roof.y == oy * 16, "falta el rect roof de " .. name)
  check(layers["roof_" .. name].above == "true" and layers["roof_" .. name].roof_of == name, "roof_" .. name .. ": above y roof_of")
  check(by_name["luz_" .. name .. "_1"] ~= nil and by_name["luz_" .. name .. "_1"].props.only == "dusk,night", "falta la luz de ventana de " .. name)
  for y = oy, oy + h - 1 do for x = ox, ox + w - 1 do
    local m = kind_at(x, y)
    local porch = open_porch and y == oy + 5 and x >= ox + 6 -- celdas abiertas del porche: tablas de madera
    check(porch or m == "grass", name .. " debe estar sobre cesped en (" .. x .. "," .. y .. "): " .. m)
  end end
end
house_checks("casa_mama", MAMA_X0, MAMA_Y0, MAMA_W, MAMA_H, true)
house_checks("casa_2", CHAYO_X0, CHAYO_Y0, CHAYO_W, CHAYO_H)
-- las puertas miran al SUR (lejos de la calle): camino de lastre de 2 tiles por el lado oeste (derecha, +col) con 1 tile de hueco junto a la pared,
-- desde el borde sur de la calle (fila 24) hasta el patio de lastre delante de la puerta
local function footpath_checks(name, ox, oy, w, h, yard_rows, yard_x0)
  local px0 = ox + w + 1 -- primera col del camino
  local yard_y = oy + h
  for y = STREET_Y + STREET_W, yard_y + yard_rows - 1 do
    for _, x in ipairs({ px0, px0 + 1 }) do check(kind_at(x, y) == "lastre", name .. ": falta el camino de lastre en (" .. x .. "," .. y .. ")") end
    if y < yard_y then check(kind_at(px0 - 1, y) == "grass", name .. ": debe quedar 1 tile de cesped entre la pared y el camino en (" .. (px0 - 1) .. "," .. y .. ")") end
  end
  for y = yard_y, yard_y + yard_rows - 1 do
    for x = yard_x0, px0 + 1 do check(kind_at(x, y) == "lastre", name .. ": falta el patio de lastre en (" .. x .. "," .. y .. ")") end
  end
  -- sin objetos en el camino ni en el patio (nada bloquea la puerta)
  for y = STREET_Y + STREET_W, yard_y + yard_rows - 1 do for x = ox + 1, px0 + 1 do
    if kind_at(x, y) == "lastre" then check(cell("objects", x, y) == 0, name .. ": objeto en el camino o patio en (" .. x .. "," .. y .. ")") end
  end end
end
footpath_checks("casa_mama", MAMA_X0, MAMA_Y0, MAMA_W, MAMA_H, 3, MAMA_X0 + 3) -- patio: cols 426-433
footpath_checks("casa_2", CHAYO_X0, CHAYO_Y0, CHAYO_W, CHAYO_H, 3, CHAYO_X0 + 1) -- patio: cols 400-407
-- porche de mama: tablas en sus dos celdas abiertas y surface madera
check(gname("ground", MAMA_X0 + 6, MAMA_Y0 + 5) == "plank_h" and gname("ground", MAMA_X0 + 7, MAMA_Y0 + 5) == "plank_h", "faltan las tablas del porche de mama")
local porche = by_name.porche_mama
check(porche ~= nil and porche.class == "surface" and porche.props.surface == "madera", "falta la surface porche_mama (madera)")
-- guanacaste grande a la izquierda de la casa de mama
check(gname("objects", MAMA_X0 - 3, MAMA_Y0 + 5) == "guanacaste_trunk", "falta el guanacaste junto a la casa de mama")

-- ---- la puerta de mama y su spawn de salida ----
local door = by_name.door_mama
check(door ~= nil and door.class == "door", "falta la puerta door_mama")
local house_tmx = read_file("games/quebrada/maps/house_mama.tmx")
if door then
  check(door.props.target_map == "maps/house_mama.tmx", "door_mama: target_map maps/house_mama.tmx")
  check(door.props.target_spawn == "inside_door" and house_tmx:find('name="inside_door"', 1, true) ~= nil, "door_mama: el spawn inside_door debe existir en house_mama.tmx")
  check(door.props.exit_spawn == "exit_mama" and spawn.exit_mama ~= nil, "door_mama: exit_spawn exit_mama debe existir en zona1")
  check(door.props.locked == "mission.chequelo.failed,!mission.chequelo.next_day", "door_mama: locked")
  check(door.props.locked_line == "Mamá cerró con llave: hoy no quiere ver a nadie. Mañana será otro día.", "door_mama: locked_line")
  check(exists("games/quebrada/" .. door.props.target_map), "door_mama: el mapa destino debe existir")
  check(door.y == (MAMA_Y0 + MAMA_H) * 16 and door.x + door.w / 2 == MAMA_X0 * 16 + 88, "door_mama debe estar justo bajo la puerta dibujada de la casa de mama")
end
if spawn.exit_mama then
  check(spawn.exit_mama.props.facing == "down", "exit_mama mira hacia abajo")
  check(kind_at(spawn.exit_mama.x // 16, spawn.exit_mama.y // 16) == "lastre", "exit_mama debe caer en el patio de lastre")
end
do -- la puerta de la casa de Abuela Paula y Abuelo Pepe, su spawn de salida, su escena y sus dialogos
  local d = by_name.door_paula
  check(d ~= nil and d.class == "door", "falta la puerta door_paula")
  local ptmx = read_file("games/quebrada/maps/house_paula.tmx")
  if d then
    check(d.props.target_map == "maps/house_paula.tmx" and exists("games/quebrada/" .. d.props.target_map), "door_paula: target_map maps/house_paula.tmx (debe existir)")
    check(d.props.target_spawn == "inside_door" and ptmx:find('name="inside_door"', 1, true) ~= nil, "door_paula: el spawn inside_door debe existir en house_paula.tmx")
    check(d.props.exit_spawn == "exit_paula" and spawn.exit_paula ~= nil, "door_paula: exit_spawn exit_paula debe existir en zona1")
    check(d.y == (Z.PAULA_Y - TOP + 6) * 16 and d.x + d.w / 2 == Z.PAULA_X * 16 + 64, "door_paula debe estar justo bajo la puerta dibujada de la casa de Paula")
    check(d.props.locked == nil, "door_paula: siempre abierta")
  end
  if spawn.exit_paula then
    check(spawn.exit_paula.props.facing == "down", "exit_paula mira hacia abajo")
    check(kind_at(spawn.exit_paula.x // 16, spawn.exit_paula.y // 16) == "lastre", "exit_paula debe caer en el camino de lastre")
  end
  local ps = read_file("games/quebrada/scripts/house_paula_scene.lua")
  check(ps:find('map = "maps/house_paula.tmx"', 1, true) ~= nil and ps:find('["maps/zona1.tmx"] = "scenes/zona1.lua"', 1, true) ~= nil, "house_paula_scene.lua: su mapa y la vuelta a zona1")
  check(read_file("games/quebrada/scripts/zona1_scene.lua"):find('["maps/house_paula.tmx"] = "scenes/house_paula.lua"', 1, true) ~= nil, "zona1_scene.lua debe conocer la escena de la casa de Paula")
  check(exists("games/quebrada/scenes/house_paula.lua") and exists("games/quebrada/scripts/house_paula_player.lua"), "faltan scenes/house_paula.lua o scripts/house_paula_player.lua")
  local dl = read_file("games/quebrada/scripts/dialogues.lua")
  check(dl:find("abuela_paula = {", 1, true) ~= nil and dl:find("abuelo_pepe = {", 1, true) ~= nil, "dialogues.lua: faltan abuela_paula / abuelo_pepe")
end
-- la escena de la casa vuelve a zona1 (@return) y zona1_scene la conoce
local hs = read_file("games/quebrada/scripts/house_scene.lua")
check(hs:find('["maps/zona1.tmx"] = "scenes/zona1.lua"', 1, true) ~= nil, "house_scene.lua debe conocer maps/zona1.tmx")
local zs = read_file("games/quebrada/scripts/zona1_scene.lua")
check(zs:find('map = "maps/zona1.tmx"', 1, true) ~= nil, "zona1_scene.lua debe cargar maps/zona1.tmx")

-- ---- la puerta abierta de Chayo ----
local pa = by_name.puerta_abierta
check(pa ~= nil and pa.class == "interactable" and pa.props.only == "night" and pa.props.line == "La puerta está abierta. Adentro no se oye nada.", "puerta_abierta: interactable de noche")
if pa then check(pa.x + pa.w / 2 == CHAYO_X0 * 16 + 48 and pa.y == (CHAYO_Y0 + CHAYO_H) * 16, "puerta_abierta debe estar bajo la puerta de casa_2") end

-- ---- emisores ----
local rc, cp = by_name.rumor_cafetal, by_name.crujido_puerta
check(rc ~= nil and rc.class == "emitter" and rc.props.sound == "leaves_rustle" and rc.props.loop == "true" and rc.props.only == "night" and rc.props.when == "mission.chequelo.night_active", "emisor rumor_cafetal")
check(cp ~= nil and cp.class == "emitter" and cp.props.sound == "door_creak_far" and cp.props.interval == "9" and cp.props.only == "night" and cp.props.when == "mission.chequelo.night_active", "emisor crujido_puerta")
if rc then check(rc.x >= CAF_X0 * 16 and rc.x <= (CAF_X1 + 1) * 16 and rc.y >= CAF_Y0 * 16 and rc.y <= (CAF_Y1 + 1) * 16, "rumor_cafetal dentro del cafetal") end
if cp then check(math.abs(cp.x - (CHAYO_X0 * 16 + 48)) <= 16 and cp.y >= (CHAYO_Y0 + CHAYO_H - 1) * 16 and cp.y <= (CHAYO_Y0 + CHAYO_H) * 16, "crujido_puerta en la puerta de casa_2") end

-- ---- la ruta (route_00..): puerta de la iglesia -> calle -> camino de mama -> puerta de mama ----
local route = {}
for i = 0, 99 do
  local o = by_name[string.format("route_%02d", i)]
  if not o then break end
  check(o.class == "route", "route_" .. i .. " debe tener class route")
  route[#route + 1] = { o.x, o.y }
end
check(#route >= 5, "la ruta debe tener al menos 5 puntos (" .. #route .. ")")
local function route_len()
  local d = 0
  for i = 2, #route do d = d + math.abs(route[i][1] - route[i - 1][1]) + math.abs(route[i][2] - route[i - 1][2]) end
  return d
end
local function point_at(d)
  local left = math.max(0, d)
  for i = 2, #route do
    local x0, y0, x1, y1 = route[i - 1][1], route[i - 1][2], route[i][1], route[i][2]
    local len = math.abs(x1 - x0) + math.abs(y1 - y0)
    if left <= len then
      local function sign(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
      return x0 + sign(x1 - x0) * left, y0 + sign(y1 - y0) * left
    end
    left = left - len
  end
  return route[#route][1], route[#route][2]
end
local len = route_len()
local walk_px = tonumber(tmx:match('<property name="walk_px"[^>]-value="(%d+)"'))
check(walk_px == len, "walk_px (" .. tostring(walk_px) .. ") debe ser igual a la longitud de la ruta (" .. len .. ")")
check(tonumber(tmx:match('<property name="walk_speed"[^>]-value="(%d+)"')) == 60, "walk_speed 60")
-- NOTA: la ruta mide ~6676 px (~111 s andando, ~67 s corriendo): consecuencia conocida del layout del usuario; el objetivo antiguo de ~60 s queda superado
check(len > 3600, "la ruta no es mas corta que el viejo objetivo de 3600 px (" .. len .. ")")
check(route[1][1] == 816 + 16 * D and route[1][2] >= 288 and route[1][2] <= 320, "la ruta empieza en la puerta de la iglesia (4640, ~300)")
check(route[2][1] == 816 + 16 * D and route[2][2] == (STREET_Y + STREET_W // 2) * 16, "la ruta baja por el camino de la iglesia hasta el centro de la calle (y=368)")
check(route[3][2] == route[2][2] and route[3][1] > route[2][1], "la ruta sigue la calle hacia el este (x creciente)")

local triggers_by_id, trigger_objs = {}, {}
for _, o in ipairs(of_class("trigger")) do
  local id = o.props.trigger
  check(id ~= nil and id ~= "", "trigger sin propiedad 'trigger': " .. tostring(o.name))
  triggers_by_id[id] = triggers_by_id[id] or {}
  table.insert(triggers_by_id[id], o)
  trigger_objs[#trigger_objs + 1] = o
  check(o.props.mission == "chequelo", "trigger " .. tostring(id) .. ": mission=chequelo")
  check(o.props.requires ~= nil and o.props.requires:find("mission.chequelo.", 1, true) ~= nil, "trigger " .. tostring(id) .. ": requires debe contener mission.chequelo.<estado>")
  check(o.w and o.h and o.w > 0 and o.h > 0, "trigger " .. tostring(id) .. " debe ser un rect")
end
for _, id in ipairs({ "walk_start", "road", "light_appears", "detour_cafetal", "detour_door", "house_arrival" }) do
  check(triggers_by_id[id] ~= nil, "falta el trigger " .. id)
end
local function covered_by(list, px, py)
  for _, r in ipairs(list) do if point_in(r, px, py) then return true end end
  return false
end
local roads = triggers_by_id.road or {}
check(#roads >= #route - 1, "road: al menos un rect por tramo de la ruta (" .. #roads .. " rects, " .. (#route - 1) .. " tramos)")
for i = 2, #route do -- la ruta entera cubierta por la union de los rects road
  local x0, y0, x1, y1 = route[i - 1][1], route[i - 1][2], route[i][1], route[i][2]
  local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
  local stepx = x1 == x0 and 0 or (x1 > x0 and 1 or -1)
  local stepy = y1 == y0 and 0 or (y1 > y0 and 1 or -1)
  local bad
  for k = 0, n, 4 do
    if not covered_by(roads, x0 + stepx * k, y0 + stepy * k) then bad = { x0 + stepx * k, y0 + stepy * k }; break end
  end
  check(bad == nil, "road no cubre la ruta (tramo " .. (i - 1) .. ") cerca de (" .. tostring(bad and bad[1]) .. "," .. tostring(bad and bad[2]) .. ")")
end
-- los rects road cubren la calle de la puerta de la iglesia a la puerta de mama (filas 21-24 en el centro, 36 px de semiancho)
for x = 816 + 16 * D, LASTRE_X1 * 16, 16 do check(covered_by(roads, x, 345) and covered_by(roads, x, 391), "road debe cubrir el ancho de la calle en x=" .. x) end
-- walk_start alrededor del spawn default; light_appears en la mitad de la ruta
local ws_rect = triggers_by_id.walk_start and triggers_by_id.walk_start[1]
if ws_rect and spawn.default then
  check(point_in(ws_rect, spawn.default.x, spawn.default.y), "default debe estar dentro de walk_start")
  check(ws_rect.props.requires == "mission.chequelo.accepted" and ws_rect.props.sets == "chequelo.walk_started", "walk_start: requires/sets")
end
local la = triggers_by_id.light_appears and triggers_by_id.light_appears[1]
if la then
  local mx, my = point_at(len / 2)
  check(point_in(la, mx, my), "light_appears debe contener pointAt(len/2) = (" .. mx .. "," .. my .. ")")
  check(la.h >= 64 and la.y <= STREET_Y * 16 and la.y + la.h >= (STREET_Y + STREET_W) * 16, "light_appears debe cruzar todas las filas de la calle")
  check(la.props.line == "Una luz se enciende sobre el camino..." and la.props.sets == "chequelo.light_appears", "light_appears: line/sets")
end
-- los desvios no se solapan con los rects road (se pisan solo al salirse del camino)
local function overlaps_any(r, list)
  for _, q in ipairs(list) do if overlap(r, q) then return true end end
  return false
end
for _, id in ipairs({ "detour_cafetal", "detour_door" }) do
  for _, r in ipairs(triggers_by_id[id] or {}) do check(not overlaps_any(r, roads), id .. " no debe solaparse con los rects road") end
end
local dc = triggers_by_id.detour_cafetal and triggers_by_id.detour_cafetal[1]
if dc then
  check(dc.x <= GAP0 * 16 and dc.x + dc.w >= (GAP1 + 1) * 16, "detour_cafetal cubre el hueco de la cerca (cols 308-309)")
  check(dc.y <= CAF_Y1 * 16 and dc.y + dc.h > CAF_Y1 * 16, "detour_cafetal toca la fila del hueco")
end
local dd = triggers_by_id.detour_door and triggers_by_id.detour_door[1]
if dd then
  check(point_in(dd, CHAYO_X0 * 16 + 48, (CHAYO_Y0 + CHAYO_H) * 16 + 8), "detour_door debe cubrir el patio delante de la puerta de casa_2")
  check(overlap(dd, pa or { x = 0, y = 0, w = 0, h = 0 }), "detour_door toca la puerta abierta")
end
local ha = triggers_by_id.house_arrival and triggers_by_id.house_arrival[1]
if ha and door then
  check(overlap(ha, door), "house_arrival debe solaparse con door_mama")
  check(ha.props.sets == "chequelo.arrived", "house_arrival: sets chequelo.arrived")
end
check(door ~= nil and route[#route][1] >= door.x and route[#route][1] <= door.x + door.w and route[#route][2] >= door.y and route[#route][2] <= door.y + door.h, "la ruta termina en la puerta de mama")
-- los rects de trigger quedan sobre suelo caminable (ni cerca ni cafeto ni pared bajo su centro)
for _, o in ipairs(trigger_objs) do
  local cx, cy = (o.x + o.w / 2) // 16, (o.y + o.h / 2) // 16
  local n = gname("objects", cx, cy)
  check(n == nil or not (n:match("^wire_") or n:match("^cafeto_") or n:match("_trunk$")), "el centro del trigger " .. o.props.trigger .. " esta sobre un objeto solido: " .. tostring(n))
end

-- ================================================================ la escuela y la casa de Olguita (ESTE de la calle de asfalto = izquierda de la pantalla)
-- Lotes de PLOT_W = 14 (cols 5-18; col 19 verde, col 20 acera lejana). Olguita: filas 27-34 (a ras con el tope del parque). Escuela: filas 36-63 (28 = 3/4 del parque).
local PLOT_X0, PLOT_X1 = 5 + D, 18 + D
local OLG_Y0, OLG_Y1, ESC_Y0, ESC_Y1 = 27, 34, 36, 63
check(ESC_Y1 - ESC_Y0 + 1 == 28 and ESC_Y1 == PARK_Y + PARK_H - 1, "la escuela mide 28 filas y termina a ras del final del parque (fila 63)")
check(OLG_Y0 == PARK_Y and OLG_Y1 - OLG_Y0 + 1 == 8 and ESC_Y0 - OLG_Y1 == 2, "Olguita empieza a ras del parque (fila 27), mide 8 y deja 1 fila de hueco antes de la escuela")
check(PLOT_X1 == PAD + 4 - 2, "los lotes terminan 1 tile de cesped antes de la acera lejana (col 19)")
for y = ESC_Y0 - 1, ESC_Y1 do -- el cesped (col 19) entre los lotes y la acera lejana
  local gate_apron = (y == 46 or y == 47) or (y == 32 or y == 33)
  check(gate_apron or kind_at(PLOT_X1 + 1, y) == "grass", "col 19 debe ser cesped salvo las entradas (fila " .. y .. ")")
end
-- la hoja school.tsx: tilecount y reglas basicas (el detalle esta en tests/school_check.lua)
local stsx = read_file("games/quebrada/tilesets/school.tsx")
local s_name, s_solid = {}, {}
for tid, body in stsx:gmatch('<tile id="(%d+)">(.-)</tile>') do
  s_name[SCHOOL_FIRSTGID + tonumber(tid)] = body:match('name="name" value="([^"]*)"')
  s_solid[SCHOOL_FIRSTGID + tonumber(tid)] = body:find('name="solid"', 1, true) ~= nil
end
local function sname(layer, x, y) return s_name[cell(layer, x, y)] end
-- cerca de la escuela: pilares en las 4 esquinas y a los lados de la entrada (filas 45 y 48), muro bajo + malla en el resto, entrada de 2 tiles en la col 18 filas 46-47
for _, c in ipairs({ { PLOT_X0, ESC_Y0 }, { PLOT_X1, ESC_Y0 }, { PLOT_X0, ESC_Y1 }, { PLOT_X1, ESC_Y1 }, { PLOT_X1, 45 }, { PLOT_X1, 48 } }) do
  check(sname("objects", c[1], c[2]) == "escuela_pilar", "falta el pilar de la escuela en (" .. c[1] .. "," .. c[2] .. ")")
end
for x = PLOT_X0 + 1, PLOT_X1 - 1 do
  check(sname("objects", x, ESC_Y0) == "escuela_cerca_h" and sname("objects", x, ESC_Y1) == "escuela_cerca_h", "falta la cerca horizontal de la escuela en col " .. x)
end
for y = ESC_Y0 + 1, ESC_Y1 - 1 do
  check(sname("objects", PLOT_X0, y) == "escuela_cerca_v", "falta la cerca oeste de la escuela en fila " .. y)
  local gate, post = (y == 46 or y == 47), (y == 45 or y == 48)
  check(gate and cell("objects", PLOT_X1, y) == 0 or (post and sname("objects", PLOT_X1, y) == "escuela_pilar") or sname("objects", PLOT_X1, y) == "escuela_cerca_v", "cerca este de la escuela / entrada de 2 tiles (col 18, fila " .. y .. ")")
end
-- patio, pasillo y entrada de concreto
for _, p in ipairs({ { 11 + D, 46 }, { 7 + D, 44 }, { 17 + D, 50 }, { 17 + D, 40 }, { 17 + D, 54 }, { 10 + D, 57 }, { PLOT_X1, 46 }, { PLOT_X1 + 1, 47 } }) do
  local n = gid_name[cell("ground", p[1], p[2])]
  check(s_name[cell("ground", p[1], p[2])] ~= nil and s_name[cell("ground", p[1], p[2])]:match("^escuela_patio") ~= nil, "el patio de la escuela debe ser concreto (escuela_patio_*) en (" .. p[1] .. "," .. p[2] .. ")")
end
-- los bloques de aulas (10x6) en (6,38) y (6,51), mirando al sur; techos, ventanas encendidas, huella y luz
local function school_block(name, ox, oy)
  local any_b, any_roof, any_lit = false, false, false
  for y = oy, oy + 5 do for x = ox, ox + 9 do
    if cell("buildings", x, y) ~= 0 then any_b = true end
    if cell("roof_" .. name, x, y) ~= 0 then any_roof = true end
    if cell("windows_lit", x, y) ~= 0 then any_lit = true end
    check(kind_at(x, y) == "grass", name .. " debe estar sobre cesped en (" .. x .. "," .. y .. ")")
  end end
  check(any_b and any_roof and any_lit, name .. ": buildings, techo y ventanas encendidas")
  check(cell("roof_" .. name, ox, oy + 4) == 0 and cell("roof_" .. name, ox, oy + 3) ~= 0, name .. ": el techo ocupa las filas 0-3")
  local foot = by_name[name .. "_footprint"]
  check(foot ~= nil and foot.x == ox * 16 and foot.w == 160 and foot.y == (oy + 1) * 16 and foot.h == 4 * 16, name .. "_footprint: filas 1-4 del bloque")
  local roof = by_name["roof_" .. name]
  check(roof ~= nil and roof.class == "roof" and roof.props.roof_of == name and roof.x == ox * 16 and roof.y == oy * 16, "falta el rect roof de " .. name)
  check(layers["roof_" .. name].above == "true" and layers["roof_" .. name].roof_of == name, "roof_" .. name .. ": above y roof_of")
  local nl = 0
  for _, o in ipairs(of_class("light")) do if o.name:match("^luz_" .. name .. "_%d+$") then nl = nl + 1; check(o.props.only == "dusk,night", o.name .. ": only=dusk,night") end end
  check(nl == 4, name .. ": 4 ventanas con luz (" .. nl .. ")")
  for i = 1, 2 do
    local d = by_name[name .. "_puerta_" .. i]
    check(d ~= nil and d.class == "interactable" and d.props.line == "La escuela está cerrada.", name .. "_puerta_" .. i .. ": interactable 'La escuela está cerrada.'")
    if d then check(d.y == (oy + 5) * 16 and d.w == 32 and d.h == 16, name .. "_puerta_" .. i .. " sobre la fila del corredor") end
  end
  -- el corredor (fila 5 del bloque) es caminable: sus celdas no son solidas; el cuerpo (filas 4) si
  for x = ox, ox + 9 do
    local g = cell("buildings", x, oy + 5)
    check(g == 0 or not s_solid[g], name .. ": el corredor debe ser caminable en (" .. x .. "," .. oy + 5 .. ")")
    check(s_solid[cell("buildings", x, oy + 4)] == true, name .. ": la pared debe ser solida en (" .. x .. "," .. oy + 4 .. ")")
  end
end
school_block("escuela_aulas_a", 6 + D, 38)
school_block("escuela_aulas_b", 6 + D, 51)
Z.FLAG_X, Z.FLAG_Y = Z.ESC_FLAG_AT[1], Z.ESC_FLAG_AT[2] - TOP -- origen (arriba) del asta 1x3: bandera en las dos filas de arriba, base solida en la tercera
check(sname("objects", Z.FLAG_X, Z.FLAG_Y + 2) == "escuela_asta_0_2" and sname("canopy", Z.FLAG_X, Z.FLAG_Y) == "escuela_asta_0_0" and sname("canopy", Z.FLAG_X, Z.FLAG_Y + 1) == "escuela_asta_0_1", "falta el asta de la bandera (1x3) en (" .. Z.FLAG_X .. ", " .. Z.FLAG_Y .. "-" .. (Z.FLAG_Y + 2) .. ")")
check(sname("canopy", 16 + D, 44) == "escuela_rotulo_0_0" and sname("objects", 17 + D, 45) == "escuela_rotulo_1_1", "falta el rotulo de la escuela (2x2) en (16 + D, 44)")
check(zones.escuela ~= nil and zones.escuela.props.title == "La escuela" and zones.escuela.props.ambience == "pueblo", "zona escuela: titulo 'La escuela' y ambience pueblo")
if zones.escuela then
  local z = zones.escuela
  check(z.x <= PLOT_X0 * 16 and z.x + z.w >= (PLOT_X1 + 1) * 16 and z.y <= ESC_Y0 * 16 and z.y + z.h >= (ESC_Y1 + 1) * 16, "la zona escuela debe cubrir el lote")
end
-- Casa de Olguita: casa_3 en (8,28) (6x5), setos de lote, entrada de 2 tiles en col 18 filas 32-33, camino de lastre hasta la puerta (sur)
house_checks("casa_3", 8 + D, 28, 6, 5)
for _, p in ipairs({ { PLOT_X0, OLG_Y0 }, { PLOT_X1, OLG_Y0 }, { PLOT_X0, OLG_Y1 }, { PLOT_X1, OLG_Y1 }, { 12 + D, OLG_Y0 }, { 12 + D, OLG_Y1 }, { PLOT_X0, 30 }, { PLOT_X1, 30 } }) do
  check(gname("objects", p[1], p[2]) == "hedge", "falta el seto del lote de Olguita en (" .. p[1] .. "," .. p[2] .. ")")
end
for _, y in ipairs({ 32, 33 }) do
  check(cell("objects", PLOT_X1, y) == 0, "la entrada de Olguita (col 18, fila " .. y .. ") debe estar libre")
  for x = 14 + D, PLOT_X1 + 1 do check(kind_at(x, y) == "lastre", "camino de lastre de Olguita en (" .. x .. "," .. y .. ")") end
end
for x = 10 + D, 13 + D do check(kind_at(x, 33) == "lastre", "camino de Olguita frente a la casa en (" .. x .. ",33)") end
local op = by_name.casa_olguita_puerta
check(op ~= nil and op.class == "interactable" and op.props.line == "Casa de Olguita. No hay nadie.", "falta casa_olguita_puerta")
if op then check(op.x + op.w / 2 == (8 + D) * 16 + 48 and op.y == (28 + 5) * 16, "casa_olguita_puerta debe estar bajo la puerta de casa_3") end
check(zones.casa_olguita ~= nil and zones.casa_olguita.props.title == "Casa de Olguita" and zones.casa_olguita.props.ambience == "pueblo", "zona casa_olguita: titulo 'Casa de Olguita'")
if zones.casa_olguita and zones.escuela then check(not overlap(zones.casa_olguita, zones.escuela), "las zonas de Olguita y la escuela no se solapan") end


-- ================================================================ el Ebais (lote 21x21 al SUR de la calle sur) y la calle de lastre que continua la calle oeste
-- Lote: cols 55-75, filas 70-90 (una fila de verde, la 69, bajo la calle sur; un tile de cesped, la col 76, antes de la calle de lastre). Cerca = la de la escuela (muro bajo + malla),
-- puerta de 2 tiles al NORTE (cols 57-58, fila 70). Edificio ebais_edificio (12x7) en (60,72): paredes filas 75-76, porche filas 77-78. Camino de concreto de 2 de ancho por el lado este (izquierda).
local WEST_X, SOUTH_Y1 = PAD + 61, 68
local EB_X0, EB_X1, EB_Y0, EB_Y1 = 55 + D, 75 + D, 70, 90
local EB_GATE0, EB_GATE1 = 57 + D, 58 + D
local EB_AT_X, EB_AT_Y = 60 + D, 72
check(EB_X1 - EB_X0 + 1 == 21 and EB_Y1 - EB_Y0 + 1 == 21, "el lote del Ebais mide 21x21 tiles")
check(EB_X1 == WEST_X - 2 and EB_Y0 == SOUTH_Y1 + 2, "el lote termina 1 tile de cesped antes de la calle de lastre y empieza 1 fila de verde bajo la calle sur")
check(map_h >= EB_Y1 + 1 + 3, "el mapa deja >= 3 filas de margen bajo el lote del Ebais")
-- la calle de lastre: continuacion de la calle oeste (cols 77-80), filas 69..ultima, sin aceras, rodadas verticales, junta limpia con el adoquin (filas 68|69)
rect_is("lastre", WEST_X, SOUTH_Y1 + 1, WEST_X + 3, map_h - 1, "calle de lastre al sur de la calle sur (cols 77-80)")
rect_is("paver", WEST_X, SOUTH_Y1, WEST_X + 3, SOUTH_Y1, "junta con el adoquin de la calle sur (fila 68)")
rect_is("grass", WEST_X - 1, SOUTH_Y1 + 1, WEST_X - 1, map_h - 1, "sin acera al oeste (izquierda) de la calle de lastre (col 76)")
rect_is("grass", WEST_X + 4, SOUTH_Y1 + 1, WEST_X + 4, map_h - 1, "sin acera al este (derecha) de la calle de lastre (col 81)")
do
  local ruts = 0
  for y = SOUTH_Y1 + 1, map_h - 1 do
    for x = WEST_X, WEST_X + 3 do check(gid_surface[cell("ground", x, y)] == "lastre", "la calle de lastre debe tener surface=lastre en (" .. x .. "," .. y .. ")") end
    if gid_name[cell("ground", WEST_X + 1, y)] == "lastre_ruts_v" then ruts = ruts + 1 end
  end
  check(ruts > 12, "la calle de lastre sur debe tener rodadas verticales (" .. ruts .. ")")
end
-- hoja ebais.tsx: nombres y solidez
local etsx = read_file("games/quebrada/tilesets/ebais.tsx")
local e_name, e_solid, e_layer = {}, {}, {}
for tid, body in etsx:gmatch('<tile id="(%d+)">(.-)</tile>') do
  local g = EBAIS_FIRSTGID + tonumber(tid)
  e_name[g] = body:match('name="name" value="([^"]*)"')
  e_solid[g] = body:find('name="solid"', 1, true) ~= nil
  e_layer[g] = body:match('name="layer" value="([^"]*)"')
end
local function ename(layer, x, y) return e_name[cell(layer, x, y)] end
-- cerca: pilares (esquinas y postes de la puerta), muro bajo + malla; puerta de 2 tiles en el norte
for _, c in ipairs({ { EB_X0, EB_Y0 }, { EB_X1, EB_Y0 }, { EB_X0, EB_Y1 }, { EB_X1, EB_Y1 }, { EB_GATE0 - 1, EB_Y0 }, { EB_GATE1 + 1, EB_Y0 } }) do
  check(sname("objects", c[1], c[2]) == "escuela_pilar", "falta el pilar del Ebais en (" .. c[1] .. "," .. c[2] .. ")")
end
for x = EB_X0 + 1, EB_X1 - 1 do
  local gate, post = (x >= EB_GATE0 and x <= EB_GATE1), (x == EB_GATE0 - 1 or x == EB_GATE1 + 1)
  check((gate and cell("objects", x, EB_Y0) == 0) or (post and sname("objects", x, EB_Y0) == "escuela_pilar") or sname("objects", x, EB_Y0) == "escuela_cerca_h", "cerca norte del Ebais / puerta de 2 tiles (col " .. x .. ")")
  check(sname("objects", x, EB_Y1) == "escuela_cerca_h", "falta la cerca sur del Ebais en col " .. x)
end
for y = EB_Y0 + 1, EB_Y1 - 1 do
  check(sname("objects", EB_X0, y) == "escuela_cerca_v" and sname("objects", EB_X1, y) == "escuela_cerca_v", "falta la cerca lateral del Ebais en fila " .. y)
end
-- entrada (verde fila 69), camino de 2 de ancho por el lado este (izquierda) y patio: concreto del tileset ebais, sin objetos
for y = EB_Y0 - 1, EB_AT_Y + 6 do
  for x = EB_GATE0, EB_GATE1 do
    local n = ename("ground", x, y)
    check(n ~= nil and n:match("^ebais_piso") ~= nil, "el camino del Ebais debe ser concreto (ebais_piso_*) en (" .. x .. "," .. y .. ")")
    check(cell("objects", x, y) == 0, "objeto en el camino del Ebais en (" .. x .. "," .. y .. ")")
  end
end
for _, p in ipairs({ { 66 + D, 80 }, { 70 + D, 82 }, { 74 + D, 79 } }) do
  local n = ename("ground", p[1], p[2])
  check(n ~= nil and n:match("^ebais_") ~= nil, "el patio / parqueo del Ebais debe ser concreto en (" .. p[1] .. "," .. p[2] .. ")")
end
-- edificio (12x7): paredes solidas (filas 75-76), porche abierto (filas 77-78, cols 62-69), techo above y nunca solid, ventanas encendidas, huella, luces, rect roof
do
  local name, ox, oy = "ebais_edificio", EB_AT_X, EB_AT_Y
  local any_b, any_roof, any_lit = false, false, false
  for y = oy, oy + 6 do for x = ox, ox + 11 do
    if cell("buildings", x, y) ~= 0 then any_b = true end
    if cell("roof_" .. name, x, y) ~= 0 then any_roof = true; check(e_layer[cell("roof_" .. name, x, y)] == "above" and not e_solid[cell("roof_" .. name, x, y)], name .. ": el techo es above y no solid en (" .. x .. "," .. y .. ")") end
    if cell("windows_lit", x, y) ~= 0 then any_lit = true end
    check(kind_at(x, y) == "grass", name .. " debe estar sobre cesped en (" .. x .. "," .. y .. ")")
  end end
  check(any_b and any_roof and any_lit, name .. ": buildings, techo y ventanas encendidas")
  for x = ox, ox + 11 do
    for _, y in ipairs({ oy + 3, oy + 4 }) do check(e_solid[cell("buildings", x, y)] == true, name .. ": la pared debe ser solida en (" .. x .. "," .. y .. ")") end
  end
  for x = ox + 2, ox + 9 do
    for _, y in ipairs({ oy + 5, oy + 6 }) do
      local g = cell("buildings", x, y)
      check(g ~= 0 and not e_solid[g], name .. ": el porche debe ser caminable en (" .. x .. "," .. y .. ")")
    end
  end
  local foot = by_name[name .. "_footprint"]
  check(foot ~= nil and foot.x == ox * 16 and foot.w == 12 * 16 and foot.y == (oy + 1) * 16 and foot.h == 4 * 16, name .. "_footprint: filas 1-4 del edificio")
  local roof = by_name["roof_" .. name]
  check(roof ~= nil and roof.class == "roof" and roof.props.roof_of == name and roof.x == ox * 16 and roof.y == oy * 16 and roof.w == 12 * 16 and roof.h == 7 * 16, "falta el rect roof de " .. name)
  check(layers["roof_" .. name].above == "true" and layers["roof_" .. name].roof_of == name, "roof_" .. name .. ": above y roof_of")
  local nl = 0
  for _, o in ipairs(of_class("light")) do if o.name:match("^luz_" .. name .. "_%d+$") then nl = nl + 1; check(o.props.only == "dusk,night", o.name .. ": only=dusk,night") end end
  check(nl == 4, name .. ": 4 ventanas con luz (" .. nl .. ")")
  check(by_name.luz_ebais_puerta ~= nil and by_name.luz_ebais_puerta.props.only == "dusk,night", "falta la luz del porche del Ebais")
  local door = by_name.ebais_puerta
  check(door ~= nil and door.class == "interactable" and door.props.line == "El Ebais está cerrado.", "falta la interactable ebais_puerta ('El Ebais está cerrado.')")
  if door then check(door.x + door.w / 2 == ox * 16 + 96 and door.y == (oy + 5) * 16 and door.w == 32 and door.h == 16, "ebais_puerta debe estar delante de la puerta de vidrio (porche, fila " .. (oy + 5) .. ")") end
end
check(ename("objects", EB_GATE1 + 2, EB_Y0 - 1) == "ebais_rotulo_0_0" and ename("objects", EB_GATE1 + 3, EB_Y0 - 1) == "ebais_rotulo_1_0", "falta el rotulo EBAIS (2x1) junto a la puerta")
do
  local benches, pots, bins, trunks = 0, 0, 0, 0
  for y = EB_Y0, EB_Y1 do for x = EB_X0, EB_X1 do
    local n = ename("objects", x, y)
    if n == "ebais_banca" then benches = benches + 1 elseif n == "ebais_maceta" then pots = pots + 1 elseif n == "ebais_basurero" then bins = bins + 1 end
    local t = gname("objects", x, y)
    if t and t:match("_trunk$") or t == "platano_stem" then trunks = trunks + 1 end
  end end
  check(benches >= 4 and pots >= 2 and bins >= 1 and trunks >= 3, "el Ebais debe tener bancas azules, macetas, un basurero y arboles (" .. benches .. "/" .. pots .. "/" .. bins .. "/" .. trunks .. ")")
end
check(zones.ebais ~= nil and zones.ebais.props.title == "El Ebais" and zones.ebais.props.ambience == "pueblo", "zona ebais: titulo 'El Ebais' y ambience pueblo")
if zones.ebais then
  local z = zones.ebais
  check(z.x <= EB_X0 * 16 and z.x + z.w >= (EB_X1 + 1) * 16 and z.y <= EB_Y0 * 16 and z.y + z.h >= (EB_Y1 + 1) * 16, "la zona ebais debe cubrir el lote")
  if zones.escuela then check(not overlap(z, zones.escuela), "las zonas del Ebais y la escuela no se solapan") end
end

-- ================================================================ el monte de hule y nispero, la carretera de asfalto y los aerogeneradores
-- Real: a 10 km al ESTE de la iglesia; simplificado a 500 m = 250 tiles (MONTE_DIST_M = 500). Zona `monte`: 60 tiles de ancho (cols 10-69) y todo el alto, centrada a 250 tiles de la
-- puerta de la iglesia, a >= 10 tiles del borde izquierdo. La carretera (filas 21-24) prolonga la calle principal al ESTE (izquierda) mas alla de la calle de asfalto: asfalto de 4 de ancho,
-- doble linea amarilla (dividida en las filas 22 y 23), sin aceras, cruce limpio con la calle de asfalto, y sigue fuera del mapa por el borde izquierdo (edge_calle_principal_este).
local MT = (function() -- una funcion aparte: el archivo principal ya esta cerca del limite de 200 locales de Lua
local MONTE_DIST_T, MONTE_W, MONTE_MARGIN = 250, 60, 10
local MONTE_X0 = (door_center - MONTE_DIST_T * 16) // 16 - MONTE_W // 2 -- 10
local MONTE_X1 = MONTE_X0 + MONTE_W - 1 -- 69
local ROAD_X1, ROAD_Y0, ROAD_Y1 = PAD + 4, STREET_Y, STREET_Y + STREET_W - 1 -- cols 0-259, filas 21-24
local TRAIL_X0, TRAIL_W, TRAIL_Y0, TRAIL_LEN = MONTE_X0 + 23, 2, ROAD_Y1 + 1, 40
local TURBINES = { { MONTE_X0 + 9, 15 }, { MONTE_X0 + 30, 14 }, { MONTE_X0 + 51, 15 }, { MONTE_X0 + 14, 35 }, { MONTE_X0 + 32, 36 }, { MONTE_X0 + 50, 35 } } -- base (col, fila) de cada torre
local CLEAR_RX, CLEAR_RY = 7, 11 -- claro: elipse centrada 3 filas sobre la base
check(MONTE_X0 == 10 and MONTE_X1 == 69, "el monte ocupa las cols 10-69 (" .. MONTE_X0 .. "-" .. MONTE_X1 .. ")")
check(MONTE_X0 >= MONTE_MARGIN, "el monte debe quedar a >= 10 tiles del borde izquierdo")
check((PAD - 16) * 16 + 816 - 4000 == MONTE_X0 * 16 + MONTE_W * 8, "PAD = 255: el centro del monte queda a 4000 px (250 tiles = 500 m) de la puerta de la iglesia")

-- hoja monte.tsx: nombre / capa / solidez por gid
local mtsx = read_file("games/quebrada/tilesets/monte.tsx")
local m_name, m_solid, m_layer, m_surface = {}, {}, {}, {}
for tid, body in mtsx:gmatch('<tile id="(%d+)">(.-)</tile>') do
  local g = MONTE_FIRSTGID + tonumber(tid)
  m_name[g] = body:match('name="name" value="([^"]*)"')
  m_solid[g] = body:find('name="solid"', 1, true) ~= nil
  m_layer[g] = body:match('name="layer" value="([^"]*)"')
  m_surface[g] = body:match('name="surface" value="([^"]*)"')
end
local function mname(layer, x, y) return m_name[cell(layer, x, y)] end

-- zonas
check(zones.monte ~= nil and zones.monte.props.title == "El monte de hule y níspero" and zones.monte.props.ambience == "monte", "zona monte: titulo 'El monte de hule y níspero' y ambience monte")
if zones.monte then
  local z = zones.monte
  check(z.x == MONTE_X0 * 16 and z.w == MONTE_W * 16 and z.y == 0 and z.h == real_h * 16, "la zona monte: 60 tiles de ancho (cols 10-69) y todo el alto")
  check(door_center - (z.x + z.w / 2) == MONTE_DIST_T * 16, "distancia de la puerta de la iglesia al centro del monte: " .. (door_center - (z.x + z.w / 2)) / 16 .. " tiles, debe ser 250 (= 500 m)")
  check((door_center - (z.x + z.w / 2)) / 16 * METRES_PER_TILE == 500, "el monte debe estar a 500 m")
  check(z.x >= MONTE_MARGIN * 16, "la zona monte a >= 10 tiles del borde izquierdo")
end
check(zones.aerogeneradores ~= nil and zones.aerogeneradores.props.title == "Los aerogeneradores" and zones.aerogeneradores.props.ambience == "monte", "zona aerogeneradores: titulo 'Los aerogeneradores' y ambience monte")
if zones.aerogeneradores and zones.monte then
  local a, m = zones.aerogeneradores, zones.monte
  check(a.x >= m.x and a.x + a.w <= m.x + m.w and a.y >= m.y and a.y + a.h <= m.y + m.h, "la zona aerogeneradores queda dentro del monte")
  check(a.w * a.h < m.w * m.h, "la zona aerogeneradores es mas pequena que el monte (gana donde se solapan)")
  for i, t in ipairs(TURBINES) do
    check(a.x <= (t[1] - CLEAR_RX) * 16 and a.x + a.w >= (t[1] + CLEAR_RX + 1) * 16 and a.y <= math.max(0, t[2] - 3 - CLEAR_RY) * 16 and a.y + a.h >= (t[2] + 1) * 16, "la zona aerogeneradores cubre el claro del aerogenerador " .. i)
  end
end
if zones.parque and zones.monte then check(not overlap(zones.parque, zones.monte), "las zonas del parque y del monte no se solapan") end

-- la carretera: asfalto en las filas 21-24, cols 0-259 (la ultima es el cruce: asfalto liso, sin acera)
for x = 0, ROAD_X1 do
  for y = ROAD_Y0, ROAD_Y1 do
    local g = cell("ground", x, y)
    local nm = gid_name[g] or m_name[g]
    check(nm ~= nil and (nm:match("^asphalt_") or nm:match("^monte_road_")), "la carretera debe ser asfalto en (" .. x .. "," .. y .. "): " .. tostring(nm))
    check(gid_surface[g] == "concreto" or m_surface[g] == "concreto", "la carretera es de concreto (surface) en (" .. x .. "," .. y .. ")")
  end
end
local n_line_n, n_line_s, n_edge_n, n_edge_s = 0, 0, 0, 0
for x = 0, ROAD_X1 - 1 do
  local joins_trail = x >= TRAIL_X0 and x <= TRAIL_X0 + TRAIL_W - 1
  check(mname("ground", x, ROAD_Y0) == "monte_road_edge_n", "borde norte de la carretera (hierba) en col " .. x)
  check(mname("ground", x, ROAD_Y1) == "monte_road_edge_s" or (joins_trail and kind_at(x, ROAD_Y1) == "asphalt"), "borde sur de la carretera en col " .. x)
  if mname("ground", x, ROAD_Y0) == "monte_road_edge_n" then n_edge_n = n_edge_n + 1 end
  if mname("ground", x, ROAD_Y1) == "monte_road_edge_s" then n_edge_s = n_edge_s + 1 end
  check(mname("ground", x, ROAD_Y0 + 1) == "monte_road_line_n", "doble linea amarilla (mitad norte) en (" .. x .. "," .. ROAD_Y0 + 1 .. ")")
  check(mname("ground", x, ROAD_Y0 + 2) == "monte_road_line_s", "doble linea amarilla (mitad sur) en (" .. x .. "," .. ROAD_Y0 + 2 .. ")")
  n_line_n = n_line_n + 1; n_line_s = n_line_s + 1
end
check(n_edge_n == ROAD_X1 and n_edge_s >= ROAD_X1 - TRAIL_W, "bordes de la carretera completos (" .. n_edge_n .. "/" .. n_edge_s .. ")")
-- cruce con la calle de asfalto: col 259 asfalto liso (filas 21-24, sin linea), aceras solo en las filas 20 y 25, sin restos de acera en la interseccion; la linea de la calle N-S sigue interrumpida
for y = ROAD_Y0, ROAD_Y1 do
  check(kind_at(ROAD_X1, y) == "asphalt" and gid_name[cell("ground", ROAD_X1, y)] ~= "asphalt_line_h", "cruce limpio: asfalto liso en (" .. ROAD_X1 .. "," .. y .. ")")
  check(kind_at(PAD + 5, y) == "asphalt" and gid_name[cell("ground", PAD + 6, y)] ~= "asphalt_line_v", "la linea central de la calle de asfalto sigue interrumpida en la interseccion (fila " .. y .. ")")
end
check(kind_at(ROAD_X1, ROAD_Y0 - 1) == "sidewalk" and kind_at(ROAD_X1, ROAD_Y1 + 1) == "sidewalk", "la acera lejana sigue en las filas 20 y 25 (col " .. ROAD_X1 .. ")")
for x = 0, ROAD_X1 do
  check(kind_at(x, ROAD_Y0 - 1) ~= "sidewalk" or x == ROAD_X1, "la carretera no tiene acera (fila 20, col " .. x .. ")")
  check(kind_at(x, ROAD_Y1 + 1) ~= "sidewalk" or x == ROAD_X1, "la carretera no tiene acera (fila 25, col " .. x .. ")")
end
-- el extremo izquierdo: borde edge_calle_principal_este + spawn dentro del mapa sobre el asfalto
check(edge.calle_principal_este ~= nil and edge.calle_principal_este.x == 0 and edge.calle_principal_este.w == 16 and edge.calle_principal_este.y == STREET_Y * 16 and edge.calle_principal_este.h == STREET_W * 16, "borde calle_principal_este: col 0, filas 21-24")
do
  local sp = spawn.edge_calle_principal_este
  check(sp ~= nil and sp.x > 0 and sp.x < 64 and sp.y >= STREET_Y * 16 and sp.y < (STREET_Y + STREET_W) * 16, "el spawn edge_calle_principal_este debe estar dentro del mapa, sobre la carretera, cerca del borde izquierdo")
  check(sp == nil or m_name[cell("ground", sp.x // 16, sp.y // 16)] ~= nil, "el spawn edge_calle_principal_este cae sobre asfalto de la carretera")
  check(sp == nil or sp.props.facing == "right", "el spawn edge_calle_principal_este mira hacia la derecha (hacia el pueblo)")
end
-- el camino de las carretas (lastre) sale de la carretera hacia el sur: cols 33-34, filas 25-64, junta limpia con el asfalto
rect_is("lastre", TRAIL_X0, TRAIL_Y0, TRAIL_X0 + TRAIL_W - 1, TRAIL_Y0 + TRAIL_LEN - 1, "camino de las carretas (lastre)")
for y = TRAIL_Y0, TRAIL_Y0 + TRAIL_LEN - 1 do for x = TRAIL_X0, TRAIL_X0 + TRAIL_W - 1 do
  check(gid_surface[cell("ground", x, y)] == "lastre" and cell("objects", x, y) == 0, "el camino de las carretas es lastre y esta libre en (" .. x .. "," .. y .. ")")
end end

-- los arboles y el sotobosque del monte (cols 10-69): troncos solidos, ninguno en la carretera + 3 de arcen, ninguno en los claros
local function is_trunk(n) return n ~= nil and (n:match("_trunk$") ~= nil or n == "monte_hule_trunk") end
local function in_clearing(x, y)
  for _, t in ipairs(TURBINES) do
    if ((x - t[1]) / CLEAR_RX) ^ 2 + ((y - (t[2] - 3)) / CLEAR_RY) ^ 2 <= 1 then return true end
  end
  return false
end
local counts = { hule = 0, nispero = 0, other = 0, ferns = 0, solid = 0 }
local bad_trunks, outside = 0, 0
for y = 0, map_h - 1 do for x = 0, map_w - 1 do
  local mn, tn = mname("objects", x, y), gname("objects", x, y)
  local in_zone = x >= MONTE_X0 and x <= MONTE_X1
  if mn == "monte_hule_trunk" then counts.hule = counts.hule + 1 elseif mn == "monte_nispero_trunk" then counts.nispero = counts.nispero + 1
  elseif tn and (tn == "guanacaste_trunk" or tn == "palm_trunk" or tn == "monte_trunk") and in_zone then counts.other = counts.other + 1 end
  if mn == "monte_fern_a" or mn == "monte_fern_b" then counts.ferns = counts.ferns + 1 end
  if in_zone and (is_trunk(mn) or mn == "monte_bush" or mn == "monte_log" or mn == "monte_rock_moss") then
    counts.solid = counts.solid + 1
    if (y >= ROAD_Y0 - 3 and y <= ROAD_Y1 + 3) or in_clearing(x, y) then bad_trunks = bad_trunks + 1 end
  end
  if not in_zone and (mn == "monte_hule_trunk" or mn == "monte_nispero_trunk" or mn == "monte_bush" or mn == "monte_log" or mn == "monte_rock_moss") then outside = outside + 1 end
end end
check(counts.hule >= 100 and counts.nispero >= 100 and counts.other >= 100, "el monte debe tener muchos hules, nisperos y arboles del monte/guanacaste/palmeras (" .. counts.hule .. "/" .. counts.nispero .. "/" .. counts.other .. ")")
check(counts.ferns >= 100, "el monte debe tener helechos (" .. counts.ferns .. ")")
check(bad_trunks == 0, "hay " .. bad_trunks .. " troncos / matorrales del monte en la carretera (+3 de arcen) o en un claro de aerogenerador")
check(outside == 0, "los arboles del monte quedan dentro de la zona (" .. outside .. " fuera)")
-- sin troncos pegados (ni en diagonal): ningun bolsillo cerrado
local touching = 0
for y = 0, map_h - 1 do for x = MONTE_X0, MONTE_X1 - 1 do
  local function sol(xx, yy) local n = mname("objects", xx, yy); return is_trunk(n) or is_trunk(gname("objects", xx, yy)) or n == "monte_bush" or n == "monte_log" or n == "monte_rock_moss" or n == "monte_tower_0_9" end
  if sol(x, y) and (sol(x + 1, y) or (y + 1 < map_h and (sol(x, y + 1) or sol(x + 1, y + 1) or sol(x - 1, y + 1)))) then touching = touching + 1 end
end end
check(touching == 0, "hay " .. touching .. " pares de solidos del monte pegados (los troncos deben dejar paso)")
-- borde gradual: la densidad sube en ~10 tiles desde el borde de la zona (las 3 primeras columnas tienen menos arboles que las columnas 20-29 de dentro)
do
  local function trunks_in(x0, x1) local n = 0; for y = 0, map_h - 1 do for x = x0, x1 do if is_trunk(mname("objects", x, y)) or is_trunk(gname("objects", x, y)) then n = n + 1 end end end; return n end
  check(trunks_in(MONTE_X0, MONTE_X0 + 2) * 2 < trunks_in(MONTE_X0 + 17, MONTE_X0 + 19), "el borde del monte debe ser gradual (arboles en las 3 primeras cols: " .. trunks_in(MONTE_X0, MONTE_X0 + 2) .. ", en las cols 17-19 de dentro: " .. trunks_in(MONTE_X0 + 17, MONTE_X0 + 19) .. ")")
end
-- suelo del monte: cesped oscuro, hojarasca y barro (la variacion)
do
  local grass, litter, mud = 0, 0, 0
  for y = 0, map_h - 1 do for x = MONTE_X0, MONTE_X1 do
    local n = mname("ground", x, y)
    if n and n:match("^monte_grass_") then grass = grass + 1 elseif n and n:match("^monte_litter_") then litter = litter + 1 elseif n and n:match("^monte_mud_") then mud = mud + 1 end
  end end
  check(grass > 500 and litter > 50 and mud > 5, "suelo del monte: cesped oscuro / hojarasca / barro (" .. grass .. "/" .. litter .. "/" .. mud .. ")")
end

-- los 6 aerogeneradores: base solida (objects), fuste + gondola above (canopy), rotor 9x9 animado (capa rotors), plataforma de concreto 3x2, luz roja
check(#TURBINES == 6, "deben ser 6 aerogeneradores")
local n_bases = 0
for y = 0, map_h - 1 do for x = 0, map_w - 1 do if mname("objects", x, y) == "monte_tower_0_9" then n_bases = n_bases + 1 end end end
check(n_bases == 6, "hay " .. n_bases .. " bases de torre en objects, deben ser 6")
for i, t in ipairs(TURBINES) do
  local bx, by = t[1], t[2]
  check(bx >= MONTE_X0 and bx <= MONTE_X1, "aerogenerador " .. i .. " dentro del monte")
  check(mname("objects", bx, by) == "monte_tower_0_9", "aerogenerador " .. i .. ": falta la base de la torre en (" .. bx .. "," .. by .. ")")
  check(m_solid[cell("objects", bx, by)] == true and m_layer[cell("objects", bx, by)] == "ysort", "aerogenerador " .. i .. ": la base es ysort y solid")
  for cy = 0, 8 do
    local g = cell("canopy", bx, by - 9 + cy)
    check(m_name[g] == "monte_tower_0_" .. cy and m_layer[g] == "above" and not m_solid[g], "aerogenerador " .. i .. ": celda " .. cy .. " de la torre above en (" .. bx .. "," .. by - 9 + cy .. ")")
  end
  check(mname("rotors", bx, by - 9) == "monte_rotor_4_4", "aerogenerador " .. i .. ": el cubo del rotor (monte_rotor_4_4) sobre la gondola (" .. bx .. "," .. by - 9 .. ")")
  local rc = 0
  for y = by - 13, by - 5 do for x = bx - 4, bx + 4 do if mname("rotors", x, y) then rc = rc + 1 end end end
  check(rc >= 30, "aerogenerador " .. i .. ": rotor 9x9 con " .. rc .. " celdas")
  for dy = 0, 1 do for dx = -1, 1 do
    local n = mname("ground", bx + dx, by + dy)
    check(n == "monte_pad_a" or n == "monte_pad_b", "aerogenerador " .. i .. ": plataforma de concreto 3x2 en (" .. bx + dx .. "," .. by + dy .. ")")
  end end
  local setback = by < ROAD_Y0 and (ROAD_Y0 - by) or (by - ROAD_Y1)
  check(setback >= 5 and setback <= 12, "aerogenerador " .. i .. ": retranqueo de " .. setback .. " tiles respecto a la carretera (5-12)")
  local l = by_name["luz_aerogenerador_" .. i]
  check(l ~= nil and l.class == "light" and l.props.only == "dusk,night" and tonumber(l.props.radius) == 20 and tonumber(l.props.r) > 200 and tonumber(l.props.g) < 100 and tonumber(l.props.b) < 100 and tonumber(l.props.flicker) > 0,
    "aerogenerador " .. i .. ": luz roja de aviso (radius 20, flicker, only=dusk,night)")
  if l then check(math.abs((l.x + l.w / 2) - (bx * 16 + 8)) <= 1 and (l.y + l.h / 2) >= (by - 9) * 16 and (l.y + l.h / 2) <= (by - 8) * 16, "aerogenerador " .. i .. ": la luz esta en la gondola") end
  -- separacion entre aerogeneradores: 20-30 tiles (en distancia) con el vecino mas cercano
  local nearest = math.huge
  for j, u in ipairs(TURBINES) do if j ~= i then nearest = math.min(nearest, math.sqrt((u[1] - bx) ^ 2 + (u[2] - by) ^ 2)) end end
  check(nearest >= 18 and nearest <= 32, "aerogenerador " .. i .. ": separacion de " .. string.format("%.1f", nearest) .. " tiles con el vecino mas cercano (18-32)")
end

return { MONTE_X0 = MONTE_X0, MONTE_X1 = MONTE_X1, ROAD_X1 = ROAD_X1, ROAD_Y0 = ROAD_Y0, ROAD_Y1 = ROAD_Y1, TRAIL_X0 = TRAIL_X0, TRAIL_Y0 = TRAIL_Y0, TRAIL_LEN = TRAIL_LEN, TURBINES = TURBINES }
end)()

-- ---- la quebrada (docs/rio.md): coordenadas ABSOLUTAS (marco nuevo, con TOP filas arriba) ----
-- hoja rio: nombres por gid (firstgid 1457); agua = water_* (town) o rio_water_* (rio), tiles de SUELO solidos
local r_name = {}
for id, body in read_file("games/quebrada/tilesets/rio.tsx"):gmatch('<tile id="(%d+)">(.-)</tile>') do r_name[RIO_FIRSTGID + tonumber(id)] = body:match('name="name" value="([^"]*)"') end
local function is_water(g) local n = gid_name[g] or r_name[g]; return n ~= nil and (n:match("^water_") ~= nil or n:match("^rio_water_") ~= nil) end
local function is_bank(g) local n = gid_name[g] or r_name[g]; return n ~= nil and (n:match("^bank_") ~= nil or n:match("^rio_bank_inner_") ~= nil) end
local function water_at(x, y) return is_water(rcell("ground", x, y)) end
local RIVER_ASKED = { { "iglesia", PAD + 35, 6 + TOP, 175, 88 }, { "cafetal", EXT_PAVER_X1 - 25, 5 + TOP, 20, 10 }, { "casa_mama", Z.MAMA_AT[1] + 4, Z.MAMA_AT[2], 50, 25 } } -- id, col, fila superior del objeto, metros pedidos, tiles
local river_cols = {}
for _, a in ipairs(RIVER_ASKED) do
  local id, col, top, metres, tiles = a[1], a[2], a[3], a[4], a[5]
  local y0
  for y = 0, top - 1 do if water_at(col, y) then y0 = y; break end end
  check(y0 ~= nil, "rio: sin agua al norte de " .. id .. " (col " .. col .. ")")
  if y0 then
    local y1 = y0
    while water_at(col, y1 + 1) do y1 = y1 + 1 end
    local centre = (y0 + y1) / 2
    local dist = top - centre
    check(math.abs(dist - tiles) <= 1, "rio: a " .. id .. " el centro del rio esta a " .. dist .. " tiles = " .. dist * METRES_PER_TILE .. " m al norte, se pedian " .. metres .. " m (" .. tiles .. " tiles +- 1)")
    check(y1 - y0 + 1 >= 3 and y1 - y0 + 1 <= 7, "rio: ancho en " .. id .. " (" .. (y1 - y0 + 1) .. " tiles) fuera de 3-7")
  end
end
-- el rio cruza todo el ancho del mapa; grosor 3-7 tiles; sin rebanadas; 6+ filas de cesped al norte de la orilla mas norte
do
  local first_bank = math.huge
  local n_water, min_t, max_t = 0, math.huge, 0
  for x = 0, map_w - 1 do
    local run, best = 0, 0
    for y = 0, real_h - 1 do
      local g = rcell("ground", x, y)
      if is_water(g) then n_water = n_water + 1; run = run + 1; best = math.max(best, run) else run = 0 end
      if is_bank(g) or is_water(g) then first_bank = math.min(first_bank, y) end
    end
    if x < PAD + 3 or x > PAD + 10 then check(best >= 3, "rio: en la col " .. x .. " el agua tiene " .. best .. " tiles de alto (sin rebanadas de 1-2)") end
    min_t, max_t = math.min(min_t, best), math.max(max_t, best)
  end
  check(first_bank >= 6, "rio: debe haber >= 6 filas de cesped al norte de la orilla mas norte (hay " .. first_bank .. ")")
  check(n_water > 3000, "rio: pocas celdas de agua (" .. n_water .. ")")
  check(max_t <= 8, "rio: el agua llega a " .. max_t .. " tiles de alto en una columna")
  -- los tiles de agua nunca estan bajo la calzada del puente (cols de asfalto y aceras) ni en un tile no de suelo
  for x = PAD + 4, PAD + 9 do for y = 0, real_h - 1 do check(not water_at(x, y), "rio: agua bajo el puente en (" .. x .. "," .. y .. ")") end end
end
-- el puente: la calle de asfalto continua al norte hasta el borde superior (cols 5-8 asfalto, aceras cols 4 y 9), con barandas amarillas oxidadas, postes y estribos
do
  local rails, posts, piers, rail_rows = 0, 0, 0, {}
  for y = 0, real_h - 1 do
    for x = PAD + 5, PAD + 8 do check(kind(rcell("ground", x, y)) == "asphalt", "calle de asfalto prolongada: falta asfalto en (" .. x .. "," .. y .. ")") end
    if y < TOP then
      check(kind(rcell("ground", PAD + 4, y)) == "sidewalk" and kind(rcell("ground", PAD + 9, y)) == "sidewalk", "calle de asfalto prolongada: faltan las aceras en la fila " .. y)
    end
    for _, x in ipairs({ PAD + 3, PAD + 10 }) do
      local n = r_name[rcell("objects", x, y)]
      if n == "rio_rail_w" or n == "rio_rail_e" then rails = rails + 1; rail_rows[#rail_rows + 1] = y elseif n == "rio_post" then posts = posts + 1 end
    end
    for _, x in ipairs({ PAD + 2, PAD + 11 }) do local n = r_name[rcell("objects", x, y)]; if n == "rio_abutment_w" or n == "rio_abutment_e" then piers = piers + 1 end end
  end
  check(rails >= 12 and posts == 4 and piers == 6, "puente: barandas " .. rails .. " (>= 12), postes " .. posts .. " (4), estribos " .. piers .. " (6)")
  check(by_name.edge_calle_este_norte ~= nil and by_name.edge_calle_este_norte.y == 0, "la calle de asfalto prolongada conserva el borde norte en la fila 0")
  -- el puente sobrepasa 2 tiles cada orilla: las barandas cubren de (primera fila de agua - 3) a (ultima + 3)
  local w0, w1 = math.huge, 0
  for y = 0, real_h - 1 do if water_at(PAD + 2, y) then w0 = math.min(w0, y); w1 = math.max(w1, y) end end
  check(#rail_rows > 0 and math.min(table.unpack(rail_rows)) == w0 - 2 and math.max(table.unpack(rail_rows)) == w1 + 2, "puente: debe pasar 2 tiles mas alla de cada orilla (barandas en las filas " .. (w0 - 2) .. " a " .. (w1 + 2) .. ", postes en " .. (w0 - 3) .. " y " .. (w1 + 3) .. ")")
  -- el rio es recto y horizontal en el cruce: la misma fila de agua en las 12 cols alrededor
  local same = true
  for x = PAD - 2, PAD + 13 do
    if x < PAD + 3 or x > PAD + 10 then for y = w0, w1 do if not water_at(x, y) then same = false end end end
  end
  check(same, "el rio debe ser recto y horizontal en el cruce del puente")
end
-- zona rio: tiras de 20 tiles que siguen el rio (mismo id de zona `rio`, nombre unico zone_rio_NN)
do
  local strips, covered = 0, 0
  for _, o in ipairs(objects) do
    local n = o.name and o.name:match("^zone_rio_(%d+)$")
    if n then
      strips = strips + 1; covered = covered + o.w
      check(o.props.zone == "rio" and o.props.title == "La quebrada" and o.props.ambience == "quebrada", o.name .. ": zona rio, titulo 'La quebrada', ambiente quebrada")
      check(o.w <= 20 * 16 and o.h >= 16 * 16, o.name .. ": tira de <= 20 tiles de ancho que abarca el agua + 8 tiles a cada lado")
    end
  end
  check(strips >= math.ceil(map_w / Z.RIVER_ZONE_LEN) and covered == map_w * 16, "zona rio: tiras que cubren todo el ancho (" .. strips .. " tiras, " .. covered .. " px)")
end

-- ---- alcanzabilidad (relleno desde el spawn default sobre tiles no solidos y sin las huellas de los edificios) ----
do
  local function solids(path, first)
    local set = {}
    for tid, body in read_file(path):gmatch('<tile id="(%d+)">(.-)</tile>') do if body:find('name="solid"', 1, true) then set[first + tonumber(tid)] = true end end
    return set
  end
  local solid = {}
  for _, t in ipairs({ { "town", 1 }, { "buildings", 145 }, { "park", PARK_FIRSTGID }, { "school", SCHOOL_FIRSTGID }, { "ebais", EBAIS_FIRSTGID }, { "monte", MONTE_FIRSTGID } }) do
    for g in pairs(solids("games/quebrada/tilesets/" .. t[1] .. ".tsx", t[2])) do solid[g] = true end
  end
  for _, t in ipairs({ { "rio", RIO_FIRSTGID } }) do
    for g in pairs(solids("games/quebrada/tilesets/" .. t[1] .. ".tsx", t[2])) do solid[g] = true end
  end
  local blocked = {}
  for _, l in ipairs({ "objects", "buildings", "ground" }) do -- el agua es un tile de SUELO solido
    for i, g in ipairs(layers[l]._cells) do if solid[g] then blocked[i] = true end end
  end
  for _, o in ipairs(objects) do
    if o.name and o.name:match("_footprint$") then
      for y = o.y // 16 + TOP, (o.y + o.h - 1) // 16 + TOP do for x = o.x // 16, (o.x + o.w - 1) // 16 do blocked[y * map_w + x + 1] = true end end
    end
  end
  local seen, q, qi = {}, { { spawn.default.x // 16, spawn.default.y // 16 + TOP } }, 1
  seen[q[1][2] * map_w + q[1][1] + 1] = true
  while q[qi] do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = x + d[1], y + d[2]
      local i = ny * map_w + nx + 1
      if nx >= 0 and ny >= 0 and nx < map_w and ny < real_h and not seen[i] and not blocked[i] then seen[i] = true; q[#q + 1] = { nx, ny } end
    end
  end
  local function reach(x, y) return seen[(y // 16 + TOP) * map_w + (x // 16) + 1] == true end -- y en px del marco original
  check(reach(PLOT_X1 * 16 + 8, 46 * 16 + 8) and reach(PLOT_X1 * 16 + 8, 47 * 16 + 8), "la entrada de la escuela (col 18, filas 46-47) debe ser alcanzable")
  check(reach((Z.FLAG_X + 1) * 16 + 8, (Z.FLAG_Y + 2) * 16 + 8) and reach((10 + D) * 16 + 8, 57 * 16 + 8) and reach((17 + D) * 16 + 8, 54 * 16 + 8), "el patio, el pasillo este y el patio sur de la escuela deben ser alcanzables")
  for _, n in ipairs({ "escuela_aulas_a", "escuela_aulas_b" }) do
    for i = 1, 2 do local d = by_name[n .. "_puerta_" .. i]; check(d and reach(d.x + d.w // 2, d.y + 8), n .. "_puerta_" .. i .. " debe ser alcanzable") end
  end
  check(reach(PLOT_X1 * 16 + 8, 32 * 16 + 8) and reach(PLOT_X1 * 16 + 8, 33 * 16 + 8), "la entrada de Olguita (col 18, filas 32-33) debe ser alcanzable")
  check(op and reach(op.x + op.w // 2, op.y + 8), "la puerta de Olguita debe ser alcanzable")
  -- el Ebais: la puerta de 2 tiles al norte (cols 57-58, fila 70) y su entrada, el camino de 2 de ancho, el patio, la puerta de vidrio y el extremo sur de la calle de lastre
  for _, x in ipairs({ EB_GATE0, EB_GATE1 }) do
    check(reach(x * 16 + 8, EB_Y0 * 16 + 8) and reach(x * 16 + 8, (EB_Y0 - 1) * 16 + 8), "la puerta del Ebais (col " .. x .. ", filas 69-70) debe ser alcanzable")
    check(reach(x * 16 + 8, (EB_AT_Y + 2) * 16 + 8) and reach(x * 16 + 8, (EB_AT_Y + 6) * 16 + 8), "el camino del Ebais (col " .. x .. ") debe ser alcanzable")
  end
  check(reach((66 + D) * 16 + 8, 80 * 16 + 8) and reach((70 + D) * 16 + 8, 82 * 16 + 8), "el patio y el parqueo del Ebais deben ser alcanzables")
  local ed = by_name.ebais_puerta
  check(ed and reach(ed.x + ed.w // 2, ed.y + 8), "la puerta de vidrio del Ebais debe ser alcanzable")
  check(reach((WEST_X + 1) * 16 + 8, (map_h - 2) * 16 + 8) and reach((WEST_X + 2) * 16 + 8, (map_h - 2) * 16 + 8), "el extremo sur de la calle de lastre debe ser alcanzable")
  local MONTE_X0, MONTE_X1, ROAD_X1, ROAD_Y0, ROAD_Y1, TRAIL_X0, TRAIL_Y0, TRAIL_LEN, TURBINES = MT.MONTE_X0, MT.MONTE_X1, MT.ROAD_X1, MT.ROAD_Y0, MT.ROAD_Y1, MT.TRAIL_X0, MT.TRAIL_Y0, MT.TRAIL_LEN, MT.TURBINES
  -- el monte: la carretera hasta el borde izquierdo (col 0), el cruce, el camino de las carretas y el claro de cada aerogenerador
  for x = 0, ROAD_X1 do check(reach(x * 16 + 8, (ROAD_Y0 + 1) * 16 + 8) and reach(x * 16 + 8, (ROAD_Y1) * 16 + 8), "la carretera debe ser alcanzable en la col " .. x) end
  check(spawn.edge_calle_principal_este and reach(spawn.edge_calle_principal_este.x, spawn.edge_calle_principal_este.y), "el spawn edge_calle_principal_este debe ser alcanzable")
  check(reach((TRAIL_X0 + 1) * 16 + 8, (TRAIL_Y0 + TRAIL_LEN - 1) * 16 + 8), "el final del camino de las carretas debe ser alcanzable")
  for i, t in ipairs(TURBINES) do
    check(reach(t[1] * 16 + 8, (t[2] + 2) * 16 + 8) and reach((t[1] - 1) * 16 + 8, t[2] * 16 + 8) and reach((t[1] + 1) * 16 + 8, t[2] * 16 + 8) and reach(t[1] * 16 + 8, (t[2] - 4) * 16 + 8), "el claro del aerogenerador " .. i .. " debe ser alcanzable")
  end
  -- sin bolsillos: toda celda libre de la zona del monte es alcanzable desde el spawn
  local pockets = 0
  for y = 0, real_h - 1 do for x = MONTE_X0, MONTE_X1 do
    local i = y * map_w + x + 1
    if not blocked[i] and not seen[i] then pockets = pockets + 1 end
  end end
  check(pockets == 0, "hay " .. pockets .. " celdas libres del monte inalcanzables (bolsillos cerrados)")
  -- la quebrada: el agua no se camina, el norte se alcanza por el puente (calzada y aceras: cols 4-9 de la calle de asfalto)
  local walk_water = 0
  for y = 0, real_h - 1 do for x = 0, map_w - 1 do if is_water(rcell("ground", x, y)) and not blocked[y * map_w + x + 1] then walk_water = walk_water + 1 end end end
  check(walk_water == 0, "rio: " .. walk_water .. " celdas de agua caminables")
  local ws = {}
  for y = 0, real_h - 1 do if is_water(rcell("ground", PAD + 2, y)) then ws[#ws + 1] = y end end
  local wy0, wy1 = ws[1], ws[#ws]
  local function reach_abs(x, y) return seen[(y // 16) * map_w + (x // 16) + 1] == true end
  check(reach_abs((PAD + 6) * 16 + 8, (wy1 + 4) * 16 + 8) and reach_abs((PAD + 6) * 16 + 8, (wy0 + wy1) // 2 * 16 + 8) and reach_abs((PAD + 6) * 16 + 8, (wy0 - 4) * 16 + 8), "rio: el puente debe poder cruzarse (orilla sur, calzada, orilla norte)")
  check(reach_abs(400 * 16 + 8, 2 * 16 + 8) == true or not blocked[2 * map_w + 400 + 1], "rio: la tierra del norte (fila 2) debe ser alcanzable")
  check(reach_abs((PAD + 4) * 16 + 8, (wy0 + wy1) // 2 * 16 + 8) and reach_abs((PAD + 9) * 16 + 8, (wy0 + wy1) // 2 * 16 + 8), "rio: las aceras del puente deben ser transitables")
end

-- ---- colisiones: borde del mapa ----
for _, n in ipairs({ "wall_top", "wall_bottom", "wall_left", "wall_right" }) do check(by_name[n] ~= nil, "falta " .. n) end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("zona1_check OK")
