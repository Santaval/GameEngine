-- Validacion de los edificios (issue #71): tilesets/buildings.{tsx,png}, maps/buildings_demo.tmx y
-- maps/house_mama.tmx. Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/buildings_check.lua
-- Sin motor: parsea los XML con patrones de cadena (como tileset_check.lua). Convenciones en
-- games/quebrada/docs/buildings.md.

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

local BTSX, BPNG = "games/quebrada/tilesets/buildings.tsx", "games/quebrada/tilesets/buildings.png"
local TTSX = "games/quebrada/tilesets/town.tsx"
local DEMO, HOUSE = "games/quebrada/maps/buildings_demo.tmx", "games/quebrada/maps/house_mama.tmx"
local LAYERS = { ground = true, overlay = true, ysort = true, above = true }

-- ---- tsx ----
local tsx = read_file(BTSX)
local head = tsx:match("<tileset ([^>]*)>")
local tw, th = tonumber(attr(head, "tilewidth")), tonumber(attr(head, "tileheight"))
local columns, tilecount = tonumber(attr(head, "columns")), tonumber(attr(head, "tilecount"))
check(tw == 16 and th == 16, "el tamano de tile debe ser 16x16")
local img_w = tonumber(tsx:match('<image source="[^"]*" width="(%d+)"'))
local img_h = tonumber(tsx:match('<image source="[^"]*" width="%d+" height="(%d+)"'))
check(img_w == columns * tw, "ancho de la imagen del tsx != columnas * tile")
check(img_h == math.ceil(tilecount / columns) * th, "alto de la imagen del tsx != filas * tile")
check(tsx:match('<image source="buildings%.png"') ~= nil, "el tsx debe apuntar a buildings.png")

local png = read_file(BPNG)
check(png:sub(1, 8) == "\137PNG\r\n\26\n", "buildings.png no tiene firma PNG")
local pw, ph = string.unpack(">I4I4", png, 17)
check(pw == img_w and ph == img_h, "buildings.png (" .. pw .. "x" .. ph .. ") no coincide con el tsx (" .. img_w .. "x" .. img_h .. ")")

-- town.tsx: solo se necesita el tilecount para el firstgid del segundo tileset
local town_head = read_file(TTSX):match("<tileset ([^>]*)>")
local town_count = tonumber(attr(town_head, "tilecount"))

-- ---- tiles ----
local tiles, by_name = {}, {}
local by_prefix = {}
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
  check(t.props.surface == nil, "tile de edificio con surface: " .. tostring(n) .. " (el suelo da la superficie)")
  if layer == "above" then check(not t.props.solid, "solid en tile above: " .. tostring(n) .. " (usar rects de collision)") end
  if t.props.solid then check(layer == "ysort", "solid solo en ysort: " .. tostring(n)) end
  if n and n:match("_lit_%d+_%d+$") then
    check(layer == "ysort" and t.props.sort_offset ~= nil, "tile encendido " .. n .. " debe ser ysort con sort_offset")
  end
  local prefix = n and n:match("^(iglesia)_") or n and n:match("^(casa_mama)_") or n and n:match("^(casa_[123])_")
  if prefix then by_prefix[prefix] = (by_prefix[prefix] or 0) + 1 end
end
for _, p in ipairs({ "iglesia", "casa_mama", "casa_1", "casa_2", "casa_3" }) do
  check((by_prefix[p] or 0) > 0, "faltan tiles " .. p .. "_*")
end
for _, n in ipairs({ "iglesia_0_0", "iglesia_4_11", "casa_mama_0_0", "casa_mama_5_5", "casa_1_2_3", "casa_2_2_3", "casa_3_2_3",
                     "casa_mama_wall_0", "casa_mama_wall_11", "hedge_burgundy", "hedge_lime" }) do
  -- (iglesia_0_0 es transparente en la esquina: se acepta que no exista, pero los demas deben estar)
  if n ~= "iglesia_0_0" and n ~= "casa_mama_0_0" then check(by_name[n] ~= nil, "falta el tile requerido " .. n) end
end
for _, t in pairs(by_name) do
  local n = t.props.name
  if n:match("^casa_mama_wall_") then check(t.props.solid == true and t.props.layer == "ysort", n .. " debe ser ysort y solid") end
  if n:match("^casa_mama_int_") then check(t.props.layer == "ysort" and not t.props.solid, n .. " debe ser ysort sin solid") end
end
-- las celdas del porche son transitables
for _, n in ipairs({ "casa_mama_6_5", "casa_mama_7_5" }) do
  check(by_name[n] and not by_name[n].props.solid, n .. " (porche) no debe ser solid")
end

-- ---- mapas ----
local FIRSTGID_B = town_count + 1

local function parse_map(path, expect_tileset_lines)
  local tmx = read_file(path)
  local mh = tmx:match("<map ([^>]*)>")
  local map_w, map_h = tonumber(attr(mh, "width")), tonumber(attr(mh, "height"))
  check(tonumber(attr(mh, "tilewidth")) == tw, path .. ": tilewidth != tileset")
  check(tmx:match('<tileset firstgid="1" source="%.%./tilesets/town%.tsx"/>') ~= nil, path .. ": falta el tileset town (firstgid 1)")
  check(tmx:match('<tileset firstgid="' .. FIRSTGID_B .. '" source="%.%./tilesets/buildings%.tsx"/>') ~= nil,
    path .. ": falta el tileset buildings con firstgid " .. FIRSTGID_B)
  local layers = {}
  for lname, lbody in tmx:gmatch('<layer id="%d+" name="([^"]+)"[^>]*>(.-)</layer>') do
    local data = {}
    local csv = lbody:match("<data[^>]*>(.-)</data>")
    for n in csv:gmatch("%d+") do data[#data + 1] = tonumber(n) end
    check(#data == map_w * map_h, path .. ": capa " .. lname .. " con " .. #data .. " celdas, esperadas " .. map_w * map_h)
    local props = {}
    for k, v in lbody:gmatch('<property name="([^"]+)"[^>]-value="([^"]*)"') do props[k] = v end
    layers[lname] = { data = data, props = props }
  end
  return tmx, layers, map_w, map_h
end

local function tile_of(gid)
  if gid == 0 then return nil end
  gid = gid & 0x1FFFFFFF
  if gid >= FIRSTGID_B then return tiles[gid - FIRSTGID_B], "buildings" end
  return nil, "town"
end

local function resolves(path, layers)
  for lname, l in pairs(layers) do
    for i, gid in ipairs(l.data) do
      if gid ~= 0 then
        local g = gid & 0x1FFFFFFF
        if g >= FIRSTGID_B then
          check(tiles[g - FIRSTGID_B] ~= nil, path .. ": " .. lname .. " celda " .. (i - 1) .. " con gid sin tile (" .. g .. ")")
        else
          check(g >= 1 and g <= town_count, path .. ": " .. lname .. " celda " .. (i - 1) .. " fuera del tileset town (" .. g .. ")")
        end
      end
    end
  end
end

-- buildings_demo.tmx
local tmx, layers = parse_map(DEMO)
resolves(DEMO, layers)
check(layers.buildings and layers.buildings.props.ysort == "true", "la capa buildings debe tener ysort=true")
check(layers.windows_lit ~= nil, "falta la capa windows_lit")
check(layers.windows_lit and layers.windows_lit.props.ysort == "true", "windows_lit debe ser ysort")
check(layers.canopy and layers.canopy.props.above == "true", "canopy debe ser above")
local roof_layers = {}
for lname, l in pairs(layers) do
  if lname:match("^roof_") then
    roof_layers[lname:sub(6)] = true
    check(l.props.above == "true", DEMO .. ": " .. lname .. " debe tener above=true")
    check(l.props.roof_of ~= nil and l.props.roof_of ~= "", DEMO .. ": " .. lname .. " sin roof_of")
    check(l.props.roof_of == lname:sub(6), DEMO .. ": " .. lname .. " roof_of distinto del nombre")
    for i, gid in ipairs(l.data) do
      local t = tile_of(gid)
      if gid ~= 0 then check(t and t.props.layer == "above", lname .. " celda " .. (i - 1) .. " debe ser above") end
    end
  end
end
for i, gid in ipairs(layers.buildings.data) do
  local t = tile_of(gid)
  if gid ~= 0 then check(t and t.props.layer == "ysort", "buildings celda " .. (i - 1) .. " debe ser ysort") end
end
for i, gid in ipairs(layers.windows_lit.data) do
  local t = tile_of(gid)
  if gid ~= 0 then check(t and t.props.name:match("_lit_") ~= nil, "windows_lit celda " .. (i - 1) .. " debe ser un tile _lit_") end
end
local placed = {}
for _, gid in ipairs(layers.buildings.data) do
  local t = tile_of(gid)
  if t then placed[t.props.name:match("^(iglesia)_") or t.props.name:match("^(casa_mama)_") or t.props.name:match("^(casa_[123])_") or "?"] = true end
end
for _, p in ipairs({ "iglesia", "casa_mama", "casa_1", "casa_2", "casa_3" }) do
  check(placed[p], "el demo no coloca " .. p)
  check(roof_layers[p], "falta la capa roof_" .. p)
end
-- cada objeto class roof apunta a una capa roof_*
local n_roofs = 0
for body in tmx:gmatch('<object [^>]-class="roof"[^>]*>(.-)</object>') do
  n_roofs = n_roofs + 1
  local of = body:match('<property name="roof_of"[^>]-value="([^"]*)"')
  check(of ~= nil and roof_layers[of], "objeto roof con roof_of sin capa: " .. tostring(of))
end
check(n_roofs >= 5, "faltan objetos roof (" .. n_roofs .. ")")
check(tmx:match('name="door_mama"') ~= nil and tmx:match('value="maps/house_mama%.tmx"') ~= nil, "falta door_mama hacia house_mama.tmx")
check(tmx:match('name="exit_mama"') ~= nil and tmx:match('name="default"') ~= nil, "faltan los spawns default / exit_mama")
check(tmx:match('name="iglesia_puerta"') ~= nil, "falta iglesia_puerta")
for _, b in ipairs({ "iglesia", "casa_mama", "casa_1", "casa_2", "casa_3" }) do
  check(tmx:match('name="' .. b .. '_footprint"') ~= nil, "falta el rect de colision " .. b .. "_footprint")
end

-- house_mama.tmx (generado, mantiene ids y nombres de #62)
local htmx, hl = parse_map(HOUSE)
resolves(HOUSE, hl)
for _, n in ipairs({ "floor", "walls", "furniture" }) do check(hl[n] ~= nil, HOUSE .. ": falta la capa " .. n) end
check(hl.walls and hl.walls.props.ysort == "true" and hl.furniture and hl.furniture.props.ysort == "true", HOUSE .. ": walls y furniture ysort")
check(htmx:match('<property name="surface" value="madera"/>') ~= nil, HOUSE .. ": falta surface=madera del mapa")
local REQ = {
  { 10, "door_out" }, { 15, "inside_door" }, { 20, "mama" }, { 21, "radio" }, { 22, "cama" }, { 23, "cargador" },
  { 24, "linterna" }, { 16, "zone_casa_mama" }, { 5, "mesa" }, { 1, "wall_top" }, { 2, "wall_bottom" }, { 3, "wall_left" },
  { 4, "wall_right" }, { 25, "seat_mama" },
}
for _, r in ipairs(REQ) do
  check(htmx:match('<object id="' .. r[1] .. '" name="' .. r[2] .. '"') ~= nil, HOUSE .. ": falta el objeto " .. r[1] .. " " .. r[2])
end
for _, g in ipairs({ "collision", "doors", "spawns", "zones", "interactables", "seats" }) do
  check(htmx:match('<objectgroup id="%d+" name="' .. g .. '"') ~= nil, HOUSE .. ": falta el grupo " .. g)
end
check(htmx:match('name="mama"[^>]*>%s*<properties>.-<property name="story" value="chequelo"/>') ~= nil, HOUSE .. ": mama pierde story=chequelo")
check(htmx:match('<property name="sleep" type="bool" value="true"/>') ~= nil, HOUSE .. ": cama pierde sleep")
check(htmx:match('<property name="target_map" value="@return"/>') ~= nil, HOUSE .. ": door_out pierde @return")
check(htmx:match('name="seat_mama" class="seat"') ~= nil, HOUSE .. ": seat_mama sin class seat")
-- ids de objeto unicos y nextobjectid mayor que todos
local max_id, seen = 0, {}
for oid in htmx:gmatch('<object id="(%d+)"') do
  oid = tonumber(oid)
  check(not seen[oid], HOUSE .. ": id de objeto repetido " .. oid)
  seen[oid] = true
  if oid > max_id then max_id = oid end
end
check(tonumber(attr(htmx:match("<map ([^>]*)>"), "nextobjectid")) > max_id, HOUSE .. ": nextobjectid debe ser mayor que " .. max_id)

-- house_paula.tmx (generado): la casa de madera de Abuela Paula y Abuelo Pepe, 16x11 tiles
do
  local PAULA = "games/quebrada/maps/house_paula.tmx"
  local ptmx, pl = parse_map(PAULA)
  resolves(PAULA, pl)
  for _, n in ipairs({ "floor", "walls", "furniture" }) do check(pl[n] ~= nil, PAULA .. ": falta la capa " .. n) end
  check(pl.walls and pl.walls.props.ysort == "true" and pl.furniture and pl.furniture.props.ysort == "true", PAULA .. ": walls y furniture ysort")
  check(ptmx:match('<property name="surface" value="madera"/>') ~= nil, PAULA .. ": falta surface=madera del mapa")
  local pw_, ph_ = tonumber(attr(ptmx:match("<map ([^>]*)>"), "width")), tonumber(attr(ptmx:match("<map ([^>]*)>"), "height"))
  check(pw_ == 16 and ph_ == 11, PAULA .. ": debe medir 16x11 tiles (" .. tostring(pw_) .. "x" .. tostring(ph_) .. ")")
  for _, r in ipairs({ { 10, "door_out" }, { 15, "inside_door" }, { 20, "abuela" }, { 21, "abuelo" }, { 22, "fogon" }, { 16, "zone_casa_paula" }, { 5, "mesa" },
                       { 1, "wall_top" }, { 2, "wall_bottom" }, { 3, "wall_left" }, { 4, "wall_right" }, { 30, "seat_abuela" }, { 31, "seat_abuelo" } }) do
    check(ptmx:match('<object id="' .. r[1] .. '" name="' .. r[2] .. '"') ~= nil, PAULA .. ": falta el objeto " .. r[1] .. " " .. r[2])
  end
  for _, g in ipairs({ "collision", "doors", "spawns", "zones", "interactables", "seats" }) do
    check(ptmx:match('<objectgroup id="%d+" name="' .. g .. '"') ~= nil, PAULA .. ": falta el grupo " .. g)
  end
  check(ptmx:match('<property name="target_map" value="@return"/>') ~= nil, PAULA .. ": door_out pierde @return")
  check(ptmx:match('<property name="npc" value="abuela_paula"/>') ~= nil and ptmx:match('<property name="npc" value="abuelo_pepe"/>') ~= nil, PAULA .. ": faltan los npc abuela_paula / abuelo_pepe")
  check(ptmx:match('<property name="ambience" value="casa"/>') ~= nil, PAULA .. ": la zona debe tener ambience=casa")
  check(ptmx:match('name="cama"[^>]*>%s*<properties>[^<]*<property name="interact"[^>]*/>%s*<property name="label"[^>]*/>%s*<property name="line"') ~= nil, PAULA .. ": la cama solo se mira (sin sleep)")
  local max_id_, seen_ = 0, {}
  for oid in ptmx:gmatch('<object id="(%d+)"') do
    oid = tonumber(oid)
    check(not seen_[oid], PAULA .. ": id de objeto repetido " .. oid)
    seen_[oid] = true
    if oid > max_id_ then max_id_ = oid end
  end
  check(tonumber(attr(ptmx:match("<map ([^>]*)>"), "nextobjectid")) > max_id_, PAULA .. ": nextobjectid debe ser mayor que " .. max_id_)
  -- tiles del interior: muro de madera solido y ysort (2 filas x 16), muebles ysort sin solid
  local n_wall, n_int = 0, 0
  for _, t in pairs(by_name) do
    local n = t.props.name
    if n:match("^casa_paula_wall_%d+_%d+$") then n_wall = n_wall + 1; check(t.props.solid == true and t.props.layer == "ysort", n .. " debe ser ysort y solid") end
    if n:match("^casa_paula_int_") then n_int = n_int + 1; check(t.props.layer == "ysort" and not t.props.solid, n .. " debe ser ysort sin solid") end
  end
  check(n_wall == 32, "el muro de la casa de Paula debe tener 32 celdas (16x2), tiene " .. n_wall)
  check(n_int >= 30 and n_int <= 96, "los muebles de la casa de Paula deben ser entre 30 y 96 celdas, hay " .. n_int)
  check(by_name.casa_paula_wall_0_0 ~= nil and by_name.casa_paula_wall_15_1 ~= nil, "faltan las esquinas del muro de la casa de Paula")
end

if failures > 0 then
  print(failures .. " fallo(s) en buildings_check")
  os.exit(1)
end
print("buildings_check OK (" .. tilecount .. " ids)")
