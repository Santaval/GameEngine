-- Validacion de la hoja del monte (tilesets/monte.{tsx,png}): arboles de hule y nispero, suelo de monte, matorral, el borde y la linea de la carretera,
-- la plataforma y el aerogenerador (torre + rotor animado). Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/monte_check.lua
-- Sin motor: parsea el XML con patrones de cadena (como ebais_check.lua). Convenciones en games/quebrada/docs/monte.md.

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

local MTSX, MPNG = "games/quebrada/tilesets/monte.tsx", "games/quebrada/tilesets/monte.png"
local LAYERS = { ground = true, overlay = true, ysort = true, above = true }
local SURFACES = { lastre = true, zacate = true, madera = true, concreto = true }

local tsx = read_file(MTSX)
local head = tsx:match("<tileset ([^>]*)>")
local tw, th = tonumber(attr(head, "tilewidth")), tonumber(attr(head, "tileheight"))
local columns, tilecount = tonumber(attr(head, "columns")), tonumber(attr(head, "tilecount"))
check(tw == 16 and th == 16, "el tamano de tile debe ser 16x16")
check(columns == 16 and tilecount == 256, "la hoja es de 16 x 16 tiles (256 ids), tiene " .. tostring(columns) .. " columnas y tilecount " .. tostring(tilecount))
local img_w = tonumber(tsx:match('<image source="[^"]*" width="(%d+)"'))
local img_h = tonumber(tsx:match('<image source="[^"]*" width="%d+" height="(%d+)"'))
check(img_w == columns * tw and img_h == math.ceil(tilecount / columns) * th, "tamano de la imagen != columnas/filas del tsx")
check(tsx:match('<image source="monte%.png"') ~= nil, "el tsx debe apuntar a monte.png")
local png = read_file(MPNG)
check(png:sub(1, 8) == "\137PNG\r\n\26\n", "monte.png no tiene firma PNG")
local pw, ph = string.unpack(">I4I4", png, 17)
check(pw == img_w and ph == img_h, "monte.png (" .. pw .. "x" .. ph .. ") no coincide con el tsx")

-- firstgid del mapa = tilecount(town) + tilecount(buildings) + tilecount(park) + tilecount(school) + tilecount(ebais) + 1 (ver games/quebrada/tests/zona1_consts.lua)
local function count_of(path) return tonumber(attr(read_file(path):match("<tileset ([^>]*)>"), "tilecount")) end
local firstgid = 1
for _, n in ipairs({ "town", "buildings", "park", "school", "ebais" }) do firstgid = firstgid + count_of("games/quebrada/tilesets/" .. n .. ".tsx") end
local Z = dofile("games/quebrada/tests/zona1_consts.lua")
check(firstgid == Z.MONTE_FIRSTGID, "firstgid del monte debe ser " .. Z.MONTE_FIRSTGID .. " (zona1_consts.lua), calculado " .. firstgid)
local tmx = read_file("games/quebrada/maps/zona1.tmx")
check(tmx:match('<tileset firstgid="' .. firstgid .. '" source="%.%./tilesets/monte%.tsx"/>') ~= nil, "zona1.tmx debe declarar monte.tsx con firstgid " .. firstgid)

-- nombres de la hoja town (el monte no puede repetirlos: monte_trunk y monte_canopy_* son de town)
local town_names = {}
for body in read_file("games/quebrada/tilesets/town.tsx"):gmatch('<tile id="%d+">(.-)</tile>') do town_names[body:match('name="name" value="([^"]*)"') or ""] = true end

local by_name, by_id, n_tiles, n_anim = {}, {}, 0, 0
for tid, body in tsx:gmatch('<tile id="(%d+)">(.-)</tile>') do
  local t = { id = tonumber(tid), props = {}, frames = {} }
  for name, rest in body:gmatch('<property name="([^"]+)"([^>]*)/>') do
    local v = rest:match('value="([^"]*)"')
    local ty = rest:match('type="([^"]*)"')
    if ty == "bool" then v = (v == "true") elseif ty == "int" then v = tonumber(v) end
    t.props[name] = v
  end
  for fid, dur in body:gmatch('<frame tileid="(%d+)" duration="(%d+)"/>') do t.frames[#t.frames + 1] = { id = tonumber(fid), duration = tonumber(dur) } end
  n_tiles = n_tiles + 1
  local n = t.props.name
  check(n ~= nil and n:match("^monte_") ~= nil, "tile " .. tid .. ": el nombre debe empezar por monte_ (" .. tostring(n) .. ")")
  check(not by_name[n or ""], "nombre repetido: " .. tostring(n))
  check(not town_names[n or ""], "el nombre choca con un tile de town: " .. tostring(n))
  by_name[n or ""] = t
  by_id[t.id] = t
  check(t.id >= 0 and t.id < tilecount, "id fuera del tileset: " .. tid)
  local layer = t.props.layer
  check(LAYERS[layer] == true, "tile " .. tostring(n) .. ": layer invalida " .. tostring(layer))
  if layer == "ground" and not t.props.solid then
    check(SURFACES[t.props.surface] == true, "ground sin surface valida: " .. tostring(n))
  else
    check(t.props.surface == nil, "solo el suelo lleva surface: " .. tostring(n))
  end
  if t.props.solid then check(layer == "ysort", "el monte no tiene agua: solid solo en ysort: " .. tostring(n)) end
  if layer == "above" then check(not t.props.solid, "solid en tile above: " .. tostring(n)) end
  if #t.frames > 0 then n_anim = n_anim + 1 end
end
check(n_tiles > 100, "monte.tsx con pocos tiles (" .. n_tiles .. ")")

for _, n in ipairs({ "monte_grass_a", "monte_grass_b", "monte_grass_c", "monte_litter_a", "monte_litter_b", "monte_mud_a", "monte_mud_b", "monte_road_edge_n", "monte_road_edge_s",
                     "monte_road_line_n", "monte_road_line_s", "monte_pad_a", "monte_pad_b", "monte_fern_a", "monte_fern_b", "monte_bush", "monte_log", "monte_rock_moss",
                     "monte_hule_trunk", "monte_hule_shaft", "monte_nispero_trunk", "monte_rotor_blank" }) do
  check(by_name[n] ~= nil, "falta el tile requerido " .. n)
end
-- suelos: zacate (monte, hojarasca), lastre (barro), concreto (carretera, plataforma); todos transitables
for n, want in pairs({ monte_grass_a = "zacate", monte_grass_b = "zacate", monte_grass_c = "zacate", monte_litter_a = "zacate", monte_litter_b = "zacate", monte_mud_a = "lastre", monte_mud_b = "lastre",
                       monte_road_edge_n = "concreto", monte_road_edge_s = "concreto", monte_road_line_n = "concreto", monte_road_line_s = "concreto", monte_pad_a = "concreto", monte_pad_b = "concreto" }) do
  local t = by_name[n]
  check(t and t.props.layer == "ground" and t.props.surface == want and not t.props.solid, n .. ": ground " .. want .. " transitable")
end
-- sotobosque: helechos transitables (ysort sin solid); matorral, tronco caido y roca solidas (ysort)
for _, n in ipairs({ "monte_fern_a", "monte_fern_b" }) do check(by_name[n] and by_name[n].props.layer == "ysort" and not by_name[n].props.solid, n .. " debe ser ysort y transitable") end
for _, n in ipairs({ "monte_bush", "monte_log", "monte_rock_moss" }) do check(by_name[n] and by_name[n].props.layer == "ysort" and by_name[n].props.solid == true, n .. " debe ser ysort y solid") end
-- arboles: troncos solidos (ysort, sort_offset -2); el fuste del hule y las copas son above y nunca solid
for _, n in ipairs({ "monte_hule_trunk", "monte_nispero_trunk" }) do
  check(by_name[n] and by_name[n].props.layer == "ysort" and by_name[n].props.solid == true and by_name[n].props.sort_offset == -2, n .. ": ysort, solid, sort_offset -2")
end
check(by_name.monte_hule_shaft and by_name.monte_hule_shaft.props.layer == "above" and not by_name.monte_hule_shaft.props.solid, "monte_hule_shaft debe ser above y no solid")
for cy = 0, 2 do for cx = 0, 2 do
  local n = "monte_hule_canopy_" .. cx .. "_" .. cy
  check(by_name[n] and by_name[n].props.layer == "above" and not by_name[n].props.solid, n .. " debe ser above (copa del hule 3x3)")
end end
for cy = 0, 1 do for cx = 0, 2 do
  local n = "monte_nispero_canopy_" .. cx .. "_" .. cy
  check(by_name[n] and by_name[n].props.layer == "above" and not by_name[n].props.solid, n .. " debe ser above (copa del nispero 3x2)")
end end
check(by_name.monte_hule_canopy_0_3 == nil and by_name.monte_nispero_canopy_0_2 == nil, "las copas son 3x3 (hule) y 3x2 (nispero)")
-- torre 1x10: celdas 0 (gondola) a 8 (fuste) above, la 9 (base con la puerta) ysort solid
for cy = 0, 9 do
  local n = "monte_tower_0_" .. cy
  local t = by_name[n]
  check(t ~= nil, "falta " .. n)
  if t then
    if cy == 9 then check(t.props.layer == "ysort" and t.props.solid == true and t.props.sort_offset == -2, n .. ": la base es ysort, solid, sort_offset -2")
    else check(t.props.layer == "above" and not t.props.solid, n .. ": fuste / gondola above y no solid") end
  end
end
check(by_name.monte_tower_0_10 == nil and by_name.monte_tower_1_0 == nil, "la torre es de 1 x 10 celdas")

-- rotor: 9x9 celdas, 4 angulos (0, 30, 60, 90 grados). Anclas monte_rotor_<cx>_<cy> (angulo 0) con <animation> de 4 frames; frames monte_rotor_<cx>_<cy>_f<k>;
-- monte_rotor_blank es el frame vacio. Todo above y sin solid.
local anchors, frames_n = 0, 0
for n, t in pairs(by_name) do
  local cx, cy = n:match("^monte_rotor_(%d+)_(%d+)$")
  local fcx, fcy, k = n:match("^monte_rotor_(%d+)_(%d+)_f(%d+)$")
  if cx then
    anchors = anchors + 1
    check(tonumber(cx) < 9 and tonumber(cy) < 9, n .. ": fuera del rotor 9x9")
    check(t.props.layer == "above" and not t.props.solid and t.props.surface == nil, n .. ": above, no solid")
    check(#t.frames == 4, n .. ": la animacion debe tener 4 frames (angulos 0, 30, 60, 90), tiene " .. #t.frames)
    check(t.frames[1] and t.frames[1].id == t.id, n .. ": el primer frame es el propio tile (angulo 0)")
    for i, fr in ipairs(t.frames) do
      check(fr.duration > 0 and fr.duration <= 1000, n .. ": duracion del frame " .. i .. " fuera de rango (" .. fr.duration .. " ms)")
      local ft = by_id[fr.id]
      check(ft ~= nil and ft.props.layer == "above" and not ft.props.solid, n .. ": el frame " .. i .. " (tileid " .. fr.id .. ") debe existir y ser above")
      if ft and i > 1 then check(ft.props.name == "monte_rotor_blank" or ft.props.name == n .. "_f" .. (i - 1), n .. ": frame " .. i .. " inesperado: " .. tostring(ft.props.name)) end
    end
  elseif fcx then
    frames_n = frames_n + 1
    check(tonumber(k) >= 1 and tonumber(k) <= 3, n .. ": angulo fuera de 1..3")
    check(t.props.layer == "above" and not t.props.solid and #t.frames == 0, n .. ": frame above, sin solid ni animacion")
    check(by_name["monte_rotor_" .. fcx .. "_" .. fcy] ~= nil, n .. ": sin ancla")
  end
end
check(n_anim == anchors, "solo las anclas del rotor llevan <animation> (" .. n_anim .. " animados, " .. anchors .. " anclas)")
check(anchors >= 30 and anchors <= 81, "el rotor 9x9 debe tener entre 30 y 81 celdas no vacias (" .. anchors .. ")")
check(by_name.monte_rotor_4_4 ~= nil, "falta la celda central del rotor (el cubo) monte_rotor_4_4")
check(frames_n >= anchors, "los frames de los otros angulos deben existir (" .. frames_n .. ")")
check(by_name.monte_rotor_blank and #by_name.monte_rotor_blank.frames == 0, "monte_rotor_blank no se anima")

-- el mapa usa el monte: capa rotors (above) y gids >= firstgid
local rotors = tmx:match('<layer id="%d+" name="rotors"[^>]*>(.-)</layer>')
check(rotors ~= nil and rotors:find('name="above" type="bool" value="true"', 1, true) ~= nil, "zona1.tmx debe tener la capa rotors con above=true")

if failures > 0 then
  print(failures .. " fallos")
  os.exit(1)
end
print("monte_check OK")
