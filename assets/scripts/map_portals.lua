-- =====================================================================
--  Pares de portales estables (#22): STABLE_PORTAL_PAIRS pares permanentes
--  de dos extremos, a 2-4 sectores uno del otro. Es una funcion pura de la
--  semilla, como map_reactor: todos los clientes obtienen los mismos pares
--  sin enviar nada por la red. No llama al motor ni usa math.random (el flujo
--  propio es grid.SALT_PORTAL). Las reglas de colocacion estan en
--  docs/aval-cup.md y los ajustes en map_config.lua (config.PORTAL).
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local biomes = require("map_biomes")
local reactor = require("map_reactor")

local P = cfg.PORTAL
local W = cfg.WORLD_SIZE
local B = cfg.STORM_BAND
local CLEAR = cfg.PORTAL_CLEAR_RADIUS

local portals = {}

-- Biomas donde cae al menos un extremo de cada par
local ANCHOR_BIOMES = { deep_void = true, debris = true }

-- Cache por semilla, como map_reactor.sites
local MAX_CACHED = 8
local cache, cached = {}, 0

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- Punto al azar del sector (sx, sy), a CLEAR px de sus bordes
local function random_point(r, sx, sy)
  local bx, by, bw, bh = grid.sector_bounds(sx, sy)
  return r.range(bx + CLEAR, bx + bw - CLEAR), r.range(by + CLEAR, by + bh - CLEAR)
end

-- true si un extremo puede ir en (x, y): dentro del mundo util, lejos de las
-- megaestructuras, los planetas, el spawn y de los extremos ya colocados
local function valid(x, y, layout, sites, placed)
  if x < B + CLEAR or x > W - B - CLEAR or y < B + CLEAR or y > W - B - CLEAR then return false end
  if reactor.blocks(sites, x, y, CLEAR) then return false end
  for _, p in ipairs(layout.planets) do
    local min = P.planet_factor * p.range
    if dist2(x, y, p.x, p.y) < min * min then return false end
  end
  local sp = cfg.PLAYER_SPAWN
  if dist2(x, y, sp.x, sp.y) < P.spawn_clear * P.spawn_clear then return false end
  for _, e in ipairs(placed) do
    if dist2(x, y, e.x, e.y) < P.spacing * P.spacing then return false end
  end
  return true
end

-- Intenta colocar el par i. Devuelve el par o nil si se agotaron los intentos
local function build_pair(i, r, layout, sites, anchors, ends)
  local sectors = cfg.SECTORS
  for _ = 1, P.tries do
    local a = anchors[r.int(1, #anchors)]
    -- Sector de B: todos los que quedan a pair_sectors de distancia de A
    local far = {}
    for sy = 0, sectors - 1 do
      for sx = 0, sectors - 1 do
        local d = math.max(math.abs(sx - a.sx), math.abs(sy - a.sy))
        if d >= P.pair_sectors.min and d <= P.pair_sectors.max then far[#far + 1] = { sx = sx, sy = sy } end
      end
    end
    local b = far[r.int(1, #far)]

    local ax, ay = random_point(r, a.sx, a.sy)
    local bx, by = random_point(r, b.sx, b.sy)
    local aAngle = r.range(0, 2 * math.pi)
    local bAngle = r.range(0, 2 * math.pi)

    -- B tambien guarda spacing con A (aun no esta en ends)
    if valid(ax, ay, layout, sites, ends) and valid(bx, by, layout, sites, ends)
       and dist2(ax, ay, bx, by) >= P.spacing * P.spacing then
      local ea = { x = ax, y = ay, angle = aAngle, pair = i, side = "a", sx = a.sx, sy = a.sy }
      local eb = { x = bx, y = by, angle = bAngle, pair = i, side = "b", sx = b.sx, sy = b.sy }
      return { id = i, a = ea, b = eb }
    end
  end
  return nil
end

local function build(seed)
  local layout = biomes.layout(seed)
  local sites = reactor.sites(seed)
  local r = grid.rng(grid.hash(seed, 0, 0, grid.SALT_PORTAL))

  local anchors = {}
  for sy = 0, cfg.SECTORS - 1 do
    for sx = 0, cfg.SECTORS - 1 do
      if ANCHOR_BIOMES[layout.biomes[sx][sy]] then anchors[#anchors + 1] = { sx = sx, sy = sy } end
    end
  end

  local out = { pairs = {}, ends = {} }
  if #anchors == 0 then
    print("[portal] sin sectores deep_void ni debris: no hay portales")
    return out
  end

  for i = 1, cfg.STABLE_PORTAL_PAIRS do
    local pair = build_pair(i, r, layout, sites, anchors, out.ends)
    if pair ~= nil then
      out.pairs[#out.pairs + 1] = pair
      out.ends[#out.ends + 1] = pair.a
      out.ends[#out.ends + 1] = pair.b
    else
      print(string.format("[portal] par %d omitido: sin sitio tras %d intentos", i, P.tries))
    end
  end
  return out
end

-- Pares de la semilla: { pairs = { {id, a, b} }, ends = { extremo, ... } } con
-- extremo = { x, y, angle, pair, side ("a"/"b"), sx, sy }. x, y es el centro
-- del portal y angle su eje de salida (radianes). Memoizado por semilla
function portals.sites(seed)
  local key = math.tointeger(seed) or seed
  local hit = cache[key]
  if hit ~= nil then return hit end

  if cached >= MAX_CACHED then cache, cached = {}, 0 end
  hit = build(seed)
  cache[key] = hit
  cached = cached + 1
  return hit
end

-- true si un disco de radio `radius` en (x, y) toca la zona vedada de algun
-- extremo (PORTAL_CLEAR_RADIUS): ahi no nacen rocas
function portals.blocks(ends, x, y, radius)
  local min = CLEAR + radius
  for _, e in ipairs(ends) do
    local dx, dy = x - e.x, y - e.y
    if dx * dx + dy * dy < min * min then return true end
  end
  return false
end

return portals
