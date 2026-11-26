-- =====================================================================
--  Biomas del mapa de la Aval Cup y planetas de los sectores Planetary.
--  Todo sale de la semilla (map_grid.hash/rng, sin math.random) y no llama
--  al motor, asi que todos los clientes obtienen lo mismo sin enviar nada
--  por la red. Los datos viven en map_config.lua y solar_system_config.lua.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local solar = require("solar_system_config")

local biomes = {}

-- Cache por semilla: generate_chunk pide el layout una vez por chunk. Se
-- guardan pocas semillas para no acumular memoria
local MAX_CACHED = 8
local cache, cached = {}, 0

-- Indice de BIOMES por id
local function biome_by_id(id)
  for _, b in ipairs(cfg.BIOMES) do
    if b.id == id then return b end
  end
  return nil
end

-- Reparto de biomas: grid[sx][sy] = id. El sector central se elige primero
-- (entre CENTER_BIOMES, con sus pesos) y el resto en orden de lectura: cada
-- sector sortea entre los biomas que ninguno de sus vecinos ORTOGONALES ya
-- asignados tiene (las diagonales no cuentan). BIOME_REPEAT_OK siempre vale,
-- asi que nunca se queda sin opciones
function biomes.assign(seed)
  local r = grid.rng(grid.hash(seed, 0, 0, grid.SALT_BIOME))
  local n = cfg.SECTORS
  local result = {}
  for sx = 0, n - 1 do result[sx] = {} end

  local pool = {}
  for _, id in ipairs(cfg.CENTER_BIOMES) do pool[#pool + 1] = biome_by_id(id) end
  local mid = n // 2
  result[mid][mid] = (grid.pick_weighted(r, pool)).id

  local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
  for sy = 0, n - 1 do
    for sx = 0, n - 1 do
      if result[sx][sy] == nil then
        local taken = {}
        for _, d in ipairs(dirs) do
          local col = result[sx + d[1]]
          local id = col and col[sy + d[2]]
          if id ~= nil then taken[id] = true end
        end

        local allowed = {}
        for _, b in ipairs(cfg.BIOMES) do
          if b.id == cfg.BIOME_REPEAT_OK or not taken[b.id] then allowed[#allowed + 1] = b end
        end
        result[sx][sy] = (grid.pick_weighted(r, allowed)).id
      end
    end
  end

  return result
end

-- Plantillas de planeta: los cuerpos reales menos el Sol
local function templates()
  local list = {}
  for _, b in ipairs(solar.BODIES) do
    if b.name ~= "Sol" then list[#list + 1] = b end
  end
  return list
end

-- Planetas de un sector Planetary, en el formato de solar_system_config
-- (mas role y sector). Se colocan con rechazo: centros a >= PLANET_SPACING_FACTOR
-- veces la suma de sus range y con todo el pozo de gravedad dentro del sector.
-- Ningun pozo cubre el punto de aparicion (PLAYER_SPAWN + SPAWN_CLEAR_PAD).
-- Puede salir menos de los pedidos, pero siempre al menos uno (ver fallback)

-- true si un pozo de radio `range` centrado en (x, y) deja libre la aparicion
local function clear_of_spawn(x, y, range)
  local dx, dy = x - cfg.PLAYER_SPAWN.x, y - cfg.PLAYER_SPAWN.y
  local min = range + cfg.SPAWN_CLEAR_PAD
  return dx * dx + dy * dy >= min * min
end

-- Sitio de reserva del primer planeta cuando el rechazo no encontro hueco: el
-- centro del sector, o si ahi esta la aparicion, el cuerpo mas pequeno corrido
-- a su derecha justo fuera del margen. Devuelve body, x, y
local function fallback_spot(bx, by, bw, bh, body, bodies)
  local cx, cy = bx + bw / 2, by + bh / 2
  if clear_of_spawn(cx, cy, solar.planet_from_body(body).range) then return body, cx, cy end

  local smallest = bodies[1]
  for _, b in ipairs(bodies) do
    if b.radius < smallest.radius then smallest = b end
  end
  local range = solar.planet_from_body(smallest).range
  return smallest, cfg.PLAYER_SPAWN.x + range + cfg.SPAWN_CLEAR_PAD, cy
end

local function sector_planets(seed, sx, sy, bodies)
  local r = grid.rng(grid.hash(seed, sx, sy, grid.SALT_PLANET))
  local bx, by, bw, bh = grid.sector_bounds(sx, sy)
  local want = r.int(cfg.PLANETS_PER_SECTOR.min, cfg.PLANETS_PER_SECTOR.max)
  local list = {}

  for i = 1, want do
    local body = bodies[r.int(1, #bodies)]
    local p = solar.planet_from_body(body)
    local margin = p.range + cfg.PLANET_EDGE_PAD

    local px, py
    if bw > 2 * margin and bh > 2 * margin then
      for _ = 1, cfg.PLANET_TRIES do
        local x = r.range(bx + margin, bx + bw - margin)
        local y = r.range(by + margin, by + bh - margin)
        local free = clear_of_spawn(x, y, p.range)
        for _, o in ipairs(list) do
          if not free then break end
          local min = cfg.PLANET_SPACING_FACTOR * (p.range + o.range)
          local dx, dy = x - o.x, y - o.y
          if dx * dx + dy * dy < min * min then
            free = false
            break
          end
        end
        if free then
          px, py = x, y
          break
        end
      end
    end
    if px == nil and i == 1 then
      body, px, py = fallback_spot(bx, by, bw, bh, body, bodies)
      p = solar.planet_from_body(body)
    end

    local role = (grid.pick_weighted(r, cfg.PLANET_ROLES)).id
    if px ~= nil then
      p.name = body.name .. " " .. sx .. "-" .. sy
      p.assetId = body.assetId
      p.x, p.y = px, py
      p.role = role
      p.sector = { x = sx, y = sy }
      -- Solo los planetas mining se pueden minar
      if role ~= "mining" then
        p.mineral = nil
        p.mine_interval = nil
      end
      list[#list + 1] = p
    end
  end

  return list
end

-- Todos los planetas del mundo (solo en sectores Planetary)
function biomes.planets(seed, biome_grid)
  local bodies = templates()
  local list = {}
  for sy = 0, cfg.SECTORS - 1 do
    for sx = 0, cfg.SECTORS - 1 do
      if biome_grid[sx][sy] == "planetary" then
        for _, p in ipairs(sector_planets(seed, sx, sy, bodies)) do list[#list + 1] = p end
      end
    end
  end
  return list
end

-- { biomes = grid[sx][sy], planets = lista } de la semilla, memoizado
function biomes.layout(seed)
  local key = math.tointeger(seed) or seed
  local hit = cache[key]
  if hit ~= nil then return hit end

  if cached >= MAX_CACHED then cache, cached = {}, 0 end
  local b = biomes.assign(seed)
  hit = { biomes = b, planets = biomes.planets(seed, b) }
  cache[key] = hit
  cached = cached + 1
  return hit
end

return biomes
