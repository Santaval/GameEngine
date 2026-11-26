-- =====================================================================
--  Visuales de bioma de la Aval Cup (entidad director, solo script):
--  - Fondo de cada bioma en teselas con paralaje; en los bordes de sector se
--    mezclan los de los sectores vecinos (crossfade continuo, sin saltos).
--  - Nubes de nebulosa (map_nebula): las de atras en el mundo, las de delante
--    con un paralaje mayor y sobre las naves.
--  - Vineta mientras la nave local esta dentro de una nube (aparece y se
--    desvanece) y el global local_in_nebula para otros scripts.
--  No hace nada hasta que aval_cup_world.lua fija map_biomes y map_seed.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local nebula = require("map_nebula")

local N = cfg.NEBULA

local vignette_alpha = 0
local_in_nebula = false

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function smoothstep(t)
  return t * t * (3 - 2 * t)
end

-- Peso (0..1) del sector propio en un eje: 1 lejos del borde, 0.5 justo en el
-- borde. pos es la coordenada del centro de camara; devuelve tambien el signo
-- hacia el vecino mas cercano (-1 o +1)
local function axis_weight(pos)
  local size = cfg.SECTOR_SIZE
  local s = clamp(math.floor(pos / size), 0, cfg.SECTORS - 1)
  local local_pos = pos - s * size
  local dir, dist
  if local_pos < size / 2 then dir, dist = -1, local_pos else dir, dist = 1, size - local_pos end
  local t = clamp(dist / cfg.BG_BLEND, 0, 1)
  return s, dir, 0.5 + 0.5 * smoothstep(t)
end

local function biome_at(sx, sy)
  local col = map_biomes[sx]
  return col and col[sy] or nil
end

-- Fondo mezclado: se suma el peso por asset y se dibuja de mayor a menor peso
-- con alpha_i = 255 * w_i / suma acumulada (el resultado es una lerp exacta)
local function draw_backgrounds(camX, camY, w, h)
  local sx, dx, wx = axis_weight(camX + w / 2)
  local sy, dy, wy = axis_weight(camY + h / 2)

  local weights = {}
  local function add(x, y, weight)
    if weight <= 0 then return end
    -- Fuera del mundo se usa el sector propio
    local id = biome_at(x, y) or biome_at(sx, sy)
    local asset = cfg.BIOME_BACKGROUNDS[id]
    if asset ~= nil then weights[asset] = (weights[asset] or 0) + weight end
  end
  add(sx, sy, wx * wy)
  add(sx + dx, sy, (1 - wx) * wy)
  add(sx, sy + dy, wx * (1 - wy))
  add(sx + dx, sy + dy, (1 - wx) * (1 - wy))

  -- Orden por insercion (no hay libreria table): de mayor a menor peso y, si
  -- empatan, por nombre, para que el orden no dependa de pairs()
  local list = {}
  for asset, weight in pairs(weights) do
    local item = { asset = asset, w = weight }
    local i = #list
    while i > 0 and (list[i].w < item.w or (list[i].w == item.w and list[i].asset > item.asset)) do
      list[i + 1] = list[i]
      i = i - 1
    end
    list[i + 1] = item
  end

  local tile = cfg.BG_TILE
  local offX = -((camX * cfg.BG_PARALLAX) % tile)
  local offY = -((camY * cfg.BG_PARALLAX) % tile)
  local cols, rows = math.ceil(w / tile) + 1, math.ceil(h / tile) + 1

  local acc = 0
  for _, item in ipairs(list) do
    acc = acc + item.w
    local alpha = math.floor(255 * item.w / acc + 0.5)
    for i = 0, cols - 1 do
      for j = 0, rows - 1 do
        draw_image(item.asset, offX + i * tile, offY + j * tile, tile, tile, alpha, "back")
      end
    end
  end
end

-- Nubes de los sectores cercanos a la camara; las que no se ven se saltan
local function draw_clouds(camX, camY, w, h)
  local clouds = nebula.clouds(map_seed, map_biomes)
  local size = cfg.SECTOR_SIZE
  local minSx = clamp(math.floor((camX - 2000) / size), 0, cfg.SECTORS - 1)
  local maxSx = clamp(math.floor((camX + w + 2000) / size), 0, cfg.SECTORS - 1)
  local minSy = clamp(math.floor((camY - 2000) / size), 0, cfg.SECTORS - 1)
  local maxSy = clamp(math.floor((camY + h + 2000) / size), 0, cfg.SECTORS - 1)

  for sx = minSx, maxSx do
    for sy = minSy, maxSy do
      local list = clouds[grid.chunk_key(sx, sy)]
      if list ~= nil then
        for _, c in ipairs(list) do
          local par = c.front and N.front_parallax or 1
          local x = c.x - camX * par - c.size / 2
          local y = c.y - camY * par - c.size / 2
          if x + c.size > 0 and x < w and y + c.size > 0 and y < h then
            if c.front then
              draw_image(c.asset, x, y, c.size, c.size, N.front_alpha, "front")
            else
              draw_image(c.asset, x, y, c.size, c.size, N.back_alpha, "back")
            end
          end
        end
      end
    end
  end
end

local function update_vignette(w, h, dt)
  local inside_now = false
  if player_entity ~= nil and is_alive(player_entity) then
    local px, py = get_collider_center(player_entity)
    inside_now = nebula.inside(map_seed, map_biomes, px, py)
  end
  local_in_nebula = inside_now

  -- Llega a 255 (o a 0) en vignette_fade segundos
  local step = 255 * dt / N.vignette_fade
  if inside_now then
    vignette_alpha = math.min(255, vignette_alpha + step)
  else
    vignette_alpha = math.max(0, vignette_alpha - step)
  end

  if vignette_alpha > 0 then
    draw_image("nebula-vignette", 0, 0, w, h, math.floor(vignette_alpha), "front")
  end
end

function update()
  if map_biomes == nil or map_seed == nil then return end

  local camX, camY = get_camera_position()
  local w, h = get_screen_size()

  draw_backgrounds(camX, camY, w, h)
  draw_clouds(camX, camY, w, h)
  update_vignette(w, h, get_delta_time())
end
