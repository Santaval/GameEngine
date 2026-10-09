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

-- Acumula mientras `inside`; cada S.tick s quita S.damage de vida. Fuera
-- reinicia, asi el primer golpe llega S.tick s despues de entrar. set_health
-- solo funciona en el dueno de la entidad (la nave local lo es)
function storm.tick_damage(state, entity, inside, dt)
  if not inside then
    state.acc = 0
    return
  end
  state.acc = state.acc + dt
  while state.acc >= S.tick do
    state.acc = state.acc - S.tick
    set_health(entity, get_health(entity) - S.damage)
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

-- Rellena la pantalla con teselas alineadas al mundo cuyo centro cumple
-- inside_fn(cx, cy)
function storm.draw_fill(camX, camY, sw, sh, frame, inside_fn)
  local size = S.tile_size
  local opts = { src = storm.src(S.tile_frame, frame % S.tile_frame.count) }
  local i0 = math.floor(camX / size)
  local i1 = math.floor((camX + sw) / size)
  local j0 = math.floor(camY / size)
  local j1 = math.floor((camY + sh) / size)
  for i = i0, i1 do
    for j = j0, j1 do
      if inside_fn((i + 0.5) * size, (j + 0.5) * size) then
        draw_image("storm-tile", math.floor(i * size - camX), math.floor(j * size - camY),
          size, size, S.alpha, "back", opts)
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

-- Tinte rojo de pantalla completa (Oxblood #9D0208)
function storm.draw_tint(w, h, alpha)
  draw_rect(0, 0, w, h, 157, 2, 8, alpha, true)
end

return storm
