-- =====================================================================
--  Planeta sobrecargado (#26), modulo que usa map_event_world.lua y
--  player/player_mining.lua.
--  - Registra el tipo overcharged_planet en el director de eventos (#24): pick
--    elige un planeta con mineral del sector que no este ya sobrecargado; fire
--    no hace nada (el efecto sale de map_events).
--  - multiplier(planeta) dice cuanto rinde ahora el mineral: OVERCHARGED.mult si
--    hay un evento activo sobre ese planeta (params.x / params.y), si no 1. Sale
--    de map_events, asi que vale igual para un recien llegado y tras migrar el host.
--  - Dibujo: aura animada sobre el planeta (blanca, draw_image no tine) y un
--    anillo punteado que se expande, del color del mineral.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local zones = require("player_gravity_zones")

local O = cfg.OVERCHARGED
local TYPE = "overcharged_planet"
local DEFAULT_COLOR = { 255, 255, 255 }
-- El anillo nace en body_radius * RING_START y llega al range; segundos de
-- cada pulso
local RING_START = 1.1
local RING_PERIOD = 2

local overcharged = {}

-- Reloj propio para las animaciones
local clock = 0

-- true si el planeta p es el objetivo del evento ev
local function is_target(ev, p)
  return type(ev.params.x) == "number" and type(ev.params.y) == "number"
    and math.abs(ev.params.x - p.x) < 1 and math.abs(ev.params.y - p.y) < 1
end

-- true si algun evento activo sobrecarga el planeta p
local function is_overcharged(p)
  if map_events == nil then return false end
  for _, ev in pairs(map_events) do
    if ev.type == TYPE and is_target(ev, p) then return true end
  end
  return false
end

-- Multiplicador del mineral del planeta (1 si no esta sobrecargado)
function overcharged.multiplier(planet)
  if is_overcharged(planet) then return O.mult end
  return 1
end

-- ---------------------------------------------------------------------
--  Registro en el director de eventos
-- ---------------------------------------------------------------------

map_event_types = map_event_types or {}
map_event_types[TYPE] = {
  pick = function(sx, sy)
    local list = {}
    for _, p in ipairs(scene_planets or {}) do
      if p.mineral ~= nil then
        local psx, psy = grid.world_to_sector(p.x, p.y)
        if psx == sx and psy == sy and not is_overcharged(p) then list[#list + 1] = p end
      end
    end
    if #list == 0 then return nil end
    local p = list[math.random(1, #list)]
    return { x = p.x, y = p.y }
  end,
  fire = function()
    return true
  end,
}

-- ---------------------------------------------------------------------
--  Dibujo
-- ---------------------------------------------------------------------

-- Aura animada centrada en el planeta y anillo punteado que se expande y se
-- desvanece; lo que queda fuera de la pantalla se salta
local function draw_planet(p, camX, camY, sw, sh)
  local reach = math.max(p.range or 0, p.body_radius)
  if p.x + reach < camX or p.x - reach > camX + sw or p.y + reach < camY or p.y - reach > camY + sh then
    return
  end

  local size = 2 * p.body_radius * O.size_factor
  local frame = math.floor(clock * O.fps) % O.sheet.count
  draw_image("aura-overcharged", p.x - size / 2 - camX, p.y - size / 2 - camY, size, size, O.alpha, "front",
    { src = { x = frame * O.sheet.frame_w, y = O.sheet.src_y, w = O.sheet.frame_w, h = O.sheet.src_h } })

  local lo = p.body_radius * RING_START
  local f = (clock % RING_PERIOD) / RING_PERIOD
  local color = O.colors[p.mineral] or DEFAULT_COLOR
  zones.draw_ring({ x = p.x, y = p.y }, lo + (reach - lo) * f, color, math.floor(O.alpha * (1 - f)),
    O.ring_dot_spacing)
end

-- Avanza el dibujo de los planetas sobrecargados
function overcharged.step(dt, camX, camY, sw, sh)
  clock = clock + dt
  if map_events == nil then return end
  for _, ev in pairs(map_events) do
    if ev.type == TYPE then
      for _, p in ipairs(scene_planets or {}) do
        if is_target(ev, p) then draw_planet(p, camX, camY, sw, sh) end
      end
    end
  end
end

return overcharged
