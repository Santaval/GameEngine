-- =====================================================================
--  Nebulosas de la Aval Cup: densidad por ruido, "esta dentro de la nube" y
--  colocacion de las nubes. Modulo puro: no llama al motor ni usa math.random
--  (solo map_grid.hash/rng), asi que todos los clientes obtienen lo mismo.
--  Lo usan map_visuals (nubes y vineta) y solar_hud (ocultar naves en el
--  minimapa). Los datos viven en map_config.lua (config.NEBULA).
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")

local nebula = {}

local N = cfg.NEBULA

-- Cache de nubes por semilla (pocas, para no acumular memoria)
local MAX_CACHED = 8
local cache, cached = {}, 0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function smoothstep(t)
  return t * t * (3 - 2 * t)
end

-- Valor del reticulo en [0,1]
local function lattice(seed, ix, iy)
  return grid.hash(seed, ix, iy, grid.SALT_NEBULA) / 4294967296
end

-- Ruido de valor: interpolacion bilineal suavizada entre valores del reticulo
local function value_noise(seed, x, y)
  local fx, fy = math.floor(x), math.floor(y)
  local tx, ty = smoothstep(x - fx), smoothstep(y - fy)
  local a = lattice(seed, fx, fy)
  local b = lattice(seed, fx + 1, fy)
  local c = lattice(seed, fx, fy + 1)
  local d = lattice(seed, fx + 1, fy + 1)
  local top = a + (b - a) * tx
  local bottom = c + (d - c) * tx
  return top + (bottom - top) * ty
end

-- Densidad en [0,1] del punto: 2 octavas de ruido por la caida hacia el borde
-- del sector (la nube no llega al borde y el contorno queda irregular)
function nebula.density(seed, x, y)
  local u, v = x / N.cell, y / N.cell
  local n = value_noise(seed, u, v) * 0.65 + value_noise(seed, u * 2 + 17, v * 2 + 31) * 0.35

  local sx, sy = grid.world_to_sector(x, y)
  local bx, by, bw, bh = grid.sector_bounds(sx, sy)
  local dist = math.min(x - bx, bx + bw - x, y - by, by + bh - y)
  return n * clamp(dist / N.edge_pad, 0, 1)
end

-- true si el punto esta dentro de una nube: sector Nebula y densidad sobre el umbral
function nebula.inside(seed, biome_grid, x, y)
  local sx, sy = grid.world_to_sector(x, y)
  local col = biome_grid[sx]
  if col == nil or col[sy] ~= "nebula" then return false end
  return nebula.density(seed, x, y) > N.threshold
end

-- Nubes de todo el mundo agrupadas por sector: clouds[grid.chunk_key(sx, sy)] =
-- { {x, y, size, asset, front}, ... } (x, y es el centro)
function nebula.clouds(seed, biome_grid)
  local hit = cache[seed]
  if hit ~= nil then return hit end

  local result = {}
  for sx = 0, cfg.SECTORS - 1 do
    for sy = 0, cfg.SECTORS - 1 do
      if biome_grid[sx][sy] == "nebula" then
        local list = {}
        local r = grid.rng(grid.hash(seed, sx, sy, grid.SALT_NEBULA + 100))
        local bx, by, bw, bh = grid.sector_bounds(sx, sy)
        local step = N.cloud_spacing
        for gx = 0, math.floor(bw / step) do
          for gy = 0, math.floor(bh / step) do
            -- Se sortea siempre lo mismo por punto para que el flujo sea fijo
            local jx, jy = r.range(-0.4, 0.4) * step, r.range(-0.4, 0.4) * step
            local size = r.range(N.cloud_size.min, N.cloud_size.max)
            local variant = r.int(1, 4)
            local front = r.int(1, 3) == 1
            local x, y = bx + gx * step + jx, by + gy * step + jy
            if nebula.inside(seed, biome_grid, x, y) then
              list[#list + 1] = { x = x, y = y, size = size,
                asset = string.format("nebula-cloud-%02d", variant), front = front }
            end
          end
        end
        result[grid.chunk_key(sx, sy)] = list
      end
    end
  end

  if cached >= MAX_CACHED then cache, cached = {}, 0 end
  cache[seed] = result
  cached = cached + 1
  return result
end

return nebula
