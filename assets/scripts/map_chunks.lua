-- =====================================================================
--  Generador del contenido de cada chunk segun el bioma de su sector
--  (map_biomes.lua): rocas grandes y pequenas repartidas con Poisson-disk,
--  algunas a la deriva y pecios que sueltan recursos extra. Los planetas son
--  del sector, no del chunk (map_biomes.planets) y las rocas los esquivan.
--  Es una funcion pura de (semilla, cx, cy): todos los clientes obtienen lo
--  mismo sin enviar nada por la red. No usa math.random (ver map_grid.lua).
--  Cada concepto (rocas, deriva, pecios) usa su propio flujo aleatorio, asi
--  que tocar un ajuste no baraja el resto.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local biomes = require("map_biomes")
local field = require("asteroid_field")
local asteroid_cfg = require("asteroid_config")

local chunks = {}

-- Margen extra (px) entre el borde de una roca grande y el de una pequena
local LARGE_SMALL_PAD = 20

-- Estado de spawn de una roca centrada en (x, y) (mismo formato que
-- asteroid_field.asteroid_state). pos es la esquina sup-izq del sprite
local function rock_state(x, y, scale, kind, rot, id)
  local drawSize = asteroid_cfg.ASTEROID_SHEET.frameSize * scale
  return {
    pos = { x = x - drawSize / 2, y = y - drawSize / 2 },
    vel = { x = 0, y = 0 },
    rot = rot,
    kind = kind,
    scale = scale,
    world = true,
    cull = true,
    chunk_id = id,
  }
end

local function in_list(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

-- Cantidad al azar de un rango { min, max }
local function pick_count(r, range)
  return r.int(range.min, range.max)
end

-- true si un disco de radio `radius` en (x, y) toca el pozo de gravedad de
-- algun planeta (se revisan todos: es una lista corta)
local function touches_planet(planets, x, y, radius)
  for _, p in ipairs(planets) do
    local dx, dy = x - p.x, y - p.y
    local min = p.range + radius
    if dx * dx + dy * dy < min * min then return true end
  end
  return false
end

-- true si el rayo que sale de (x, y) con direccion unitaria (ux, uy) se queda
-- a mas de planet.range + radius de todos los planetas. Si el punto mas
-- cercano queda "detras" (t < 0) cuenta la distancia al origen del rayo
local function ray_is_clear(planets, x, y, ux, uy, radius)
  for _, p in ipairs(planets) do
    local rx, ry = p.x - x, p.y - y
    local t = rx * ux + ry * uy
    local d2
    if t < 0 then
      d2 = rx * rx + ry * ry
    else
      local cx, cy = rx - t * ux, ry - t * uy
      d2 = cx * cx + cy * cy
    end
    local min = p.range + radius
    if d2 <= min * min then return false end
  end
  return true
end

-- Lista de estados de spawn de las rocas del chunk (cx, cy)
function chunks.generate_chunk(seed, cx, cy)
  local key = grid.chunk_key(cx, cy)
  local list = {}

  -- El chunk recortado a lo que queda dentro de la franja de tormenta
  local bx, by, bw, bh = grid.chunk_bounds(cx, cy)
  local minX = math.max(bx, cfg.STORM_BAND)
  local minY = math.max(by, cfg.STORM_BAND)
  local maxX = math.min(bx + bw, cfg.WORLD_SIZE - cfg.STORM_BAND)
  local maxY = math.min(by + bh, cfg.WORLD_SIZE - cfg.STORM_BAND)
  if maxX <= minX or maxY <= minY then return list end
  local rect = { x = minX, y = minY, width = maxX - minX, height = maxY - minY }

  local layout = biomes.layout(seed)
  local sx, sy = grid.world_to_sector(bx, by)
  local biome = layout.biomes[sx][sy]
  local planets = layout.planets

  local function reject(x, y, radius)
    return touches_planet(planets, x, y, radius)
  end

  local r = grid.rng(grid.hash(seed, cx, cy, grid.SALT_ROCKS))
  local sizes = cfg.ROCK_SIZES

  -- Rocas grandes (mas en dense_belt)
  local largeRange = biome == "dense_belt" and cfg.LARGE_ROCKS_DENSE or cfg.LARGE_ROCKS
  local large = field.poisson_points({
    rng = r, rect = rect, count = pick_count(r, largeRange),
    min_dist = cfg.LARGE_SPACING, tries = cfg.ROCK_TRIES,
    scale = sizes.large, reject = reject,
  })
  for _, p in ipairs(large) do p.large = true end

  -- Rocas medianas y pequenas a partes iguales (ninguna en deep_void). Contra
  -- las grandes guardan sus radios mas un margen; entre ellas SMALL_SPACING
  local medium, small = {}, {}
  if biome ~= "deep_void" then
    local smallCount = pick_count(r, cfg.SMALL_ROCKS)
    local existing = {}
    for _, p in ipairs(large) do existing[#existing + 1] = p end

    local function cross_dist(radius, other)
      if other.large then
        return math.max(cfg.SMALL_SPACING, radius + other.radius + LARGE_SMALL_PAD)
      end
      return cfg.SMALL_SPACING
    end

    medium = field.poisson_points({
      rng = r, rect = rect, count = smallCount - smallCount // 2,
      min_dist = cfg.SMALL_SPACING, tries = cfg.ROCK_TRIES,
      scale = sizes.medium, existing = existing, cross_dist = cross_dist, reject = reject,
    })
    for _, p in ipairs(medium) do existing[#existing + 1] = p end

    small = field.poisson_points({
      rng = r, rect = rect, count = smallCount // 2,
      min_dist = cfg.SMALL_SPACING, tries = cfg.ROCK_TRIES,
      scale = sizes.small, existing = existing, cross_dist = cross_dist, reject = reject,
    })
  end

  -- Todas las rocas, en orden fijo: grandes, medianas, pequenas
  local all = {}
  for _, p in ipairs(large) do all[#all + 1] = p end
  for _, p in ipairs(medium) do all[#all + 1] = p end
  for _, p in ipairs(small) do all[#all + 1] = p end

  for i, p in ipairs(all) do
    local _, kind = asteroid_cfg.pickAsteroidType(r.next())
    local rot = r.range(0, 2 * math.pi)
    list[i] = rock_state(p.x, p.y, p.scale, kind, rot, key .. ":" .. i)
  end

  -- Pecio: una roca grande del chunk (nunca a la deriva) en debris y reactor
  local wreckIndex = nil
  if in_list(cfg.WRECK_BIOMES, biome) and #large > 0 then
    local w = grid.rng(grid.hash(seed, cx, cy, grid.SALT_WRECK))
    if w.next() < cfg.WRECK_CHANCE then
      wreckIndex = w.int(1, #large)
      list[wreckIndex].wreck = w.int(1, #asteroid_cfg.WRECK_TYPES)
    end
  end

  -- Deriva: la roca sale con velocidad constante en un rumbo que no cruce la
  -- gravedad de ningun planeta (si no encuentra rumbo se queda quieta). No se
  -- duerme con el culling y el host la borra al salir del mundo
  local d = grid.rng(grid.hash(seed, cx, cy, grid.SALT_DRIFT))
  for i, p in ipairs(all) do
    if i ~= wreckIndex and d.next() < cfg.DRIFT.chance then
      for _ = 1, cfg.DRIFT.tries do
        local a = d.range(0, 2 * math.pi)
        local ux, uy = math.cos(a), math.sin(a)
        if ray_is_clear(planets, p.x, p.y, ux, uy, p.radius) then
          local speed = d.range(cfg.DRIFT.speed.min, cfg.DRIFT.speed.max)
          local s = list[i]
          s.vel = { x = ux * speed, y = uy * speed }
          s.cull = nil
          s.despawn_far = true
          s.drift = true
          break
        end
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
