-- =====================================================================
--  Generador PROVISIONAL del contenido de cada chunk: asteroides estaticos
--  repartidos con rechazo. Sirve para probar la semilla, el culling y la
--  sincronizacion de destruccion; los biomas reales llegan despues.
--  Es una funcion pura de (semilla, cx, cy): todos los clientes obtienen lo
--  mismo sin enviar nada por la red. No usa math.random (ver map_grid.lua).
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local asteroid_cfg = require("asteroid_config")

local chunks = {}

-- Intentos por roca: fijo, para que el resultado sea determinista
local TRIES_PER_ROCK = 30

-- Estado de spawn de una roca centrada en (cx, cy) (mismo formato que
-- asteroid_field.asteroid_state). pos es la esquina sup-izq del sprite
local function rock_state(cx, cy, scale, kind, rot, id)
  local drawSize = asteroid_cfg.ASTEROID_SHEET.frameSize * scale
  return {
    pos = { x = cx - drawSize / 2, y = cy - drawSize / 2 },
    vel = { x = 0, y = 0 },
    rot = rot,
    kind = kind,
    scale = scale,
    world = true,
    cull = true,
    chunk_id = id,
  }
end

-- Lista de estados de spawn de las rocas del chunk (cx, cy)
function chunks.generate_chunk(seed, cx, cy)
  local r = grid.rng(grid.hash(seed, cx, cy))
  local key = grid.chunk_key(cx, cy)
  local bodyRadius = asteroid_cfg.ASTEROID_SHEET.bodyRadius

  -- El chunk recortado a lo que queda dentro de la franja de tormenta
  local bx, by, bw, bh = grid.chunk_bounds(cx, cy)
  local minX = math.max(bx, cfg.STORM_BAND)
  local minY = math.max(by, cfg.STORM_BAND)
  local maxX = math.min(bx + bw, cfg.WORLD_SIZE - cfg.STORM_BAND)
  local maxY = math.min(by + bh, cfg.WORLD_SIZE - cfg.STORM_BAND)

  local list = {}
  if maxX <= minX or maxY <= minY then return list end

  local placed = {}
  local count = r.int(cfg.PLACEHOLDER_ROCKS.min, cfg.PLACEHOLDER_ROCKS.max)

  for _ = 1, count do
    for _ = 1, TRIES_PER_ROCK do
      local scale = r.range(cfg.ROCK_SCALE.min, cfg.ROCK_SCALE.max)
      local radius = bodyRadius * scale
      local x = r.range(minX + radius, maxX - radius)
      local y = r.range(minY + radius, maxY - radius)

      local free = true
      for _, other in ipairs(placed) do
        local dx, dy = x - other.x, y - other.y
        local min = other.radius + radius + cfg.ROCK_MIN_GAP
        if dx * dx + dy * dy < min * min then
          free = false
          break
        end
      end

      if free then
        placed[#placed + 1] = { x = x, y = y, radius = radius }
        local _, kind = asteroid_cfg.pickAsteroidType(r.next())
        local rot = r.range(0, 2 * math.pi)
        local id = key .. ":" .. #placed
        list[#list + 1] = rock_state(x, y, scale, kind, rot, id)
        break
      end
    end
  end

  return list
end

-- Todos los chunks del mundo: { ["cx:cy"] = lista de estados }
function chunks.generate_world(seed)
  local world = {}
  local total = cfg.SECTORS * cfg.CHUNKS_PER_SECTOR
  for cy = 0, total - 1 do
    for cx = 0, total - 1 do
      world[grid.chunk_key(cx, cy)] = chunks.generate_chunk(seed, cx, cy)
    end
  end
  return world
end

return chunks
