-- =====================================================================
--  Contraccion de la tormenta (#25), modulo que usa map_storm_world.lua.
--  - Registra el tipo storm_contraction en el director de eventos (#24):
--    pick elige el sector y el punto de la caja de loot, fire (host) crea la
--    caja y on_end (host) la borra si nadie la abrio.
--  - Fases a partir del tiempo restante del evento (ev.t), asi que todos los
--    clientes, tambien un recien llegado, ven la misma: aviso -> cierre -> espera.
--  - Zona de tormenta: dentro del sector y mas lejos del centro que el radio
--    seguro. El dano, las teselas y el tinte solo aplican ahi.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local storm = require("map_storm")
local zones = require("player_gravity_zones")
local ui = require("ui_helpers")
local crate = require("map_event_crate")

local C = cfg.STORM_CONTRACTION
local SAFE = cfg.STORM_CONTRACTION_SAFE_RADIUS
local TYPE = "storm_contraction"

-- Margen (px) entre el borde del circulo final y la caja
local CRATE_EDGE_PAD = 300
-- Grosor (px) de los tres marcos anidados del contorno del sector y su parpadeo (Hz)
local OUTLINE_STEP = 4
local BLINK_HZ = 1.5

local contraction = {}

-- Reloj propio para el parpadeo
local clock = 0

-- Rectangulo del sector (x, y, w, h) y su centro
function contraction.sector_rect(sx, sy)
  return grid.sector_bounds(sx, sy)
end

function contraction.centre(sx, sy)
  local x, y, w, h = grid.sector_bounds(sx, sy)
  return x + w / 2, y + h / 2
end

-- Fase segun el tiempo transcurrido del evento
function contraction.phase(ev)
  local elapsed = cfg.EVENTS.types[TYPE].duration - ev.t
  if elapsed < C.warning then return "warning" end
  if elapsed < C.warning + C.shrink then return "shrink" end
  return "hold"
end

-- Radio seguro actual: el inicial en el aviso, baja linealmente en el cierre y
-- se queda en el final en la espera
function contraction.radius_at(ev)
  local elapsed = cfg.EVENTS.types[TYPE].duration - ev.t
  if elapsed < C.warning then return C.start_radius end
  local f = math.min(1, (elapsed - C.warning) / C.shrink)
  return C.start_radius + (SAFE - C.start_radius) * f
end

local function in_rect(ev, x, y)
  local rx, ry, rw, rh = grid.sector_bounds(ev.sx, ev.sy)
  return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

-- true si (x, y) esta en la zona de tormenta del evento: nunca en el aviso
function contraction.in_storm(ev, x, y)
  if contraction.phase(ev) == "warning" then return false end
  if not in_rect(ev, x, y) then return false end
  local cx, cy = contraction.centre(ev.sx, ev.sy)
  local r = contraction.radius_at(ev)
  local dx, dy = x - cx, y - cy
  return dx * dx + dy * dy > r * r
end

-- ---------------------------------------------------------------------
--  Registro en el director de eventos
-- ---------------------------------------------------------------------

-- true si el punto queda a crate_clear del cuerpo de todos los planetas (la
-- gravedad no cuenta: casi cubre los sectores Planetary y la caja no se mueve)
local function clear_of_planets(x, y)
  for _, p in ipairs(scene_planets or {}) do
    local reach = (p.body_radius or 0) + C.crate_clear
    local dx, dy = x - p.x, y - p.y
    if dx * dx + dy * dy < reach * reach then return false end
  end
  return true
end

-- Punto de la caja: el centro del sector o, si un planeta lo cubre, un punto al
-- azar del circulo final (solo lo llama el host, math.random esta bien)
local function crate_spot(cx, cy)
  if clear_of_planets(cx, cy) then return cx, cy end
  local reach = SAFE - CRATE_EDGE_PAD
  for _ = 1, C.crate_tries do
    local a = math.random() * 2 * math.pi
    local d = math.sqrt(math.random()) * reach
    local x, y = cx + d * math.cos(a), cy + d * math.sin(a)
    if clear_of_planets(x, y) then return x, y end
  end
  return nil
end

map_event_types = map_event_types or {}
map_event_types[TYPE] = {
  pick = function(sx, sy)
    local cx, cy = contraction.centre(sx, sy)
    local x, y = crate_spot(cx, cy)
    if x == nil then return nil end
    return { x = x, y = y, cx = cx, cy = cy }
  end,
  fire = function(p)
    -- fire corre antes de que el director copie params: el id viaja a todos
    return crate.spawn(p, TYPE)
  end,
  -- Al acabar, el host borra la caja si nadie la abrio (tambien el host nuevo
  -- tras migrar: el id va en params)
  on_end = function(ev)
    crate.despawn(ev, TYPE)
  end,
}

-- ---------------------------------------------------------------------
--  Dibujo
-- ---------------------------------------------------------------------

-- Contorno parpadeante del sector (tres marcos anidados) y circulo final punteado
local function draw_warning(ev, cx, cy)
  local rx, ry, rw, rh = grid.sector_bounds(ev.sx, ev.sy)
  local hc = C.highlight
  local blink = 0.5 + 0.5 * math.sin(clock * 2 * math.pi * BLINK_HZ)
  local a = math.floor(C.highlight_alpha * (0.4 + 0.6 * blink))
  for i = 0, 2 do
    local o = i * OUTLINE_STEP
    draw_rect_world(rx + o, ry + o, rw - 2 * o, rh - 2 * o, hc[1], hc[2], hc[3], a, false)
  end
  zones.draw_ring({ x = cx, y = cy }, SAFE, hc, C.highlight_alpha, C.ring_dot_spacing)
end

-- Teselas, borde irregular y borde del circulo seguro del cierre y la espera
local function draw_closing(ev, cx, cy, camX, camY, sw, sh, frame)
  local rx, ry, rw, rh = grid.sector_bounds(ev.sx, ev.sy)
  local r = contraction.radius_at(ev)
  storm.draw_fill(camX, camY, sw, sh, frame, function(x, y)
    return contraction.in_storm(ev, x, y)
  end, rx, ry, C.tile_alpha)
  storm.draw_edge_ring(cx, cy, r, C.edge_height, camX, camY, sw, sh, frame, function(x, y)
    return x >= rx and x < rx + rw and y >= ry and y < ry + rh
  end)
  zones.draw_ring({ x = cx, y = cy }, r, C.highlight, C.highlight_alpha, C.ring_dot_spacing)
end

-- Avanza el dibujo de las contracciones activas; (px, py) es la nave local o
-- nil. Devuelve true si la nave esta en la zona de tormenta
function contraction.step(dt, camX, camY, sw, sh, frame, px, py)
  clock = clock + dt
  if map_events == nil then return false end
  local inside = false
  for _, ev in pairs(map_events) do
    if ev.type == TYPE then
      local cx, cy = contraction.centre(ev.sx, ev.sy)
      local phase = contraction.phase(ev)
      if phase == "warning" then
        draw_warning(ev, cx, cy)
        if px ~= nil and in_rect(ev, px, py) then
          local _, wh = get_window_size()
          local c = C.highlight
          local left = math.ceil(ev.t - (C.shrink + C.hold))
          ui.draw_centered(wh * 0.2, string.format("CONTRACCION EN %ds", left), "debug-big", 28, c[1], c[2], c[3], 255)
        end
      else
        draw_closing(ev, cx, cy, camX, camY, sw, sh, frame)
      end
      if px ~= nil and contraction.in_storm(ev, px, py) then inside = true end
    end
  end
  return inside
end

return contraction
