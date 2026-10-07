-- =====================================================================
--  HUD de navegacion del sistema solar (entidad director, solo script):
--  minimapa abajo a la derecha con el Sol, los planetas (color segun su
--  mineral), los cinturones y la nave, y el nombre de cada planeta en el
--  mundo debajo de su cuerpo.
-- =====================================================================

local solar = require("solar_system_config")

local MAP_SIZE = 220
local MARGIN = 20
-- La parte de abajo de la pantalla la usan los avisos de orbita / mineria
local BOTTOM_MARGIN = 120

local MINERAL_COLORS = {
  iron = { 190, 190, 200 },
  gunpowder = { 255, 150, 50 },
  plasma = { 200, 110, 255 },
}
local SUN_COLOR = { 255, 210, 80 }
local BELT_COLOR = { 130, 120, 100 }
local PLAYER_COLOR = { 255, 255, 0 }

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

local function color_for(planet)
  if planet.mineral == nil then return SUN_COLOR end
  return MINERAL_COLORS[planet.mineral] or { 255, 255, 255 }
end

-- Mundo -> pantalla del minimapa (ox, oy es la esquina del minimapa)
local function to_map(x, y, ox, oy)
  local k = MAP_SIZE / (2 * solar.MAP_RADIUS)
  return ox + (x - solar.SUN_CENTER.x + solar.MAP_RADIUS) * k,
         oy + (y - solar.SUN_CENTER.y + solar.MAP_RADIUS) * k
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

local function draw_minimap(planets)
  local w, h = get_screen_size()
  local ox, oy = w - MAP_SIZE - MARGIN, h - MAP_SIZE - BOTTOM_MARGIN

  draw_rect(ox, oy, MAP_SIZE, MAP_SIZE, 0, 0, 0, 170)
  draw_rect(ox, oy, MAP_SIZE, MAP_SIZE, 255, 255, 255, 120, false)

  for _, p in ipairs(belt_points) do
    local mx, my = to_map(p.x, p.y, ox, oy)
    draw_rect(mx - 1, my - 1, 2, 2, BELT_COLOR[1], BELT_COLOR[2], BELT_COLOR[3], 160)
  end

  local k = MAP_SIZE / (2 * solar.MAP_RADIUS)
  for _, p in ipairs(planets) do
    local mx, my = to_map(p.x, p.y, ox, oy)
    local dot = math.max(MIN_DOT, math.min(MAX_DOT, p.body_radius * 2 * k * 4))
    local c = color_for(p)
    draw_rect(mx - dot / 2, my - dot / 2, dot, dot, c[1], c[2], c[3], 255)
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

function update()
  local planets = scene_planets
  if planets == nil then return end
  if belt_points == nil then belt_points = build_belt_points() end

  draw_labels(planets)
  draw_minimap(planets)
  draw_nearest(planets)
end
