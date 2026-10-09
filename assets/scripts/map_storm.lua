-- =====================================================================
--  Tormenta del borde: funciones compartidas (sin estado propio; quien las
--  llama guarda su estado). Las usan map_storm_world.lua (banda del borde) y,
--  mas adelante, las tormentas errantes (#21) y la contraccion (#25).
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")

local S = cfg.STORM
local B = cfg.STORM_BAND
local W = cfg.WORLD_SIZE

local storm = {}

-- true si el punto esta a menos de STORM_BAND de algun borde o fuera del mundo
function storm.in_border(x, y)
  return x < B or y < B or x > W - B or y > W - B
end

-- Estado del dano por tiempo de una entidad
function storm.new_damage()
  return { acc = 0 }
end

-- Acumula mientras `inside`; cada tick s quita damage de vida (por defecto
-- S.tick y S.damage). Fuera reinicia, asi el primer golpe llega un tick
-- despues de entrar. set_health solo funciona en el dueno de la entidad (la
-- nave local lo es)
function storm.tick_damage(state, entity, inside, dt, damage, tick)
  damage = damage or S.damage
  tick = tick or S.tick
  if not inside then
    state.acc = 0
    return
  end
  state.acc = state.acc + dt
  while state.acc >= tick do
    state.acc = state.acc - tick
    set_health(entity, get_health(entity) - damage)
  end
end

-- Frame de animacion para el reloj dado
function storm.frame(clock)
  return math.floor(clock * S.fps) % S.tile_frame.count
end

-- Rect fuente {x, y, w, h} del frame i de una hoja (tile_frame o edge_frame)
function storm.src(frame_cfg, i)
  return { x = math.floor(i * frame_cfg.step), y = frame_cfg.y, w = frame_cfg.w, h = frame_cfg.h }
end

-- Rellena la pantalla con teselas cuyo centro cumple inside_fn(cx, cy). La
-- rejilla esta alineada al mundo salvo que se pase un origen (ox, oy): con el
-- origen en una tormenta errante las teselas viajan con ella y no aparecen y
-- desaparecen. alpha por defecto S.alpha
function storm.draw_fill(camX, camY, sw, sh, frame, inside_fn, ox, oy, alpha)
  ox = ox or 0
  oy = oy or 0
  alpha = alpha or S.alpha
  local size = S.tile_size
  local opts = { src = storm.src(S.tile_frame, frame % S.tile_frame.count) }
  local i0 = math.floor((camX - ox) / size)
  local i1 = math.floor((camX + sw - ox) / size)
  local j0 = math.floor((camY - oy) / size)
  local j1 = math.floor((camY + sh - oy) / size)
  for i = i0, i1 do
    for j = j0, j1 do
      if inside_fn(ox + (i + 0.5) * size, oy + (j + 0.5) * size) then
        draw_image("storm-tile", math.floor(ox + i * size - camX), math.floor(oy + j * size - camY),
          size, size, alpha, "back", opts)
      end
    end
  end
end

-- Tiras de borde a lo largo de un segmento recto (horizontal o vertical) del
-- mundo. inward_angle (grados horarios) deja el lado irregular hacia la zona
-- segura. La linea central de la tira queda sobre el segmento, desplazada para
-- que edge_overlap de su alto asome hacia dentro
function storm.draw_edge_segment(x1, y1, x2, y2, inward_angle, camX, camY, sw, sh, frame)
  local eh = S.edge_height
  local len = eh * S.edge_frame.w / S.edge_frame.h
  local horizontal = (y1 == y2)
  local opts = { src = storm.src(S.edge_frame, frame % S.edge_frame.count), angle = inward_angle }

  -- Sentido hacia la zona segura (el lado irregular apunta ahi)
  local nx, ny
  if inward_angle == 0 then nx, ny = 0, -1
  elseif inward_angle == 180 then nx, ny = 0, 1
  elseif inward_angle == 90 then nx, ny = 1, 0
  else nx, ny = -1, 0 end
  -- Centro de la tira: el lado solido (opuesto al irregular) queda fuera, y
  -- edge_overlap*eh asoma hacia dentro del segmento
  local shift = eh * (S.edge_overlap - 0.5)

  local lo, hi
  if horizontal then lo, hi = math.min(x1, x2), math.max(x1, x2)
  else lo, hi = math.min(y1, y2), math.max(y1, y2) end
  local view_lo, view_hi
  if horizontal then view_lo, view_hi = camX, camX + sw else view_lo, view_hi = camY, camY + sh end
  local first = math.max(lo, view_lo - len)
  local last = math.min(hi, view_hi + len)
  local k0 = math.floor((first - lo) / len)

  local k = k0
  while lo + k * len < last do
    local a = lo + k * len
    local piece = math.min(len, hi - a)
    if piece > 0 then
      local c = a + piece / 2
      local cx, cy
      if horizontal then cx, cy = c + nx * shift, y1 + ny * shift
      else cx, cy = x1 + nx * shift, c + ny * shift end
      -- dst antes de girar: w = largo de la pieza, h = alto de la tira
      local sx, sy = cx - camX, cy - camY
      draw_image("storm-edge", math.floor(sx - piece / 2), math.floor(sy - eh / 2),
        math.ceil(piece) + 1, math.ceil(eh), S.alpha, "back", opts)
    end
    k = k + 1
  end
end

-- Anillo de borde irregular alrededor del circulo (cx, cy, r), con el lado
-- irregular hacia fuera. La pieza k va en el angulo t = 2*pi*k/n, con
-- n = ceil(2*pi*r / largo), centrada en (cx + r cos t, cy + r sin t) y girada
-- deg(t) + 90 (arriba, t = -90, da 0: lado irregular hacia arriba)
function storm.draw_edge_ring(cx, cy, r, height, camX, camY, sw, sh, frame)
  -- Todo el anillo fuera de pantalla
  local reach = r + height
  if cx + reach < camX or cx - reach > camX + sw or cy + reach < camY or cy - reach > camY + sh then
    return
  end
  local len = height * S.edge_frame.w / S.edge_frame.h
  local n = math.ceil(2 * math.pi * r / len)
  local src = storm.src(S.edge_frame, frame % S.edge_frame.count)
  for k = 0, n - 1 do
    local t = 2 * math.pi * k / n
    local px, py = cx + r * math.cos(t), cy + r * math.sin(t)
    if px >= camX - len and px <= camX + sw + len and py >= camY - len and py <= camY + sh + len then
      local sx, sy = px - camX, py - camY
      draw_image("storm-edge", math.floor(sx - (len + 1) / 2), math.floor(sy - height / 2),
        math.ceil(len) + 1, math.ceil(height), S.alpha, "back",
        { src = src, angle = math.deg(t) + 90 })
    end
  end
end

-- Tormentas errantes vivas: lista { {e, x, y, r, vx, vy}, ... } a partir del
-- global wandering_storms (netId -> true, lo llena wandering_storm.lua en cada
-- cliente). Descarta (y borra de la tabla) los ids que ya no existen. La
-- posicion de la entidad es el CENTRO (no tiene sprite)
function storm.wandering()
  local list = {}
  if wandering_storms == nil then return list end
  for id in pairs(wandering_storms) do
    local e = find_by_net_id(id)
    if e == nil or not is_alive(e) then
      wandering_storms[id] = nil
      if wandering_storm_radius ~= nil then wandering_storm_radius[id] = nil end
    else
      local x, y = get_position(e)
      local vx, vy = get_velocity(e)
      local r = (wandering_storm_radius and wandering_storm_radius[id]) or cfg.WANDERING_STORM.radius.min
      list[#list + 1] = { e = e, x = x, y = y, r = r, vx = vx, vy = vy }
    end
  end
  return list
end

-- true si el punto (x, y) esta dentro de alguna tormenta errante (mas pad px).
-- Es el gancho para los portales (#22)
function storm.in_wandering(x, y, pad)
  pad = pad or 0
  for _, w in ipairs(storm.wandering()) do
    local dx, dy = x - w.x, y - w.y
    local rr = w.r + pad
    if dx * dx + dy * dy < rr * rr then return true end
  end
  return false
end

-- Tinte rojo de pantalla completa (Oxblood #9D0208)
function storm.draw_tint(w, h, alpha)
  draw_rect(0, 0, w, h, 157, 2, 8, alpha, true)
end

return storm
