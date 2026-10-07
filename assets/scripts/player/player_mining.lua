local zones = require("player_gravity_zones")

local player_mining_module = {}

-- Color del rayo y del texto segun el mineral del planeta
local MINERAL_COLORS = {
  iron = { 190, 190, 200 },
  gunpowder = { 255, 150, 50 },
  plasma = { 200, 110, 255 },
}
local DEFAULT_COLOR = { 255, 255, 255 }

-- Rayo punteado entre la superficie y la nave: los puntos suben hacia la nave
local BEAM_DOT_SPACING = 14
local BEAM_DOT_SIZE = 4
local BEAM_FLOW_SPEED = 60
-- Texto "+1 iron": cuanto dura y cuanto sube (px/s)
local POPUP_TIME = 1
local POPUP_RISE = 40

-- Estado del modulo: persiste entre frames, se reinicia al cargar la escena
local timer = 0
local planet = nil
local mining = false
local cargo_full = false
local clock = 0
local popups = {}

local function color_for(mineral)
  return MINERAL_COLORS[mineral] or DEFAULT_COLOR
end

-- Mina mientras la nave esta dentro del range (gravedad) de un planeta con
-- mineral: suma el mineral del planeta cada mine_interval segundos
function player_mining_module.update(entity)
  local dt = get_delta_time()
  clock = clock + dt

  planet = zones.nearest_planet(entity, 1)
  mining = planet ~= nil and planet.mineral ~= nil
  if not mining then
    timer = 0
    cargo_full = false
    return
  end

  timer = timer + dt
  if timer < planet.mine_interval then return end
  timer = timer - planet.mine_interval

  -- add_item ya recorta a la capacidad: 0 significa bodega llena
  cargo_full = add_item(entity, planet.mineral, 1) == 0
  if not cargo_full then
    local x, y = get_collider_center(entity)
    popups[#popups + 1] = { x = x, y = y - 40, text = "+1 " .. planet.mineral, t = 0, color = color_for(planet.mineral) }
  end
end

local function draw_beam(entity, planet, color)
  local sx, sy = get_collider_center(entity)
  local r, dx, dy = zones.distance_to(entity, planet)
  if r <= planet.body_radius then return end

  -- Desde la superficie (en direccion a la nave) hasta la nave
  local nx, ny = dx / r, dy / r
  local length = r - planet.body_radius
  local offset = (clock * BEAM_FLOW_SPEED) % BEAM_DOT_SPACING
  local half = BEAM_DOT_SIZE / 2
  local d = offset
  while d < length do
    draw_rect_world(sx - nx * d - half, sy - ny * d - half, BEAM_DOT_SIZE, BEAM_DOT_SIZE,
      color[1], color[2], color[3], 200)
    d = d + BEAM_DOT_SPACING
  end
end

-- Los popups siguen subiendo y desvaneciendose aunque se deje de minar
local function draw_popups()
  local alive = {}
  for _, p in ipairs(popups) do
    p.t = p.t + get_delta_time()
    if p.t < POPUP_TIME then
      local alpha = math.floor(255 * (1 - p.t / POPUP_TIME))
      draw_text_world(p.x, p.y - p.t * POPUP_RISE, p.text, "default", p.color[1], p.color[2], p.color[3], alpha)
      alive[#alive + 1] = p
    end
  end
  popups = alive
end

function player_mining_module.draw(entity)
  draw_popups()
  if not mining then return end

  local color = color_for(planet.mineral)
  draw_beam(entity, planet, color)

  local w, h = get_screen_size()
  if cargo_full then
    draw_text(w / 2 - 60, h - 100, "Bodega llena", "default", 255, 60, 60)
  else
    draw_text(w / 2 - 70, h - 100, "Minando " .. planet.mineral, "default", color[1], color[2], color[3])
  end
end

return player_mining_module
