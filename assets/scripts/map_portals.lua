-- =====================================================================
--  Pares de portales estables (#22): STABLE_PORTAL_PAIRS pares permanentes
--  de dos extremos, a 2-4 sectores uno del otro. Es una funcion pura de la
--  semilla, como map_reactor: todos los clientes obtienen los mismos pares
--  sin enviar nada por la red. No llama al motor ni usa math.random (el flujo
--  propio es grid.SALT_PORTAL). Las reglas de colocacion estan en
--  docs/aval-cup.md y los ajustes en map_config.lua (config.PORTAL).
--  #23: tras los 12 pares se generan PORTAL_COLLAPSE.reserve_pairs pares de
--  repuesto (sitios a los que se mueve un par que colapsa) con el mismo flujo,
--  asi los 12 de siempre no cambian; y el nexus (flujo grid.SALT_NEXUS).
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local biomes = require("map_biomes")
local reactor = require("map_reactor")

local P = cfg.PORTAL
local W = cfg.WORLD_SIZE
local B = cfg.STORM_BAND
local CLEAR = cfg.PORTAL_CLEAR_RADIUS
local N = cfg.NEXUS

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

-- true si (x, y) esta dentro del mundo util, lejos de las megaestructuras, los
-- planetas y el spawn (sin mirar los demas extremos)
local function valid_basic(x, y, layout, sites)
  if x < B + CLEAR or x > W - B - CLEAR or y < B + CLEAR or y > W - B - CLEAR then return false end
  if reactor.blocks(sites, x, y, CLEAR) then return false end
  for _, p in ipairs(layout.planets) do
    local min = P.planet_factor * p.range
    if dist2(x, y, p.x, p.y) < min * min then return false end
  end
  local sp = cfg.PLAYER_SPAWN
  if dist2(x, y, sp.x, sp.y) < P.spawn_clear * P.spawn_clear then return false end
  return true
end

-- true si un extremo puede ir en (x, y): punto valido y a spacing de los
-- extremos ya colocados
local function valid(x, y, layout, sites, placed)
  if not valid_basic(x, y, layout, sites) then return false end
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

-- Cuatro bocas del nexus: direccion d (0 E, 1 S, 2 O, 3 N; y crece hacia abajo)
-- -> sectores candidatos a exit_sectors del centro en esa direccion
local function exit_sectors_for(d, csx, csy)
  local k = N.exit_sectors
  local list = {}
  for i = 0, cfg.SECTORS - 1 do
    if d == 0 then list[#list + 1] = { sx = csx + k, sy = i }
    elseif d == 1 then list[#list + 1] = { sx = i, sy = csy + k }
    elseif d == 2 then list[#list + 1] = { sx = csx - k, sy = i }
    else list[#list + 1] = { sx = i, sy = csy - k } end
  end
  local ok = {}
  for _, s in ipairs(list) do
    if s.sx >= 0 and s.sx < cfg.SECTORS and s.sy >= 0 and s.sy < cfg.SECTORS then ok[#ok + 1] = s end
  end
  return ok
end

-- Coloca el nexus en el sector central y sus 4 salidas. Devuelve
-- { x, y, sx, sy, exits = { [1..4] = {x, y, angle, dir} } } o nil. all: lista
-- de puntos ya colocados, a la que se anaden los del nexus
local function build_nexus(seed, layout, sites, all)
  local r = grid.rng(grid.hash(seed, 0, 0, grid.SALT_NEXUS))
  local csx, csy = cfg.SECTORS // 2, cfg.SECTORS // 2
  local placed = {}
  for _, e in ipairs(all) do placed[#placed + 1] = e end

  local nx, ny
  for _ = 1, N.tries do
    local x, y = random_point(r, csx, csy)
    if valid(x, y, layout, sites, placed) then nx, ny = x, y break end
  end
  if nx == nil then
    print(string.format("[portal] nexus omitido: sin sitio tras %d intentos", N.tries))
    return nil
  end
  placed[#placed + 1] = { x = nx, y = ny }

  local exits = {}
  for d = 0, 3 do
    local cands = exit_sectors_for(d, csx, csy)
    local found = nil
    for _ = 1, N.tries do
      if #cands == 0 then break end
      local sc = cands[r.int(1, #cands)]
      local x, y = random_point(r, sc.sx, sc.sy)
      if valid(x, y, layout, sites, placed) then
        -- El eje de salida apunta lejos del nexus
        found = { x = x, y = y, angle = math.atan(y - ny, x - nx), dir = d, sx = sc.sx, sy = sc.sy }
        break
      end
    end
    if found == nil then
      print(string.format("[portal] nexus omitido: sin salida %d tras %d intentos", d, N.tries))
      return nil
    end
    exits[d + 1] = found
    placed[#placed + 1] = found
  end

  for i = #all + 1, #placed do all[i] = placed[i] end
  return { x = nx, y = ny, sx = csx, sy = csy, exits = exits }
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

  -- layout y sites se guardan para valid_point
  local out = { pairs = {}, ends = {}, reserve = {}, ends_all = {}, layout = layout, rsites = sites }
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

  -- Sitios de repuesto (#23): despues de los 12 y con el mismo flujo, asi los
  -- anteriores no cambian. Guardan spacing con todo lo colocado hasta ahora
  for _, e in ipairs(out.ends) do out.ends_all[#out.ends_all + 1] = e end
  for i = 1, cfg.PORTAL_COLLAPSE.reserve_pairs do
    local pair = build_pair(cfg.STABLE_PORTAL_PAIRS + i, r, layout, sites, anchors, out.ends_all)
    if pair ~= nil then
      out.reserve[#out.reserve + 1] = pair
      out.ends_all[#out.ends_all + 1] = pair.a
      out.ends_all[#out.ends_all + 1] = pair.b
    else
      print(string.format("[portal] repuesto %d omitido: sin sitio tras %d intentos", i, P.tries))
    end
  end

  out.nexus = build_nexus(seed, layout, sites, out.ends_all)
  return out
end

-- Pares de la semilla: { pairs = { {id, a, b} }, ends = { extremo, ... },
-- reserve = { par, ... } (sitios de repuesto, ids a partir de 13), ends_all =
-- { puntos de pares, repuestos y nexus (x, y) }, nexus = { x, y, sx, sy, exits
-- = { [1..4] = {x, y, angle, dir} } } o nil } con extremo = { x, y, angle, pair, side ("a"/"b"), sx, sy }. x, y es el centro
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

-- true si (x, y) sirve de punto para un portal en runtime (destino de un
-- portal inestable, su posicion): mundo util, sin megaestructuras, planetas ni
-- spawn cerca. No mira el espaciado con otros extremos
function portals.valid_point(seed, x, y)
  local s = portals.sites(seed)
  if s.layout == nil then return false end
  return valid_basic(x, y, s.layout, s.rsites)
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
