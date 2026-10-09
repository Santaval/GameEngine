-- =====================================================================
--  HUD de navegacion del sistema solar (entidad director, solo script):
--  minimapa abajo a la derecha con el Sol, los planetas (color segun su
--  mineral), los cinturones y la nave, y el nombre de cada planeta en el
--  mundo debajo de su cuerpo. En la Aval Cup (scene_map ~= nil) el minimapa
--  cubre el mundo cuadrado y dibuja el bioma de cada sector (map_biomes), la
--  rejilla de sectores y la franja de tormenta en vez de los cinturones.
-- =====================================================================

local solar = require("solar_system_config")
local ui = require("ui_helpers")
local grid = require("map_grid")
local nebula = require("map_nebula")
local storm = require("map_storm")

local MAP_SIZE = 220
local MARGIN = 20
-- La parte de abajo de la pantalla la usan los avisos de mineria / gravedad
local BOTTOM_MARGIN = 120

local MINERAL_COLORS = {
  iron = { 190, 190, 200 },
  gunpowder = { 255, 150, 50 },
  plasma = { 200, 110, 255 },
}
local SUN_COLOR = { 255, 210, 80 }
local BELT_COLOR = { 130, 120, 100 }
local PLAYER_COLOR = { 255, 255, 0 }
local OTHER_COLOR = { 255, 90, 90 }
local SECTOR_LINE_COLOR = { 255, 255, 255, 45 }
local STORM_COLOR = { 150, 30, 60, 200 }
local REACTOR_COLOR = { 255, 225, 170 }
local PORTAL_COLOR = { 123, 44, 191 }
local PORTAL_GLOW = { 199, 125, 255 }

local BELT_DOTS = 72
-- Tamano de un punto de planeta en el minimapa: px de mundo por px de punto,
-- con un minimo para que los planetas chicos se vean
local MIN_DOT = 3
local MAX_DOT = 10

-- Ancho aproximado de un caracter de DejaVuSansMono 16 (para centrar texto)
local CHAR_WIDTH = 10
-- Separacion entre la superficie del planeta y su nombre
local LABEL_GAP = 16

local belt_points = nil
local toggle_pvp_pressed = ui.edge("toggle_pvp")

local function color_for(planet)
  if planet.mineral == nil then return SUN_COLOR end
  return MINERAL_COLORS[planet.mineral] or { 255, 255, 255 }
end

-- Escala del minimapa (px de pantalla por px de mundo) y el punto del mundo
-- que cae en su esquina sup-izq: el cuadrado del mundo en la Aval Cup, el
-- cuadrado que circunscribe al sistema solar en el resto
local function map_frame()
  if scene_map ~= nil then
    return MAP_SIZE / scene_map.WORLD_SIZE, 0, 0
  end
  return MAP_SIZE / (2 * solar.MAP_RADIUS),
         solar.SUN_CENTER.x - solar.MAP_RADIUS,
         solar.SUN_CENTER.y - solar.MAP_RADIUS
end

-- Mundo -> pantalla del minimapa (ox, oy es la esquina del minimapa)
local function to_map(x, y, ox, oy)
  local k, x0, y0 = map_frame()
  return ox + (x - x0) * k, oy + (y - y0) * k
end

local function build_belt_points()
  local list = {}
  for _, belt in ipairs(solar.BELTS) do
    local r = (belt.inner + belt.outer) / 2
    for i = 0, BELT_DOTS - 1 do
      local a = i * 2 * math.pi / BELT_DOTS
      list[#list + 1] = { x = solar.SUN_CENTER.x + r * math.cos(a), y = solar.SUN_CENTER.y + r * math.sin(a) }
    end
  end
  return list
end

-- Tinte de cada sector segun su bioma (map_biomes, lo fija aval_cup_world)
local function draw_biome_tints(ox, oy, k)
  local size = scene_map.SECTOR_SIZE * k
  for sx = 0, scene_map.SECTORS - 1 do
    for sy = 0, scene_map.SECTORS - 1 do
      local c = scene_map.BIOME_COLORS[map_biomes[sx][sy]]
      if c ~= nil then
        draw_rect(ox + sx * size, oy + sy * size, size, size, c[1], c[2], c[3], 90)
      end
    end
  end
end

-- Rejilla de sectores (4 lineas verticales y 4 horizontales interiores, con 1 px
-- de margen en los bordes) y la franja de tormenta del borde del mundo
local function draw_sector_grid(ox, oy, k)
  local sectors = scene_map.SECTORS
  local c = SECTOR_LINE_COLOR
  for i = 1, sectors - 1 do
    local pos = i * scene_map.SECTOR_SIZE * k
    draw_rect(ox + pos, oy + 1, 1, MAP_SIZE - 2, c[1], c[2], c[3], c[4])
    draw_rect(ox + 1, oy + pos, MAP_SIZE - 2, 1, c[1], c[2], c[3], c[4])
  end

  local inset = scene_map.STORM_BAND * k
  local s = STORM_COLOR
  draw_rect(ox + inset, oy + inset, MAP_SIZE - 2 * inset, MAP_SIZE - 2 * inset, s[1], s[2], s[3], s[4], false)
end

local function draw_minimap(planets)
  local w, h = get_screen_size()
  local ox, oy = w - MAP_SIZE - MARGIN, h - MAP_SIZE - BOTTOM_MARGIN

  draw_rect(ox, oy, MAP_SIZE, MAP_SIZE, 0, 0, 0, 170)
  draw_rect(ox, oy, MAP_SIZE, MAP_SIZE, 255, 255, 255, 120, false)

  local k = map_frame()

  if scene_map ~= nil then
    if map_biomes ~= nil then draw_biome_tints(ox, oy, k) end
    draw_sector_grid(ox, oy, k)
  else
    for _, p in ipairs(belt_points) do
      local mx, my = to_map(p.x, p.y, ox, oy)
      draw_rect(mx - 1, my - 1, 2, 2, BELT_COLOR[1], BELT_COLOR[2], BELT_COLOR[3], 160)
    end
  end
  -- Megaestructuras del reactor (reactor_sites, lo fija map_reactor_world)
  if scene_map ~= nil and reactor_sites ~= nil then
    for _, site in ipairs(reactor_sites) do
      local mx, my = to_map(site.x, site.y, ox, oy)
      draw_rect(mx - 3, my - 3, 6, 6, REACTOR_COLOR[1], REACTOR_COLOR[2], REACTOR_COLOR[3], 255, false)
      draw_rect(mx - 1, my - 1, 2, 2, REACTOR_COLOR[1], REACTOR_COLOR[2], REACTOR_COLOR[3], 255)
    end
  end
  -- Tormentas errantes (wandering_storms, lo llena wandering_storm.lua)
  if scene_map ~= nil and wandering_storms ~= nil then
    local icon = scene_map.WANDERING_STORM.icon_size
    local s = STORM_COLOR
    for _, w in ipairs(storm.wandering()) do
      local mx, my = to_map(w.x, w.y, ox, oy)
      local rr = w.r * k
      draw_rect(mx - rr, my - rr, rr * 2, rr * 2, s[1], s[2], s[3], 140, false)
      draw_image("icon-storm", mx - icon / 2, my - icon / 2, icon, icon, 255, "hud")
    end
  end
  -- Portales estables (portal_sites, lo fija map_portal_world): icono violeta
  -- y el numero del par, igual en los dos extremos
  if scene_map ~= nil and portal_sites ~= nil then
    local icon = scene_map.PORTAL.icon_size
    for _, e in ipairs(portal_sites.ends) do
      -- Un par que colapsa (#23) parpadea
      local col = portal_sites.collapsing and portal_sites.collapsing[e.pair]
      if col == nil or math.floor(col.t * 4) % 2 == 0 then
        local mx, my = to_map(e.x, e.y, ox, oy)
        draw_rect(mx - icon / 2, my - icon / 2, icon, icon, PORTAL_COLOR[1], PORTAL_COLOR[2], PORTAL_COLOR[3], 255)
        draw_rect(mx - icon / 2, my - icon / 2, icon, icon, PORTAL_GLOW[1], PORTAL_GLOW[2], PORTAL_GLOW[3], 255, false)
        draw_text(mx + icon / 2 + 1, my - 6, tostring(e.pair), "small", PORTAL_GLOW[1], PORTAL_GLOW[2], PORTAL_GLOW[3], 255)
      end
    end
    -- Nexus (#23): solo el, sin sus salidas
    local n = portal_sites.nexus
    if n ~= nil then
      local nsize = scene_map.NEXUS.icon_size
      local mx, my = to_map(n.x, n.y, ox, oy)
      draw_image("icon-nexus", mx - nsize / 2, my - nsize / 2, nsize, nsize, 255, "hud")
    end
    -- Portales inestables vivos (unstable_portals, los llena unstable_portal.lua)
    if unstable_portals ~= nil then
      local usize = scene_map.UNSTABLE_PORTAL.icon_size
      for _, u in pairs(unstable_portals) do
        if u.life > 0 then
          local mx, my = to_map(u.x, u.y, ox, oy)
          draw_image("icon-portal-unstable", mx - usize / 2, my - usize / 2, usize, usize, 255, "hud")
        end
      end
    end
  end
  for _, p in ipairs(planets) do
    local mx, my = to_map(p.x, p.y, ox, oy)
    local dot = math.max(MIN_DOT, math.min(MAX_DOT, p.body_radius * 2 * k * 4))
    local c = color_for(p)
    draw_rect(mx - dot / 2, my - dot / 2, dot, dot, c[1], c[2], c[3], 255)
  end

  -- Otras naves: las que estan dentro de una nebulosa no aparecen
  if player_ships ~= nil then
    for id in pairs(player_ships) do
      local e = find_by_net_id(id)
      if e ~= nil and is_alive(e) then
        local ex, ey = get_collider_center(e)
        if map_biomes == nil or not nebula.inside(map_seed, map_biomes, ex, ey) then
          local mx, my = to_map(ex, ey, ox, oy)
          draw_rect(mx - 1.5, my - 1.5, 3, 3, OTHER_COLOR[1], OTHER_COLOR[2], OTHER_COLOR[3], 255)
        end
      end
    end
  end

  if player_entity ~= nil and is_alive(player_entity) then
    local px, py = get_collider_center(player_entity)
    local mx, my = to_map(px, py, ox, oy)
    draw_rect(mx - 2, my - 2, 4, 4, PLAYER_COLOR[1], PLAYER_COLOR[2], PLAYER_COLOR[3], 255)

    -- Lo que entra en pantalla, como recuadro
    local cw, ch = w * k, h * k
    draw_rect(mx - cw / 2, my - ch / 2, cw, ch, 255, 255, 255, 90, false)
  end
end

-- Nombre del planeta mas cercano y a cuanto esta (sobre el minimapa)
local function draw_nearest(planets)
  if player_entity == nil or not is_alive(player_entity) then return end
  local px, py = get_collider_center(player_entity)

  -- Sin planetas (Aval Cup) se muestra el sector actual
  if scene_map ~= nil and #planets == 0 then
    local sx, sy = grid.world_to_sector(px, py)
    local w, h = get_screen_size()
    draw_text(w - MAP_SIZE - MARGIN, h - MAP_SIZE - BOTTOM_MARGIN - 24,
      string.format("Sector (%d,%d)", sx, sy), "default", 255, 255, 255)
    return
  end

  local best, best_d = nil, math.huge
  for _, p in ipairs(planets) do
    local d = math.sqrt((p.x - px) ^ 2 + (p.y - py) ^ 2) - p.body_radius
    if d < best_d then best, best_d = p, d end
  end
  if best == nil then return end

  local w, h = get_screen_size()
  local c = color_for(best)
  draw_text(w - MAP_SIZE - MARGIN, h - MAP_SIZE - BOTTOM_MARGIN - 24,
    string.format("%s  %d px", best.name, math.max(0, best_d)), "default", c[1], c[2], c[3])
end

local function draw_labels(planets)
  local camX, camY = get_camera_position()
  local w, h = get_screen_size()

  for _, p in ipairs(planets) do
    local top = p.y + p.body_radius + LABEL_GAP
    if p.x + p.body_radius > camX and p.x - p.body_radius < camX + w
       and top > camY - 40 and p.y - p.body_radius < camY + h then
      local text = p.name
      if p.mineral ~= nil then text = text .. " (" .. p.mineral .. ")" end
      local c = color_for(p)
      draw_text_world(p.x - #text * CHAR_WIDTH / 2, top, text, "default", c[1], c[2], c[3])
    end
  end
end

-- Indicador de PvP arriba a la derecha (solo en linea); el host lo alterna con P
local function draw_pvp()
  -- Se llama siempre para mantener al dia el detector de flanco
  local pressed = toggle_pvp_pressed()
  if not net_is_online() then return end
  local pvp = net_room_settings().pvp
  if pressed and net_is_host() then
    net_set_pvp(not pvp)
    pvp = not pvp
  end
  local w = get_screen_size()
  local text = pvp and "PvP ON" or "PvP OFF"
  local x = w - MARGIN - #text * CHAR_WIDTH
  if pvp then
    draw_text(x, MARGIN, text, "default", 255, 70, 70)
  else
    draw_text(x, MARGIN, text, "default", 80, 220, 100)
  end
  if net_is_host() then
    local hint = "P - toggle"
    draw_text(w - MARGIN - #hint * CHAR_WIDTH, MARGIN + 20, hint, "default", 200, 200, 200)
  end
end

function update()
  draw_pvp()
  local planets = scene_planets
  if planets == nil then return end
  if belt_points == nil and scene_map == nil then belt_points = build_belt_points() end

  draw_labels(planets)
  draw_minimap(planets)
  draw_nearest(planets)
end
