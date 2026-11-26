-- =====================================================================
--  Senal de Pal (#26), modulo que usa map_event_world.lua.
--  - Registra el tipo pal_signal en el director de eventos (#24): pick elige
--    donde cae la caja de loot alto, fire (host) la crea y on_end (host) la
--    borra si nadie la abrio (map_event_crate.lua).
--  - La caja va entre dos zonas con jugadores para provocar el combate: el
--    punto medio entre el centroide de las naves del sector y el de las naves
--    del otro sector ocupado con mas gente (el centro del sector si no hay otro).
--  - El haz de luz se dibuja cada frame a partir de map_events, en todos los
--    clientes (tambien un recien llegado, que no corre on_start). El icono del
--    minimapa lo dibuja solar_hud.lua con params.x / params.y.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local crate = require("map_event_crate")

local P = cfg.PAL_SIGNAL
local TYPE = "pal_signal"
-- Radio (px) alrededor del punto ideal donde se buscan puntos libres
local SEARCH_RADIUS = 1500

local signal = {}

-- Reloj propio para la animacion
local clock = 0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Posiciones de las naves vivas (la local y las de player_ships)
local function ship_positions()
  local list = {}
  if player_entity ~= nil and is_alive(player_entity) then
    local x, y = get_collider_center(player_entity)
    list[#list + 1] = { x = x, y = y }
  end
  if player_ships ~= nil then
    for id in pairs(player_ships) do
      local e = find_by_net_id(id)
      if e ~= nil and is_alive(e) then
        local x, y = get_collider_center(e)
        list[#list + 1] = { x = x, y = y }
      end
    end
  end
  return list
end

-- Naves por sector: clave -> { sx, sy, n, x, y } con x, y la suma (luego el centroide)
local function group_by_sector(ships)
  local groups = {}
  for _, s in ipairs(ships) do
    local sx, sy = grid.world_to_sector(s.x, s.y)
    local key = sx .. ":" .. sy
    local g = groups[key]
    if g == nil then
      g = { sx = sx, sy = sy, n = 0, x = 0, y = 0 }
      groups[key] = g
    end
    g.n = g.n + 1
    g.x = g.x + s.x
    g.y = g.y + s.y
  end
  for _, g in pairs(groups) do
    g.x = g.x / g.n
    g.y = g.y / g.n
  end
  return groups
end

-- true si el punto queda a crate_clear del cuerpo de todos los planetas
local function clear_of_planets(x, y)
  for _, p in ipairs(scene_planets or {}) do
    local reach = (p.body_radius or 0) + P.crate_clear
    local dx, dy = x - p.x, y - p.y
    if dx * dx + dy * dy < reach * reach then return false end
  end
  return true
end

-- Punto de la caja (solo lo llama el host, math.random esta bien): el objetivo
-- o, si un planeta lo cubre, un punto al azar cerca de el dentro del sector
local function crate_spot(sx, sy, tx, ty)
  local rx, ry, rw, rh = grid.sector_bounds(sx, sy)
  local minX, maxX = rx + P.edge_pad, rx + rw - P.edge_pad
  local minY, maxY = ry + P.edge_pad, ry + rh - P.edge_pad
  tx, ty = clamp(tx, minX, maxX), clamp(ty, minY, maxY)
  if clear_of_planets(tx, ty) then return tx, ty end
  for _ = 1, P.crate_tries do
    local a = math.random() * 2 * math.pi
    local d = math.sqrt(math.random()) * SEARCH_RADIUS
    local x = clamp(tx + d * math.cos(a), minX, maxX)
    local y = clamp(ty + d * math.sin(a), minY, maxY)
    if clear_of_planets(x, y) then return x, y end
  end
  return nil
end

-- ---------------------------------------------------------------------
--  Registro en el director de eventos
-- ---------------------------------------------------------------------

map_event_types = map_event_types or {}
map_event_types[TYPE] = {
  pick = function(sx, sy)
    local rx, ry, rw, rh = grid.sector_bounds(sx, sy)
    local groups = group_by_sector(ship_positions())
    local a = groups[sx .. ":" .. sy]
    -- El otro sector ocupado con mas naves (a igualdad, el de clave menor)
    local b = nil
    for key, g in pairs(groups) do
      if g ~= a and (b == nil or g.n > b.n or (g.n == b.n and key < b.key)) then
        b = g
        b.key = key
      end
    end
    local tx, ty = rx + rw / 2, ry + rh / 2
    if b ~= nil then
      -- Sin naves en el sector (no deberia) el punto medio parte del centro
      local ax, ay = tx, ty
      if a ~= nil then ax, ay = a.x, a.y end
      tx, ty = (ax + b.x) / 2, (ay + b.y) / 2
    end
    local x, y = crate_spot(sx, sy, tx, ty)
    if x == nil then return nil end
    return { x = x, y = y }
  end,
  fire = function(p)
    -- fire corre antes de que el director copie params: el id viaja a todos
    return crate.spawn(p, TYPE)
  end,
  on_end = function(ev)
    crate.despawn(ev, TYPE)
  end,
}

-- ---------------------------------------------------------------------
--  Dibujo
-- ---------------------------------------------------------------------

-- Haz animado con la base en el centro de la caja (coordenadas de pantalla
-- como map_visuals.lua); lo que no se ve se salta
local function draw_beam(ev, camX, camY, sw, sh)
  local B = P.beam
  local x = ev.params.x - B.w / 2 - camX
  local y = ev.params.y - B.h - camY
  if x + B.w < 0 or x > sw or y + B.h < 0 or y > sh then return end
  local frame = math.floor(clock * P.fps) % B.count
  draw_image("pal-beacon", x, y, B.w, B.h, P.alpha, "front",
    { src = { x = frame * B.frame_w, y = 0, w = B.frame_w, h = B.frame_h } })
end

-- Avanza el dibujo de las senales activas
function signal.step(dt, camX, camY, sw, sh)
  clock = clock + dt
  if map_events == nil then return end
  for _, ev in pairs(map_events) do
    if ev.type == TYPE and type(ev.params.x) == "number" and type(ev.params.y) == "number" then
      draw_beam(ev, camX, camY, sw, sh)
    end
  end
end

return signal
