-- Validacion del tileset del pueblo (issue #55): tilesets/town.tsx, tilesets/town.png y maps/tiles_demo.tmx.
-- Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/tileset_check.lua
-- Sin motor: parsea los XML con patrones de cadena. Convenciones en games/quebrada/docs/tileset.md.

package.path = "./games/quebrada/scripts/?.lua;" .. package.path

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

local surfaces = require("surface_logic")

local TSX, PNG, TMX = "games/quebrada/tilesets/town.tsx", "games/quebrada/tilesets/town.png", "games/quebrada/maps/tiles_demo.tmx"
local LAYERS = { ground = true, overlay = true, ysort = true, above = true }

-- ---- tsx ----
local tsx = read_file(TSX)
local head = tsx:match("<tileset ([^>]*)>")
local function attr(s, name) return s:match(name .. '="([^"]*)"') end
local tw, th = tonumber(attr(head, "tilewidth")), tonumber(attr(head, "tileheight"))
local columns, tilecount = tonumber(attr(head, "columns")), tonumber(attr(head, "tilecount"))
check(tw == 16 and th == 16, "el tamano de tile debe ser 16x16")
local img_w, img_h = tonumber(tsx:match('<image source="[^"]*" width="(%d+)"')), tonumber(tsx:match('<image source="[^"]*" width="%d+" height="(%d+)"'))
check(img_w == columns * tw, "ancho de la imagen del tsx != columnas * tile")
check(img_h == math.ceil(tilecount / columns) * th, "alto de la imagen del tsx != filas * tile")

-- ---- png ----
local png = read_file(PNG)
check(png:sub(1, 8) == "\137PNG\r\n\26\n", "town.png no tiene firma PNG")
local pw, ph = string.unpack(">I4I4", png, 17)
check(pw == img_w and ph == img_h, "town.png (" .. pw .. "x" .. ph .. ") no coincide con el tsx (" .. img_w .. "x" .. img_h .. ")")

-- ---- tiles ----
local tiles, by_name = {}, {}
for id, body in tsx:gmatch('<tile id="(%d+)">(.-)</tile>') do
  local t = { id = tonumber(id), props = {} }
  for name, rest in body:gmatch('<property name="([^"]+)"([^>]*)/>') do
    local v = rest:match('value="([^"]*)"')
    local ty = rest:match('type="([^"]*)"')
    if ty == "bool" then v = (v == "true") elseif ty == "int" then v = tonumber(v) end
    t.props[name] = v
  end
  tiles[t.id] = t
  local n = t.props.name
  check(n ~= nil and n ~= "", "tile " .. id .. " sin nombre")
  check(not by_name[n or ""], "nombre repetido: " .. tostring(n))
  by_name[n or ""] = t
  check(t.id >= 0 and t.id < tilecount, "id fuera del tileset: " .. id)
  local layer = t.props.layer
  check(LAYERS[layer] == true, "tile " .. tostring(n) .. ": layer invalida " .. tostring(layer))
  local s = t.props.surface
  if layer == "ground" and not t.props.solid then
    check(type(s) == "string" and surfaces.STEPS[s] ~= nil, "tile de suelo transitable sin surface valida: " .. tostring(n) .. " (" .. tostring(s) .. ")")
  end
  if layer ~= "ground" then
    check(s == nil, "tile " .. tostring(n) .. " (" .. tostring(layer) .. ") no debe tener surface")
  end
  if t.props.solid then
    check(layer == "ground" or layer == "ysort", "solid solo en ground (agua) o ysort: " .. tostring(n))
  end
  if s ~= nil then check(surfaces.STEPS[s] ~= nil, "surface desconocida en " .. tostring(n) .. ": " .. tostring(s)) end
end

-- nombres que el demo y la documentacion dan por existentes
local REQUIRED = {
  "grass_a", "grass_d", "lastre_a", "lastre_ruts_v", "lastre_edge_n", "lastre_outer_nw", "lastre_inner_se",
  "asphalt_a", "asphalt_line_h", "sidewalk_a", "paver_a", "gutter_h", "drain", "seam_asphalt_w",
  "water_a", "bank_e", "wire_h", "wire_v", "wire_corner_es", "chainlink_h", "hedge",
  "guanacaste_canopy_1_1", "platano_canopy_1_0", "palm_canopy_2_1", "monte_canopy_0_0", "poste_head_top",
  "guanacaste_trunk", "platano_stem", "palm_trunk", "monte_trunk", "poste_base", "cafeto_a", "shadow_blob", "plank_h",
}
for _, n in ipairs(REQUIRED) do check(by_name[n] ~= nil, "falta el tile requerido " .. n) end
for _, kind in ipairs({ "guanacaste", "platano", "palm", "monte" }) do
  for cy = 0, 1 do for cx = 0, 2 do
    local t = by_name[kind .. "_canopy_" .. cx .. "_" .. cy]
    check(t and t.props.layer == "above", kind .. " canopy " .. cx .. "," .. cy .. " debe ser above")
  end end
end
for _, n in ipairs({ "guanacaste_trunk", "platano_stem", "palm_trunk", "monte_trunk", "poste_base" }) do
  local t = by_name[n]
  check(t and t.props.layer == "ysort" and t.props.solid == true, n .. " debe ser ysort y solid")
  check(t and t.props.sort_offset ~= nil, n .. " debe tener sort_offset")
end
for _, n in ipairs({ "water_a", "water_b", "water_ripple" }) do
  check(by_name[n] and by_name[n].props.solid == true and by_name[n].props.surface == nil, n .. " debe ser solid sin surface")
end

-- ---- tmx ----
local tmx = read_file(TMX)
local firstgid = tonumber(tmx:match('<tileset firstgid="(%d+)"'))
check(firstgid ~= nil, "el tmx no declara firstgid")
check(tmx:match('<tileset firstgid="%d+" source="%.%./tilesets/town%.tsx"') ~= nil, "el tmx debe apuntar a ../tilesets/town.tsx")
local map_w, map_h = tonumber(attr(tmx:match("<map ([^>]*)>"), "width")), tonumber(attr(tmx:match("<map ([^>]*)>"), "height"))
check(tonumber(attr(tmx:match("<map ([^>]*)>"), "tilewidth")) == tw, "tilewidth del mapa != tileset")

local function tile_of(gid)
  if gid == 0 then return nil end
  gid = gid & 0x1FFFFFFF
  return tiles[gid - firstgid]
end

local layers = {}
for lname, lbody in tmx:gmatch('<layer id="%d+" name="([^"]+)"[^>]*>(.-)</layer>') do
  local data = {}
  local csv = lbody:match("<data[^>]*>(.-)</data>")
  for n in csv:gmatch("%d+") do data[#data + 1] = tonumber(n) end
  check(#data == map_w * map_h, "capa " .. lname .. ": " .. #data .. " celdas, esperadas " .. map_w * map_h)
  local props = {}
  for k, v in lbody:gmatch('<property name="([^"]+)"[^>]-value="([^"]*)"') do props[k] = v end
  layers[lname] = { data = data, props = props }
end
for _, n in ipairs({ "ground", "overlay", "objects", "canopy" }) do check(layers[n] ~= nil, "falta la capa " .. n) end
check(layers.objects and layers.objects.props.ysort == "true", "la capa objects debe tener ysort=true")
check(layers.canopy and layers.canopy.props.above == "true", "la capa canopy debe tener above=true")
check(layers.ground and layers.ground.props.ysort == nil and layers.ground.props.above == nil, "ground debe ser plana")

local walkable = 0
for i, gid in ipairs(layers.ground.data) do
  local t = tile_of(gid)
  check(t ~= nil, "ground celda " .. (i - 1) .. " vacia o con gid desconocido")
  if t then
    check(t.props.layer == "ground", "ground celda " .. (i - 1) .. ": " .. t.props.name .. " no es de suelo")
    if not t.props.solid then
      walkable = walkable + 1
      check(t.props.surface ~= nil, "ground celda " .. (i - 1) .. " transitable sin surface")
    end
  end
end
check(walkable > 0, "el demo no tiene suelo transitable")
local function layer_hint(name, hint)
  for i, gid in ipairs(layers[name].data) do
    local t = tile_of(gid)
    if gid ~= 0 then
      check(t ~= nil and t.props.layer == hint, name .. " celda " .. (i - 1) .. ": " .. tostring(t and t.props.name) .. " debe ser " .. hint)
    end
  end
end
layer_hint("canopy", "above")
layer_hint("objects", "ysort")
layer_hint("overlay", "overlay")

-- ---- surface_at sobre el mapa de prueba ----
local ts = { firstgid = firstgid, tiles = {} }
for id, t in pairs(tiles) do ts.tiles[id] = { properties = t.props } end
local fake = {
  tilewidth = tw, tileheight = th,
  tilesets = { ts },
  layers = {
    { kind = "tile", name = "ground", width = map_w, height = map_h, data = layers.ground.data },
    { kind = "tile", name = "overlay", width = map_w, height = map_h, data = layers.overlay.data },
    { kind = "tile", name = "objects", width = map_w, height = map_h, data = layers.objects.data },
    { kind = "tile", name = "canopy", width = map_w, height = map_h, data = layers.canopy.data },
  },
  objects = {},
}
local idx = surfaces.build(fake)
local function surface_of_cell(cx, cy) return surfaces.surface_at(idx, cx * tw + 8, cy * th + 8) end
check(surface_of_cell(0, 0) == "zacate", "(0,0) debe ser zacate, es " .. tostring(surface_of_cell(0, 0)))
check(surface_of_cell(10, 14) == "concreto", "la calle (10,14) debe ser concreto, es " .. tostring(surface_of_cell(10, 14)))
check(surface_of_cell(30, 5) == "lastre", "el camino (30,5) debe ser lastre, es " .. tostring(surface_of_cell(30, 5)))
check(surface_of_cell(13, 20) == "madera", "las tablas (13,20) deben ser madera, es " .. tostring(surface_of_cell(13, 20)))
-- bajo una copa (above) no cambia la superficie: sigue la del suelo
check(surface_of_cell(8, 7) == "zacate", "bajo la copa (8,7) sigue siendo zacate, es " .. tostring(surface_of_cell(8, 7)))

if failures > 0 then
  print(failures .. " fallo(s) en tileset_check")
  os.exit(1)
end
print("tileset_check OK (" .. tilecount .. " ids, " .. walkable .. " celdas transitables)")
