-- Prueba de determinismo del mapa (issue #16). Se corre desde la raiz del repo:
--   lua5.3 tests/map_determinism.lua
-- Sin motor: solo map_config, map_grid, map_chunks y asteroid_config.

package.path = "./assets/scripts/?.lua;" .. package.path

-- math.random no puede intervenir en la generacion del mapa: si alguien lo usa,
-- la prueba falla en vez de pasar por casualidad
math.random = function()
  error("math.random no se debe usar en la generacion del mapa")
end

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. " (esperado " .. tostring(b) .. ", obtenido " .. tostring(a) .. ")")
end

local cfg = require("map_config")
local grid = require("map_grid")
local chunks = require("map_chunks")

-- Serializa todo el mundo a un string: posiciones, tipos, escalas, rotaciones e ids
local function serialize(world)
  local keys = {}
  for key in pairs(world) do keys[#keys + 1] = key end
  -- Orden estable sin table.sort: insercion simple
  for i = 2, #keys do
    local v, j = keys[i], i - 1
    while j >= 1 and keys[j] > v do
      keys[j + 1] = keys[j]
      j = j - 1
    end
    keys[j + 1] = v
  end

  local parts = {}
  for _, key in ipairs(keys) do
    for _, s in ipairs(world[key]) do
      parts[#parts + 1] = string.format("%s|%.6f,%.6f|k%d|s%.6f|r%.6f", s.chunk_id,
        s.pos.x, s.pos.y, s.kind, s.scale, s.rot)
    end
  end
  return table.concat(parts, ";")
end

-- Misma semilla -> mismo mundo; otra semilla -> otro mundo
local a = serialize(chunks.generate_world(12345))
local b = serialize(chunks.generate_world(12345))
local c = serialize(chunks.generate_world(54321))
check(#a > 0, "el mundo no esta vacio")
check(a == b, "generate_world(12345) es identico en dos llamadas")
check(a ~= c, "una semilla distinta da un mundo distinto")

-- Cada chunk tiene rocas dentro de los limites y fuera de la franja de tormenta
local world = chunks.generate_world(12345)
local total = 0
for cy = 0, cfg.SECTORS * cfg.CHUNKS_PER_SECTOR - 1 do
  for cx = 0, cfg.SECTORS * cfg.CHUNKS_PER_SECTOR - 1 do
    local list = world[grid.chunk_key(cx, cy)]
    check(list ~= nil, "existe el chunk " .. cx .. ":" .. cy)
    total = total + #list
    check(#list <= cfg.PLACEHOLDER_ROCKS.max, "no mas rocas que el maximo en " .. cx .. ":" .. cy)
    for _, s in ipairs(list) do
      check(s.pos.x >= 0 and s.pos.x < cfg.WORLD_SIZE and s.pos.y >= 0 and s.pos.y < cfg.WORLD_SIZE,
        "roca dentro del mundo: " .. s.chunk_id)
      check(s.cull == true and s.world == true, "roca con cull y world: " .. s.chunk_id)
    end
  end
end
check(total > 0, "se generaron rocas")

-- Hash y RNG
eq(grid.hash(1, 2, 3), grid.hash(1, 2, 3), "hash estable")
check(grid.hash(1, 2, 3) ~= grid.hash(1, 3, 2), "hash distingue cx de cy")
check(grid.hash(1, 2, 3) ~= grid.hash(2, 2, 3), "hash depende de la semilla")
check(grid.hash(1, 2, 3) <= 0xFFFFFFFF, "hash cabe en 32 bits")
local r1, r2 = grid.rng(99), grid.rng(99)
for _ = 1, 50 do
  local v = r1.next()
  check(v >= 0 and v < 1, "next() en [0,1)")
  eq(v, r2.next(), "rng reproducible")
end
local r3 = grid.rng(7)
for _ = 1, 200 do
  local n = r3.int(3, 5)
  check(n >= 3 and n <= 5 and math.type(n) == "integer", "int(3,5) entero en rango")
end

-- Ayudantes de rejilla
local sx, sy = grid.world_to_sector(19999, 0)
eq(sx, 4, "world_to_sector x"); eq(sy, 0, "world_to_sector y")
sx, sy = grid.world_to_sector(99999, -5)
eq(sx, 4, "world_to_sector recorta x"); eq(sy, 0, "world_to_sector recorta y")
local cx, cy = grid.world_to_chunk(2000, 3999)
eq(cx, 1, "world_to_chunk x"); eq(cy, 1, "world_to_chunk y")
local bx, by, bw, bh = grid.sector_bounds(2, 2)
eq(bx, 8000, "sector_bounds x"); eq(by, 8000, "sector_bounds y")
eq(bw, 4000, "sector_bounds w"); eq(bh, 4000, "sector_bounds h")
eq(grid.chunk_key(3, 7), "3:7", "chunk_key")
local minX, minY, maxX, maxY = grid.active_bounds(0, 0)
eq(minX, 0, "active_bounds minX"); eq(minY, 0, "active_bounds minY")
eq(maxX, 6000, "active_bounds maxX"); eq(maxY, 6000, "active_bounds maxY")
minX, minY, maxX, maxY = grid.active_bounds(10000, 10000)
eq(minX, 6000, "active_bounds centro minX"); eq(maxX, 16000, "active_bounds centro maxX")

if failures == 0 then
  print("map_determinism: all passed")
else
  print("map_determinism: " .. failures .. " failures")
  os.exit(1)
end
