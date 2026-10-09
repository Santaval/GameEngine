-- =====================================================================
--  Lluvia de escombros (#26), modulo que usa map_event_world.lua.
--  - Registra el tipo debris_rain en el director de eventos (#24): pick elige
--    el rumbo (al azar) y el centro del sector; fire no hace nada, las rocas
--    nacen en step.
--  - Fases a partir del tiempo restante del evento (ev.t), asi que todos los
--    clientes, tambien un recien llegado, ven la misma: aviso -> lluvia -> cola.
--  - Solo el host crea las rocas, durante la lluvia: asteroides normales
--    (net_spawn de asteroid.lua, del host y replicados) que entran por el lado
--    contrario al rumbo y cruzan el sector rapido, asi que danan al chocar por
--    la via de siempre (ImpactDamage). Con state.ttl el duenio borra la roca
--    pasado un tiempo (ver asteroid.lua).
--  - Aviso: flechas en el borde de la pantalla del lado de donde vienen y, en
--    el aviso, un texto si la nave esta en el sector.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local field = require("asteroid_field")
local ui = require("ui_helpers")

local DR = cfg.DEBRIS_RAIN
local TYPE = "debris_rain"
local SECTOR = cfg.SECTOR_SIZE
local COLOR = cfg.EVENTS.types[TYPE].color

-- Distancia (px) del centro del sector a la que nacen las rocas, contra el
-- rumbo, en multiplos del lado del sector
local UPSTREAM = 0.75
-- Separacion entre flechas en multiplos de su lado y parpadeo del aviso (Hz)
local ARROW_GAP = 1.5
local BLINK_HZ = 2
-- Opacidad de las flechas en la lluvia y en el aviso (maxima)
local ARROW_ALPHA_RAIN = 150
local ARROW_ALPHA_WARNING = 255

local rain = {}

-- Reloj propio para el parpadeo
local clock = 0
-- Rocas pendientes de crear por evento (id -> fraccion); solo el host la usa
local pending = {}

local function rand_range(r)
  return r.min + math.random() * (r.max - r.min)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Fase segun el tiempo transcurrido del evento
function rain.phase(ev)
  local elapsed = cfg.EVENTS.types[TYPE].duration - ev.t
  if elapsed < DR.warning then return "warning" end
  if elapsed < DR.warning + DR.rain then return "rain" end
  return "tail"
end

-- ---------------------------------------------------------------------
--  Registro en el director de eventos
-- ---------------------------------------------------------------------

map_event_types = map_event_types or {}
map_event_types[TYPE] = {
  pick = function(sx, sy)
    local x, y, w, h = grid.sector_bounds(sx, sy)
    return { x = x + w / 2, y = y + h / 2, angle = math.random() * 2 * math.pi }
  end,
  fire = function()
    return true
  end,
}

-- ---------------------------------------------------------------------
--  Rocas (host)
-- ---------------------------------------------------------------------

-- Crea una roca del lado de donde viene la lluvia, con un desvio lateral
-- al azar de medio sector y un rumbo con algo de ruido
local function spawn_rock(p)
  local ux, uy = math.cos(p.angle), math.sin(p.angle)
  local side = (math.random() - 0.5) * SECTOR
  local cx = p.x - ux * SECTOR * UPSTREAM - uy * side
  local cy = p.y - uy * SECTOR * UPSTREAM + ux * side
  local a = p.angle + (math.random() * 2 - 1) * DR.spread
  local speed = rand_range(DR.speed)
  local scale = rand_range(DR.scale)
  local state = field.asteroid_state(cx, cy, scale, function()
    return math.cos(a) * speed, math.sin(a) * speed
  end)
  state.ttl = DR.ttl
  net_spawn("asteroid.lua", state)
end

-- El host crea las rocas de los eventos en lluvia; los acumuladores de eventos
-- que ya no estan se borran
local function step_spawns(dt)
  for id in pairs(pending) do
    if map_events[id] == nil then pending[id] = nil end
  end
  if not net_is_host() then return end
  for id, ev in pairs(map_events) do
    if ev.type == TYPE and rain.phase(ev) == "rain" then
      local acc = (pending[id] or 0) + dt * DR.rate
      while acc >= 1 do
        acc = acc - 1
        spawn_rock(ev.params)
      end
      pending[id] = acc
    end
  end
end

-- ---------------------------------------------------------------------
--  Aviso
-- ---------------------------------------------------------------------

-- true si (x, y) esta en el sector del evento ampliado en pad px por lado
local function near_sector(ev, x, y, pad)
  local rx, ry, rw, rh = grid.sector_bounds(ev.sx, ev.sy)
  return x >= rx - pad and x < rx + rw + pad and y >= ry - pad and y < ry + rh + pad
end

-- Flechas en el borde de la pantalla de donde vienen las rocas: el punto donde
-- el rayo desde el centro, contra el rumbo, corta el rectangulo de la pantalla
-- recortado por el margen; las flechas se reparten a lo ancho de ese borde
local function draw_arrows(angle, phase, sw, sh)
  local S = DR.arrow_size
  local ux, uy = math.cos(angle), math.sin(angle)
  local hx = sw / 2 - DR.arrow_margin - S / 2
  local hy = sh / 2 - DR.arrow_margin - S / 2
  local t = math.huge
  if math.abs(ux) > 0.0001 then t = math.min(t, hx / math.abs(ux)) end
  if math.abs(uy) > 0.0001 then t = math.min(t, hy / math.abs(uy)) end
  local bx, by = sw / 2 - ux * t, sh / 2 - uy * t

  local alpha = ARROW_ALPHA_RAIN
  if phase == "warning" then
    local blink = 0.5 + 0.5 * math.sin(clock * 2 * math.pi * BLINK_HZ)
    alpha = math.floor(ARROW_ALPHA_WARNING * (0.3 + 0.7 * blink))
  end

  local n = DR.arrow_count
  for i = 1, n do
    local off = (i - (n + 1) / 2) * S * ARROW_GAP
    local x = clamp(bx - uy * off, S / 2 + DR.arrow_margin, sw - S / 2 - DR.arrow_margin)
    local y = clamp(by + ux * off, S / 2 + DR.arrow_margin, sh - S / 2 - DR.arrow_margin)
    draw_image("debris-arrow", x - S / 2, y - S / 2, S, S, alpha, "hud", { angle = math.deg(angle) })
  end
end

-- Avanza la lluvia: las rocas del host y el aviso de la nave local
function rain.step(dt, camX, camY, sw, sh)
  clock = clock + dt
  if map_events == nil then return end
  step_spawns(dt)

  local alive = player_entity ~= nil and is_alive(player_entity)
  if not alive then return end
  local px, py = get_collider_center(player_entity)
  for _, ev in pairs(map_events) do
    if ev.type == TYPE and type(ev.params.angle) == "number" then
      local phase = rain.phase(ev)
      if phase ~= "tail" and near_sector(ev, px, py, DR.warn_pad) then
        draw_arrows(ev.params.angle, phase, sw, sh)
      end
      if phase == "warning" and near_sector(ev, px, py, 0) then
        local _, wh = get_window_size()
        local left = math.ceil(DR.warning - (cfg.EVENTS.types[TYPE].duration - ev.t))
        ui.draw_centered(wh * 0.2, string.format("LLUVIA DE ESCOMBROS EN %ds", left), "debug-big", 28,
          COLOR[1], COLOR[2], COLOR[3], 255)
      end
    end
  end
end

return rain
