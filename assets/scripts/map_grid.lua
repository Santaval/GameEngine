-- =====================================================================
--  Rejilla del mundo (sectores y chunks) y generador pseudoaleatorio
--  determinista del mapa. Todo se lee de map_config.lua.
--  NO usa math.random: es el rand() de C (distinto entre plataformas y
--  compartido con el resto del juego). Hash y RNG usan solo enteros de 32
--  bits (mascara & 0xFFFFFFFF), asi que dan lo mismo en todas las maquinas.
-- =====================================================================

local cfg = require("map_config")

local grid = {}

local MASK = 0xFFFFFFFF
local CHUNKS = cfg.SECTORS * cfg.CHUNKS_PER_SECTOR

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Entero de cualquier numero (la semilla puede llegar como float desde JSON)
local function toint(v)
  return math.tointeger(v) or math.tointeger(math.floor(v))
end

-- Sector (0..SECTORS-1) que contiene el punto, recortado al mundo
function grid.world_to_sector(x, y)
  local sx = math.floor(x / cfg.SECTOR_SIZE)
  local sy = math.floor(y / cfg.SECTOR_SIZE)
  return clamp(sx, 0, cfg.SECTORS - 1), clamp(sy, 0, cfg.SECTORS - 1)
end

-- Chunk (0..SECTORS*CHUNKS_PER_SECTOR-1) que contiene el punto, recortado al mundo
function grid.world_to_chunk(x, y)
  local cx = math.floor(x / cfg.CHUNK_SIZE)
  local cy = math.floor(y / cfg.CHUNK_SIZE)
  return clamp(cx, 0, CHUNKS - 1), clamp(cy, 0, CHUNKS - 1)
end

-- Rectangulo del sector en px de mundo: x, y, ancho, alto
function grid.sector_bounds(sx, sy)
  return sx * cfg.SECTOR_SIZE, sy * cfg.SECTOR_SIZE, cfg.SECTOR_SIZE, cfg.SECTOR_SIZE
end

-- Rectangulo del chunk en px de mundo: x, y, ancho, alto
function grid.chunk_bounds(cx, cy)
  return cx * cfg.CHUNK_SIZE, cy * cfg.CHUNK_SIZE, cfg.CHUNK_SIZE, cfg.CHUNK_SIZE
end

function grid.chunk_key(cx, cy)
  return cx .. ":" .. cy
end

-- Finalizador de murmur3 (fmix32), todo en 32 bits
local function fmix32(h)
  h = h ~ (h >> 16)
  h = (h * 0x85EBCA6B) & MASK
  h = h ~ (h >> 13)
  h = (h * 0xC2B2AE35) & MASK
  h = h ~ (h >> 16)
  return h
end

-- Hash de 32 bits de (semilla, chunk): mismo trio -> mismo valor en cualquier
-- cliente. Se mezcla cada componente con un primo distinto. salt (opcional)
-- separa flujos independientes (biomas, planetas, deriva, pecios): sin salt el
-- resultado es el de siempre
function grid.hash(seed, cx, cy, salt)
  seed, cx, cy = toint(seed), toint(cx), toint(cy)
  local h = fmix32((seed & MASK) ~ 0x9E3779B9)
  h = fmix32(h ~ (((cx + 1) * 0x27D4EB2F) & MASK))
  h = fmix32(h ~ (((cy + 1) * 0x165667B1) & MASK))
  if salt ~= nil then
    h = fmix32(h ~ (((toint(salt) + 1) * 0x85EBCA77) & MASK))
  end
  return h
end

-- Sales de cada flujo aleatorio de la generacion
grid.SALT_BIOME = 1
grid.SALT_PLANET = 2
grid.SALT_ROCKS = 3
grid.SALT_DRIFT = 4
grid.SALT_WRECK = 5
grid.SALT_NEBULA = 6
grid.SALT_REACTOR = 7
grid.SALT_PORTAL = 8
grid.SALT_NEXUS = 9

-- Generador mulberry32 sembrado con `state` (entero de 32 bits). Devuelve un
-- objeto con next() en [0,1), range(a,b) real y int(a,b) entero (ambos
-- inclusivos en sus extremos)
function grid.rng(state)
  local s = toint(state) & MASK

  local obj = {}

  function obj.next()
    s = (s + 0x6D2B79F5) & MASK
    local t = s
    t = ((t ~ (t >> 15)) * (t | 1)) & MASK
    t = t ~ ((t + (((t ~ (t >> 7)) * (t | 61)) & MASK)) & MASK)
    t = (t ~ (t >> 14)) & MASK
    return t / 4294967296
  end

  function obj.range(a, b)
    return a + obj.next() * (b - a)
  end

  function obj.int(a, b)
    return a + math.floor(obj.next() * (b - a + 1))
  end

  return obj
end

-- Elige un elemento de list = { {weight = n, ...}, ... } con probabilidad
-- proporcional a su weight, usando el rng r. Devuelve el elemento y su indice
function grid.pick_weighted(r, list)
  local total = 0
  for _, item in ipairs(list) do total = total + item.weight end
  local roll = r.next() * total
  for i, item in ipairs(list) do
    roll = roll - item.weight
    if roll < 0 then return item, i end
  end
  return list[#list], #list
end

-- Rectangulo del mundo que cubren los chunks a UPDATE_RADIUS_CHUNKS del chunk
-- que contiene (x, y), recortado al mundo: minX, minY, maxX, maxY
function grid.active_bounds(x, y)
  local cx, cy = grid.world_to_chunk(x, y)
  local r = cfg.UPDATE_RADIUS_CHUNKS
  local minCx, minCy = clamp(cx - r, 0, CHUNKS - 1), clamp(cy - r, 0, CHUNKS - 1)
  local maxCx, maxCy = clamp(cx + r, 0, CHUNKS - 1), clamp(cy + r, 0, CHUNKS - 1)
  return minCx * cfg.CHUNK_SIZE, minCy * cfg.CHUNK_SIZE,
         (maxCx + 1) * cfg.CHUNK_SIZE, (maxCy + 1) * cfg.CHUNK_SIZE
end

return grid
