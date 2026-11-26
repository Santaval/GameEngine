-- =====================================================================
--  Megaestructuras del Reactor Remains: un sitio por sector reactor, con la
--  variante (anillo o casco modular), su giro, las piezas dibujadas, los
--  circulos de colision y los huecos por los que pasa una nave. Es una
--  funcion pura de la semilla, como map_biomes: todos los clientes obtienen
--  lo mismo sin enviar nada por la red. No llama al motor ni usa math.random
--  (el flujo propio es grid.SALT_REACTOR). Las plantillas y el plano del
--  casco viven en map_reactor_data.lua.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local biomes = require("map_biomes")
local data = require("map_reactor_data")

local R = cfg.REACTOR

local reactor = {}

-- Cache por semilla, como map_biomes.layout
local MAX_CACHED = 8
local cache, cached = {}, 0

-- Giros de cuartos de vuelta (horario en pantalla, +y hacia abajo), exactos
local COS = { [0] = 1, 0, -1, 0 }
local SIN = { [0] = 0, 1, 0, -1 }

local function rotate(x, y, q)
  q = q % 4
  return x * COS[q] - y * SIN[q], x * SIN[q] + y * COS[q]
end

-- Circulos { x, y, r } (px respecto al centro de la pieza) de una plantilla de
-- map_reactor_data para una pieza cuya unidad mide `unit` px
local function expand(template, unit)
  local out = {}
  for _, s in ipairs(template.shapes) do
    if s.kind == "line" then
      local dx, dy = s.x2 - s.x1, s.y2 - s.y1
      local len = math.sqrt(dx * dx + dy * dy)
      local usable = len - 2 * s.hw
      local n = 1
      if usable > 0 then n = math.ceil(usable / (data.STEP * s.hw)) + 1 end
      for i = 0, n - 1 do
        local t = 0.5
        if n > 1 then t = (s.hw + usable * i / (n - 1)) / len end
        out[#out + 1] = { x = (s.x1 + dx * t) * unit, y = (s.y1 + dy * t) * unit, r = s.hw * unit }
      end
    elseif s.kind == "grid" then
      for i = 0, s.nx - 1 do
        for j = 0, s.ny - 1 do
          local fx = s.nx > 1 and i / (s.nx - 1) or 0.5
          local fy = s.ny > 1 and j / (s.ny - 1) or 0.5
          local x = s.nx > 1 and (s.x1 + s.r + (s.x2 - s.x1 - 2 * s.r) * fx) or (s.x1 + s.x2) / 2
          local y = s.ny > 1 and (s.y1 + s.r + (s.y2 - s.y1 - 2 * s.r) * fy) or (s.y1 + s.y2) / 2
          out[#out + 1] = { x = x * unit, y = y * unit, r = s.r * unit }
        end
      end
    elseif s.kind == "arc" then
      -- El primer y el ultimo circulo se meten hw/R radianes: el borde del
      -- circulo cae justo en el extremo del arco del arte
      local inset = s.hw / s.R
      local a0, a1 = math.rad(s.from) + inset, math.rad(s.to) - inset
      local n = math.ceil((a1 - a0) / math.rad(s.step)) + 1
      for i = 0, n - 1 do
        local a = n > 1 and (a0 + (a1 - a0) * i / (n - 1)) or (a0 + a1) / 2
        out[#out + 1] = { x = s.R * math.cos(a) * unit, y = s.R * math.sin(a) * unit, r = s.hw * unit }
      end
    end
  end
  return out
end

-- Anade a `site` una pieza dibujada y sus circulos. piece = { asset, x, y, rot,
-- w, h } con x, y en px respecto al centro del sitio y rot en cuartos de vuelta;
-- siteQ (cuartos de vuelta) gira el sitio entero
local function add_piece(site, piece, siteQ)
  local px, py = rotate(piece.x, piece.y, siteQ)
  local q = (piece.rot + siteQ) % 4
  local wx, wy = site.x + px, site.y + py
  site.pieces[#site.pieces + 1] = { asset = piece.asset, x = wx, y = wy, w = piece.w, h = piece.h,
    rot = q * math.pi / 2 }

  -- La unidad de la plantilla es el alto de la pieza (el ancho en el anillo)
  local unit = piece.asset == "ring" and piece.w or piece.h
  for _, c in ipairs(expand(data.TEMPLATES[piece.asset], unit)) do
    local rx, ry = rotate(c.x, c.y, q)
    site.colliders[#site.colliders + 1] = { x = wx + rx, y = wy + ry, r = c.r }
  end
end

-- Radio exterior del sitio: lo que alcanza el circulo mas lejano
local function outer_radius(site)
  local radius = 0
  for _, c in ipairs(site.colliders) do
    local d = math.sqrt((c.x - site.x) ^ 2 + (c.y - site.y) ^ 2) + c.r
    if d > radius then radius = d end
  end
  return radius
end

local function build_site(seed, sx, sy, index)
  local bx, by, bw, bh = grid.sector_bounds(sx, sy)
  local r = grid.rng(grid.hash(seed, sx, sy, grid.SALT_REACTOR))

  local pool = {}
  for _, id in ipairs(data.VARIANTS) do pool[#pool + 1] = { id = id, weight = R.variants[id] or 0 } end
  local variant = (grid.pick_weighted(r, pool)).id
  local siteQ = r.int(0, 3)

  local site = {
    index = index, sx = sx, sy = sy, x = bx + bw / 2, y = by + bh / 2,
    variant = variant, rot = siteQ * math.pi / 2,
    pieces = {}, colliders = {}, gaps = {},
  }

  if variant == "ring" then
    for _, piece in ipairs(data.ring_layout()) do add_piece(site, piece, siteQ) end
    local ring = data.TEMPLATES.ring
    for _, deg in ipairs(ring.gaps) do
      local a = math.rad(deg)
      local gx, gy = rotate(ring.gap_radius * R.ring_size * math.cos(a), ring.gap_radius * R.ring_size * math.sin(a), siteQ)
      site.gaps[#site.gaps + 1] = { x = site.x + gx, y = site.y + gy }
    end
  else
    local side, cover = data.hull_layout()
    -- Cuatro lados girados 90 grados (molinete), cada uno con su hueco
    for k = 0, 3 do
      for _, piece in ipairs(side.pieces) do
        local x, y = rotate(piece.x, piece.y, k)
        add_piece(site, { asset = piece.asset, x = x, y = y, rot = piece.rot + k, w = piece.w, h = piece.h }, siteQ)
      end
      local gx, gy = rotate(side.gap.x, side.gap.y, k + siteQ)
      site.gaps[#site.gaps + 1] = { x = site.x + gx, y = site.y + gy }
    end
    for _, piece in ipairs(cover) do add_piece(site, piece, siteQ) end
  end

  -- Nucleo en el centro: lo dibuja y lleva su propio collider reactor_core.lua
  -- (no entra en colliders); el director lo anima
  site.core = { x = site.x, y = site.y, size = R.core_size }

  site.radius = outer_radius(site)
  return site
end

-- Sitios de la semilla, uno por sector reactor, en orden de lectura:
-- { index, sx, sy, x, y, variant, rot, pieces, colliders, core, radius, gaps }.
-- pieces = { {asset, x, y, w, h, rot} } (centro en el mundo, rot en radianes),
-- colliders = { {x, y, r} } en px de mundo y gaps = { {x, y} }: el punto medio
-- de cada hueco. Memoizado por semilla
function reactor.sites(seed)
  local key = math.tointeger(seed) or seed
  local hit = cache[key]
  if hit ~= nil then return hit end

  if cached >= MAX_CACHED then cache, cached = {}, 0 end
  local layout = biomes.layout(seed)
  hit = {}
  for sy = 0, cfg.SECTORS - 1 do
    for sx = 0, cfg.SECTORS - 1 do
      if layout.biomes[sx][sy] == "reactor" then
        hit[#hit + 1] = build_site(seed, sx, sy, #hit + 1)
      end
    end
  end
  cache[key] = hit
  cached = cached + 1
  return hit
end

-- true si un disco de radio `radius` en (x, y) toca la zona vedada de algun
-- sitio (su radio exterior mas clear_pad): ahi no nacen rocas
function reactor.blocks(sites, x, y, radius)
  for _, s in ipairs(sites) do
    local dx, dy = x - s.x, y - s.y
    local min = s.radius + R.clear_pad + radius
    if dx * dx + dy * dy < min * min then return true end
  end
  return false
end

return reactor
