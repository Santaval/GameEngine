-- =====================================================================
--  Sitios de los contenedores de suministros (#27): funcion pura de la
--  semilla, como map_chunks.lua (todos los clientes obtienen lo mismo sin
--  enviar nada). No usa math.random (ver map_grid.lua).
--  - Un contenedor como maximo por sector cuyo bioma este en
--    SUPPLY_CRATE.biomes (1 por cada 4 chunks), con su propio flujo
--    hash(seed, sx, sy, SALT_SUPPLY).
--  - Hasta `tries` intentos dentro del sector, a edge_pad del borde y fuera de
--    la franja de tormenta. Se descarta el punto a menos de planet_clear del
--    pozo de gravedad de un planeta, a menos de rock_clear del borde de una
--    roca de los 4 chunks del sector o dentro de la zona vedada de un portal.
--    Si ningun intento sirve, el sector se queda sin contenedor.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local biomes = require("map_biomes")
local chunks = require("map_chunks")
local portals = require("map_portals")
local asteroid_cfg = require("asteroid_config")

local S = cfg.SUPPLY_CRATE

local supply = {}

local cache = {}
local cached = 0
local MAX_CACHED = 4

local function in_list(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

-- Radio (px de mundo) del collider del contenedor: S.radius va en px del frame
local CRATE_RADIUS = S.radius * S.size / S.sheet.frame_w

-- Rocas de los chunks del sector como lista de { x, y, radius } (centro y radio
-- del cuerpo: scale x bodyRadius, como asteroid_field)
local function sector_rocks(seed, sx, sy)
  local list = {}
  local n = cfg.CHUNKS_PER_SECTOR
  local body = asteroid_cfg.ASTEROID_SHEET.bodyRadius
  local frame = asteroid_cfg.ASTEROID_SHEET.frameSize
  for cy = sy * n, sy * n + n - 1 do
    for cx = sx * n, sx * n + n - 1 do
      for _, s in ipairs(chunks.generate_chunk(seed, cx, cy)) do
        local half = frame * s.scale / 2
        list[#list + 1] = { x = s.pos.x + half, y = s.pos.y + half, radius = body * s.scale }
      end
    end
  end
  return list
end

-- Punto valido del sector (sx, sy) o nil
local function sector_slot(seed, sx, sy, planets, pends)
  local r = grid.rng(grid.hash(seed, sx, sy, grid.SALT_SUPPLY))
  local bx, by, bw, bh = grid.sector_bounds(sx, sy)
  local minX = math.max(bx, cfg.STORM_BAND) + S.edge_pad
  local minY = math.max(by, cfg.STORM_BAND) + S.edge_pad
  local maxX = math.min(bx + bw, cfg.WORLD_SIZE - cfg.STORM_BAND) - S.edge_pad
  local maxY = math.min(by + bh, cfg.WORLD_SIZE - cfg.STORM_BAND) - S.edge_pad
  if maxX <= minX or maxY <= minY then return nil end

  local rocks = sector_rocks(seed, sx, sy)

  for _ = 1, S.tries do
    -- Los dos sorteos van siempre, para que el flujo no dependa del rechazo
    local x = r.range(minX, maxX)
    local y = r.range(minY, maxY)
    local free = not portals.blocks(pends, x, y, CRATE_RADIUS)
    for _, p in ipairs(planets) do
      if not free then break end
      local dx, dy = x - p.x, y - p.y
      local min = p.range + S.planet_clear
      if dx * dx + dy * dy < min * min then free = false end
    end
    for _, k in ipairs(rocks) do
      if not free then break end
      local dx, dy = x - k.x, y - k.y
      local min = k.radius + CRATE_RADIUS + S.rock_clear
      if dx * dx + dy * dy < min * min then free = false end
    end
    if free then return { slot = sx .. ":" .. sy, x = x, y = y } end
  end
  return nil
end

-- Sitios de la semilla: lista de { slot = "sx:sy", x, y } (centro de la caja),
-- memoizada
function supply.slots(seed)
  local key = math.tointeger(seed) or seed
  local hit = cache[key]
  if hit ~= nil then return hit end

  local layout = biomes.layout(seed)
  local pends = portals.sites(seed).ends_all
  hit = {}
  for sy = 0, cfg.SECTORS - 1 do
    for sx = 0, cfg.SECTORS - 1 do
      if in_list(S.biomes, layout.biomes[sx][sy]) then
        local s = sector_slot(seed, sx, sy, layout.planets, pends)
        if s ~= nil then hit[#hit + 1] = s end
      end
    end
  end

  if cached >= MAX_CACHED then cache, cached = {}, 0 end
  cache[key] = hit
  cached = cached + 1
  return hit
end

return supply
