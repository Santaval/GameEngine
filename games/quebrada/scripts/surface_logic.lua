-- Logica pura de superficies y pasos (issue #65): sin llamadas al motor.
-- Convenciones en games/quebrada/docs/audio.md.
local door = require("door_logic")
local M = {}

M.DEFAULT = "lastre"
-- Lista de variaciones por superficie y modo. Anadir un archivo = anadir un id aqui.
M.STEPS = {
  lastre   = { walk = { "step_lastre_walk" },   run = { "step_lastre_run" } },
  zacate   = { walk = { "step_zacate_walk" },   run = { "step_zacate_run" } },
  madera   = { walk = { "step_madera_walk" },   run = { "step_madera_run" } },
  concreto = { walk = { "step_concreto_walk" }, run = { "step_concreto_run" } },
}
M.WALK_VOLUME = 0.5
M.RUN_VOLUME = 0.8
M.JITTER = 0.15 -- +-15% de volumen

-- Centro de la caja de pies en mundo
function M.foot_center(px, py, box)
  return px + box.x + box.w / 2, py + box.y + box.h / 2
end

local function collect_tile_layers(layers, out)
  for _, l in ipairs(layers or {}) do
    if l.kind == "tile" then out[#out + 1] = l
    elseif l.kind == "group" then collect_tile_layers(l.layers, out) end
  end
end

-- Construye el indice desde el resultado de load_tmx
function M.build(map)
  local idx = { tile_props = {}, layers = {}, rects = {}, tw = map.tilewidth, th = map.tileheight }
  idx.default = map.properties and map.properties.surface
  if idx.default == "" then idx.default = nil end
  for _, ts in ipairs(map.tilesets or {}) do
    for local_id, tile in pairs(ts.tiles or {}) do
      local s = tile.properties and tile.properties.surface
      if type(s) == "string" and s ~= "" then idx.tile_props[ts.firstgid + local_id] = s end
    end
  end
  collect_tile_layers(map.layers, idx.layers)
  for _, o in ipairs(map.objects or {}) do
    local s = o.properties and o.properties.surface
    if o.type == "surface" and o.shape == "rect" and type(s) == "string" and s ~= "" then
      idx.rects[#idx.rects + 1] = { name = o.name, rect = o.rect, properties = o.properties }
    end
  end
  return idx
end

-- Superficie de la capa de tiles mas alta con propiedad en esa celda (nil si ninguna)
local function tile_surface(idx, x, y)
  for i = #idx.layers, 1, -1 do
    local l = idx.layers[i]
    local col = math.floor((x - (l.offsetx or 0)) / idx.tw)
    local row = math.floor((y - (l.offsety or 0)) / idx.th)
    if col >= 0 and row >= 0 and col < l.width and row < l.height then
      local gid = l.data[row * l.width + col + 1]
      if gid and gid > 0 then
        local s = idx.tile_props[gid]
        if s then return s end
      end
    end
  end
  return nil
end

-- Superficie bajo el punto (x, y) en mundo. idx nil = superficie por defecto.
function M.surface_at(idx, x, y)
  if not idx then return M.DEFAULT end
  local s = tile_surface(idx, x, y)
  if s then return s end
  local z = door.find_zone(idx.rects, x, y) -- gana el rect de menor area
  if z then return z.properties.surface end
  return idx.default or M.DEFAULT
end

-- Elige sonido y volumen de un paso. rng() -> [0,1). Superficie desconocida = la de
-- por defecto. last_id evita repetir la misma variacion seguida.
function M.pick_step(surface, running, last_id, rng)
  local per = M.STEPS[surface] or M.STEPS[M.DEFAULT]
  local list = running and per.run or per.walk
  local id
  if #list <= 1 then
    id = list[1]
  else
    repeat
      id = list[math.min(#list, math.floor(rng() * #list) + 1)]
    until id ~= last_id
  end
  local base = running and M.RUN_VOLUME or M.WALK_VOLUME
  local vol = base * (1 + (rng() * 2 - 1) * M.JITTER)
  return id, vol
end

return M
