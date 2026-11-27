-- Validacion de la zona 1 (issue #78): maps/zona1.tmx. Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/zona1_check.lua
-- Sin motor: parsea el XML con patrones de cadena (como buildings_check.lua). Todo objeto del
-- TMX se escribe como <object ...>...</object> (nunca autocerrado): el patron de abajo lo necesita.
-- Convenciones en games/quebrada/docs/zona1.md.
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

local ZONA = "games/quebrada/maps/zona1.tmx"
local tmx = read_file(ZONA)

-- ---- mapa ----
local METRES_PER_TILE = 2
-- Orientacion: OESTE = DERECHA de la pantalla, ESTE = IZQUIERDA, SUR = abajo, NORTE = arriba.
local EXT_PAVER_M, EXT_LASTRE_M = 550, 200
local EXT_PAVER_T, EXT_LASTRE_T = EXT_PAVER_M // METRES_PER_TILE, EXT_LASTRE_M // METRES_PER_TILE -- 275, 100
local EXT_X0 = 60
local EXT_PAVER_X1 = EXT_X0 + EXT_PAVER_T - 1 -- 334
local LASTRE_X0, LASTRE_X1 = EXT_PAVER_X1 + 1, EXT_PAVER_X1 + EXT_LASTRE_T -- 335, 434
local MAP_W, MAP_H = LASTRE_X1 + 1 + 10, 72 -- 445 x 72 (10 tiles de margen a la derecha, 3 filas abajo)
local STREET_X, STREET_Y, STREET_LEN, STREET_W = 10, 21, 50, 4 -- tiles; 50 tiles = 100 m; ancho 4 (~8 m reales, distorsion conocida)
local CHURCH_X, CHURCH_Y, CHURCH_W, CHURCH_H = 30, 6, 10, 12 -- tiles
local SIDEWALK_A, SIDEWALK_B = 49, 50 -- gids de sidewalk_a / sidewalk_b (tile ids 48 / 49)
local PARK_FIRSTGID = 529 -- town (144) + buildings (384) + 1
local PARK_X, PARK_Y, PARK_W, PARK_H = 10, 27, 50, 37 -- el parque: una cuadra (50 tiles), una fila de cesped bajo la acera sur
local PAVER_A, PAVER_B = 51, 52 -- gids de paver_a / paver_b (town firstgid 1, tile ids 50 / 51)
local head = tmx:match("<map ([^>]*)>")
local map_w, map_h = tonumber(attr(head, "width")), tonumber(attr(head, "height"))
check(map_w == MAP_W and map_h == MAP_H, "el mapa debe ser 445x72 (" .. tostring(map_w) .. "x" .. tostring(map_h) .. ")")
check(tonumber(attr(head, "tilewidth")) == 16 and tonumber(attr(head, "tileheight")) == 16, "tiles de 16x16")
check(STREET_LEN * METRES_PER_TILE == 100, "la calle debe medir 100 m")
check(tmx:match('<property name="metres_per_tile"[^>]-value="2"') ~= nil, "falta metres_per_tile=2 en el mapa")
check(tmx:match('<tileset firstgid="1" source="%.%./tilesets/town%.tsx"/>') ~= nil, "falta el tileset town (firstgid 1)")
check(tmx:match('<tileset firstgid="145" source="%.%./tilesets/buildings%.tsx"/>') ~= nil, "falta el tileset buildings (firstgid 145)")

check(tmx:match('<tileset firstgid="' .. PARK_FIRSTGID .. '" source="%.%./tilesets/park%.tsx"/>') ~= nil, "falta el tileset park (firstgid 529)")
local _, n_tilesets = tmx:gsub("<tileset ", "")
check(n_tilesets == 3, "el mapa debe declarar 3 tilesets (town, buildings, park), tiene " .. n_tilesets)

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
for _, n in ipairs({ "ground", "overlay", "objects", "buildings", "windows_lit", "roof_iglesia", "roof_casa_mama", "roof_casa_2", "canopy" }) do
  check(layers[n] ~= nil, "falta la capa " .. n)
end
check(layers.objects and layers.objects.ysort == "true", "objects debe ser ysort")
check(layers.windows_lit and layers.windows_lit.ysort == "true", "windows_lit debe ser ysort")
check(layers.canopy and layers.canopy.above == "true", "canopy debe ser above")
local function cell(layer, x, y) return layers[layer]._cells[y * map_w + x + 1] end -- x, y en tiles

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
  for _, x in ipairs({ 6, 62, 100, 340, 420 }) do
    local k = kind_at(x, y)
    check(SURF[k] == nil or gid_surface[cell("ground", x, y)] == SURF[k], "superficie inesperada en (" .. x .. "," .. y .. "): " .. k)
  end
end
local function rect_is(k, x0, y0, x1, y1, what)
  for y = y0, y1 do for x = x0, x1 do
    if kind_at(x, y) ~= k then check(false, what .. ": se esperaba " .. k .. " en (" .. x .. "," .. y .. "), hay " .. kind_at(x, y)); return end
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

-- ---- la extension al oeste (derecha): 550 m de adoquin + 200 m de lastre = 750 m = 375 tiles ----
check(EXT_PAVER_T == 275 and EXT_LASTRE_T == 100 and EXT_PAVER_T + EXT_LASTRE_T == 375, "extension: 275 + 100 = 375 tiles")
check((EXT_PAVER_T + EXT_LASTRE_T) * METRES_PER_TILE == 750, "la extension debe medir 750 m")
rect_is("paver", EXT_X0, STREET_Y, EXT_PAVER_X1, STREET_Y + STREET_W - 1, "extension de adoquin (550 m)")
rect_is("lastre", LASTRE_X0, STREET_Y, LASTRE_X1, STREET_Y + STREET_W - 1, "tramo de lastre (200 m)")
rect_is("grass", LASTRE_X1 + 1, STREET_Y, map_w - 1, STREET_Y + STREET_W - 1, "margen tras el lastre")
for y = STREET_Y, STREET_Y + STREET_W - 1 do
  local g = cell("ground", LASTRE_X0, y)
  check(gid_surface[g] == "lastre", "el lastre debe tener surface=lastre en (" .. LASTRE_X0 .. "," .. y .. ")")
  g = cell("ground", EXT_X0 + 10, y)
  check(gid_surface[g] == "concreto", "el adoquin debe tener surface=concreto")
end
-- el lastre no tiene aceras: filas 20 y 25 son cesped
rect_is("grass", LASTRE_X0, STREET_Y - 1, LASTRE_X1, STREET_Y - 1, "sin acera norte en el lastre")
for x = LASTRE_X0, LASTRE_X1 do -- fila 25: cesped salvo donde arrancan los caminos de las casas de Chayo (406-407) y mama (432-433)
  local foot = x == 406 or x == 407 or x == 432 or x == 433
  check(kind_at(x, STREET_Y + STREET_W) == (foot and "lastre" or "grass"), "sin acera sur en el lastre (fila 25, col " .. x .. ")")
end
-- el lastre tiene rodadas (ruts) en las filas interiores
local ruts = 0
for x = LASTRE_X0, LASTRE_X1 do if gid_name[cell("ground", x, STREET_Y + 1)] == "lastre_ruts_h" then ruts = ruts + 1 end end
check(ruts > 50, "el lastre debe tener rodadas (" .. ruts .. ")")

-- ---- aceras de la extension de adoquin (filas 20 y 25, cols 60-334); la sur se abre en la T oeste (cols 61-64) ----
rect_is("sidewalk", EXT_X0, STREET_Y - 1, EXT_PAVER_X1, STREET_Y - 1, "acera norte de la extension")
rect_is("sidewalk", EXT_X0, STREET_Y + STREET_W, EXT_X0, STREET_Y + STREET_W, "acera sur (col 60)")
rect_is("paver", 61, STREET_Y + STREET_W, 64, STREET_Y + STREET_W, "union en T: sin acera en cols 61-64 de la fila 25")
rect_is("sidewalk", 65, STREET_Y + STREET_W, EXT_PAVER_X1, STREET_Y + STREET_W, "acera sur tras la union")

-- ---- calles alrededor del parque ----
-- oeste (derecha del parque): adoquin cols 61-64, filas 25-68; acera solo del lado del parque (col 60, filas 25-64)
rect_is("paver", 61, 25, 64, 68, "calle oeste del parque")
rect_is("sidewalk", 60, 25, 60, 64, "acera de la calle oeste (lado del parque)")
rect_is("grass", 65, 26, 65, 68, "la calle oeste no tiene acera en el lado lejano")
-- sur (bajo el parque): adoquin filas 65-68, cols 9-60; acera solo del lado del parque (fila 64)
rect_is("paver", 9, 65, 64, 68, "calle sur del parque")
rect_is("sidewalk", 10, 64, 60, 64, "acera de la calle sur (lado del parque)")
rect_is("grass", 10, 69, 64, map_h - 1, "la calle sur no tiene acera en el lado lejano; 3 filas de margen")
-- este (izquierda del parque): ASFALTO cols 5-8, toda la altura (filas 0-71), aceras en col 4 y col 9
for y = 0, map_h - 1 do
  for x = 5, 8 do check(kind_at(x, y) == "asphalt", "falta asfalto en (" .. x .. "," .. y .. ")") end
  check(kind_at(4, y) == "sidewalk", "falta la acera lejana (col 4) en la fila " .. y)
  local mouth = (y >= 21 and y <= 24) or (y >= 65 and y <= 68)
  if mouth then check(kind_at(9, y) == "paver", "la boca de la calle en (9," .. y .. ") debe ser adoquin (sin acera)")
  else check(kind_at(9, y) == "sidewalk", "falta la acera del parque (col 9) en la fila " .. y) end
end
check(kind_at(3, 30) == "grass" and kind_at(0, 10) == "grass", "el resto es cesped")
-- linea amarilla doble (col 6): continua salvo en las dos uniones (filas 21-24 y 65-68)
for y = 0, map_h - 1 do
  local gap = (y >= 21 and y <= 24) or (y >= 65 and y <= 68)
  local is_line = gid_name[cell("ground", 6, y)] == "asphalt_line_v"
  check(is_line == not gap, "linea central en (6," .. y .. "): " .. tostring(is_line))
end
-- las esquinas de las uniones no tienen restos de acera dentro de la interseccion
rect_is("paver", 61, 21, 64, 25, "T norte: interseccion limpia")
rect_is("paver", 61, 65, 64, 68, "esquina sur-oeste limpia")

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
check(street_center == 560, "el centro de la calle original debe estar en x=560 px (col 35)")
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
  check(spawn.default.x == 560 and spawn.default.y == 308, "default debe estar en (560,308)")
  check(dx == 0 and dy >= 0 and dy <= 64, "default debe estar justo delante de la puerta de la iglesia (" .. dx .. "," .. dy .. ")")
end

-- ---- bordes (extremos de la calle) y zonas ----
local edge = {}
for _, o in ipairs(of_class("edge")) do
  edge[o.props.edge or ""] = o
  check(o.props.connects_to ~= nil, "edge " .. tostring(o.props.edge) .. " sin connects_to")
end
for _, id in ipairs({ "calle_principal_oeste", "calle_este_norte", "calle_este_sur" }) do
  check(edge[id] ~= nil, "falta el borde " .. id)
  check(spawn["edge_" .. id] ~= nil, "falta el spawn edge_" .. id)
  local sp = spawn["edge_" .. id]
  check(sp == nil or (sp.x > 0 and sp.x < map_w * 16 and sp.y > 0 and sp.y < map_h * 16), "el spawn edge_" .. id .. " debe estar dentro del mapa")
end
check(edge.calle_oeste == nil and edge.calle_este == nil, "los bordes viejos calle_oeste/calle_este ya no existen")
if edge.calle_principal_oeste then
  check(edge.calle_principal_oeste.x + edge.calle_principal_oeste.w == (LASTRE_X1 + 1) * 16, "el borde de la calle principal debe estar en el extremo del lastre")
end
if edge.calle_este_norte then check(edge.calle_este_norte.y == 0 and edge.calle_este_norte.x == 5 * 16 and edge.calle_este_norte.w == 4 * 16, "borde norte de la calle de asfalto") end
if edge.calle_este_sur then check(edge.calle_este_sur.y + edge.calle_este_sur.h == map_h * 16 and edge.calle_este_sur.x == 5 * 16, "borde sur de la calle de asfalto") end
local zones = {}
for _, o in ipairs(of_class("zone")) do zones[o.props.zone or ""] = o end
for _, id in ipairs({ "zona1", "iglesia", "parque" }) do check(zones[id] ~= nil, "falta la zona " .. id) end
if zones.parque then
  local z = zones.parque
  check(z.x == PARK_X * 16 and z.y == PARK_Y * 16 and z.w == PARK_W * 16 and z.h == PARK_H * 16, "la zona parque debe cubrir el parque (50x37 tiles desde (10,27))")
  check(z.props.title == "El parque" and z.props.ambience == "pueblo", "la zona parque: titulo 'El parque' y ambience pueblo")
end
if zones.zona1 then check(zones.zona1.w == map_w * 16 and zones.zona1.h == map_h * 16, "la zona zona1 debe cubrir todo el mapa") end

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
check(park_cells("ground", 11, 39, 22, 54) == 12 * 16, "el skate park debe ser 12x16 tiles del tileset park")
check(park_cells("ground", 24, 43, 35, 50) == 12 * 8, "los juegos de ninos deben ser 12x8 tiles de arena")
check(park_cells("ground", 37, 52, 59, 63) == 23 * 12, "la cancha (con su acera) debe ser 23x12 tiles del tileset park")
-- equipo: columpios (base solida), tobogan, trepador, aros y arcos en la capa objects (ysort)
for _, p in ipairs({ { 25, 45 }, { 27, 45 }, { 30, 45 }, { 31, 45 }, { 33, 46 }, { 34, 46 }, { 40, 58 }, { 56, 58 }, { 38, 55 }, { 38, 59 }, { 58, 55 }, { 58, 59 } }) do
  check(is_park(cell("objects", p[1], p[2])), "falta equipo del parque en objects (" .. p[1] .. "," .. p[2] .. ")")
end
-- los pasos entre los columpios deben ser transitables (la celda del medio no es solida)
check(is_park(cell("objects", 26, 45)), "la celda central de los columpios debe existir (sin solid)")
-- arboles: zona de arboles (cols 11-25, filas 27-38) con troncos en objects y copas en canopy
local trunks = 0 -- gids 129/131/132 = guanacaste/palm/monte_trunk (ids 128/130/131 + 1)
for y = 27, 38 do for x = 11, 25 do local g = cell("objects", x, y); if g == 129 or g == 131 or g == 132 then trunks = trunks + 1 end end end
check(trunks >= 8, "la zona de arboles debe tener arboles (troncos: " .. trunks .. ")")
-- camino de adoquin diagonal: arranca en la acera sur (fila 26) y llega a la esquina NE del skate park
local path_start, path_end = false, false
for x = PARK_X, PARK_X + PARK_W - 1 do
  local g = cell("ground", x, STREET_Y + STREET_W + 1)
  if g == PAVER_A or g == PAVER_B then path_start = true end
end
for y = 39, 42 do local g = cell("ground", 23, y); if g == PAVER_A or g == PAVER_B then path_end = true end end
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
for col = 10, LASTRE_X1, 25 do
  for _, side in ipairs({ "n", "s" }) do
    local skipped = (side == "n" and (col == 35 or col == 310)) or (side == "s" and col == 60) -- camino de la iglesia / cafetal (cerca y pasillo) / acera de la calle oeste
    check((lamp_x[side .. col] == true) == (not skipped), "farola " .. side .. col .. (skipped and " debe omitirse" or " falta"))
    if lamp_x[side .. col] then
      n_lamps = n_lamps + 1
      local y = side == "n" and 19 or 26
      check(cell("objects", col, y) ~= 0, "falta el poste de la farola " .. side .. col)
    end
  end
end
check(n_lamps == 31, "deben ser 31 farolas de calle (17 columnas x 2 lados - 3 omitidas), hay " .. n_lamps)
for x in pairs(lamp_x) do
  local col = tonumber(x:sub(2))
  check((col - 10) % 25 == 0, "farola fuera de la rejilla de 25 tiles: " .. x)
end
local lamps = 0
for _, o in ipairs(of_class("light")) do if o.name:match("^luz_farola_") then lamps = lamps + 1 end end
check(lamps >= 31, "faltan farolas (" .. lamps .. ")")

-- ================================================================ el Chequelo: cafetal, casas, ruta, triggers, emisores
local function gname(layer, x, y) return gid_name[cell(layer, x, y)] end
local function has_prefix(layer, x, y, prefix) local n = gname(layer, x, y); return n ~= nil and n:sub(1, #prefix) == prefix end
local function point_in(r, px, py) return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h end
local function of_name_prefix(prefix)
  local out = {}
  for _, o in ipairs(objects) do if o.name and o.name:sub(1, #prefix) == prefix then out[#out + 1] = o end end
  return out
end

-- ---- el cafetal: 25 tiles (50 m) de ancho, centrado 50 m antes del fin del adoquin (col 334 - 25 = 309), al norte de la calle ----
local CAF_X0, CAF_X1, CAF_Y0, CAF_Y1, GAP0, GAP1 = 297, 321, 5, 18, 308, 309
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
for y = CAF_Y1, STREET_Y - 1 do -- pasillo hasta la acera: lastre y sin objetos
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
local MAMA_X0, MAMA_Y0, MAMA_W, MAMA_H = 423, 27, 8, 6
local CHAYO_X0, CHAYO_Y0, CHAYO_W, CHAYO_H = 399, 27, 6, 5
check((MAMA_X0 + MAMA_W / 2) - (CHAYO_X0 + CHAYO_W / 2) == 25, "la casa de Chayo debe estar 25 tiles (50 m) antes de la de mama, centro a centro")
check(MAMA_X0 + MAMA_W - 1 < LASTRE_X1, "la casa de mama termina antes del fin de la calle (col 434)")
check(MAMA_Y0 >= STREET_Y + STREET_W + 2, "las casas dejan 2 filas de cesped bajo la calle de lastre")
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
  local foot = by_name[name .. "_footprint"]
  check(foot ~= nil and foot.x == ox * 16 and foot.w == w * 16 and foot.h > 0, name .. "_footprint debe cubrir el ancho de la casa")
  local roof = by_name["roof_" .. name]
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
check(route[1][1] == 560 and route[1][2] >= 288 and route[1][2] <= 320, "la ruta empieza en la puerta de la iglesia (560, ~300)")
check(route[2][1] == 560 and route[2][2] == (STREET_Y + STREET_W // 2) * 16, "la ruta baja por el camino de la iglesia hasta el centro de la calle (y=368)")
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
for x = 560, 6928, 16 do check(covered_by(roads, x, 345) and covered_by(roads, x, 391), "road debe cubrir el ancho de la calle en x=" .. x) end
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

-- ---- colisiones: borde del mapa ----
for _, n in ipairs({ "wall_top", "wall_bottom", "wall_left", "wall_right" }) do check(by_name[n] ~= nil, "falta " .. n) end

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("zona1_check OK")
