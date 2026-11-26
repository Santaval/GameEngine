-- Logica pura de puertas, zonas y fundido (issue #62): sin llamadas al motor, sin
-- os ni io. Asi se prueba con un Lua independiente
-- (games/quebrada/tests/door_logic.lua) y los scripts solo hacen de pegamento.
--
-- Convenciones de Tiled en games/quebrada/docs/doors-and-zones.md.
local M = {}

-- ---- condiciones de bloqueo -------------------------------------------------

-- Evalua una condicion de texto: "a", "!a", "a,!b" (lista separada por comas =
-- AND). nil o "" = false. Un booleano de Tiled se devuelve tal cual.
-- flag_fn(nombre) -> truthy si el flag esta activo.
function M.eval_condition(cond, flag_fn)
  if type(cond) == "boolean" then return cond end
  if cond == nil or cond == "" then return false end
  if type(cond) ~= "string" then return false end
  local any = false
  for term in cond:gmatch("[^,]+") do
    term = term:match("^%s*(.-)%s*$")
    if term ~= "" then
      local negated = false
      if term:sub(1, 1) == "!" then
        negated = true
        term = term:match("^!%s*(.-)$")
      end
      if term ~= "" then
        any = true
        local value = flag_fn(term) and true or false
        if negated then value = not value end
        if not value then return false end
      end
    end
  end
  return any
end

-- La propiedad `locked` es la condicion que, si es VERDADERA, deja la puerta
-- cerrada. Sin propiedad = abierta.
function M.is_locked(door, flag_fn)
  local props = door and door.properties
  return M.eval_condition(props and props.locked, flag_fn)
end

-- ---- rectangulos ------------------------------------------------------------

-- Solape estricto: dos rects que solo se tocan por el borde no se solapan
function M.rect_overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Area de solape (0 si no hay)
local function overlap_area(a, b)
  local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
  local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
  if w <= 0 or h <= 0 then return 0 end
  return w * h
end

-- Caja de pies en mundo: position es la esquina superior izquierda del sprite,
-- box = {x,y,w,h} relativa a ella
function M.foot_box(px, py, box)
  return { x = px + box.x, y = py + box.y, w = box.w, h = box.h }
end

-- Puerta cuyo rect mas se solapa con la caja de pies (nil si ninguna)
function M.find_door(doors, foot)
  local best, best_area = nil, 0
  for _, d in ipairs(doors) do
    local area = overlap_area(d.rect, foot)
    if area > best_area then best, best_area = d, area end
  end
  return best
end

-- Zona que contiene el punto; con zonas anidadas gana la de menor area. El
-- borde derecho/inferior no cuenta como dentro (intervalo semiabierto)
function M.find_zone(zones, px, py)
  local best, best_area = nil, nil
  for _, z in ipairs(zones) do
    local r = z.rect
    if px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h then
      local area = r.w * r.h
      if best == nil or area < best_area then best, best_area = z, area end
    end
  end
  return best
end

-- ---- objetos del mapa -------------------------------------------------------

-- Reparte map.objects (lista plana de load_tmx) en puertas, zonas y spawns.
-- doors/zones: arrays { name, rect, properties }; spawns: por nombre { x, y, facing }
function M.index_objects(map)
  local idx = { doors = {}, zones = {}, spawns = {} }
  for _, o in ipairs(map.objects or {}) do
    local props = o.properties or {}
    if o.type == "door" and o.shape == "rect" then
      idx.doors[#idx.doors + 1] = { name = o.name, rect = o.rect, properties = props }
    elseif o.type == "zone" and o.shape == "rect" then
      idx.zones[#idx.zones + 1] = { name = o.name, rect = o.rect, properties = props }
    elseif o.type == "spawn" and o.shape == "point" then
      local f = props.facing
      if f == "" then f = nil end
      idx.spawns[o.name] = { x = o.x, y = o.y, facing = f }
    end
  end
  return idx
end

-- x, y, facing del spawn (facing puede ser nil) o nil, mensaje
function M.resolve_spawn(spawns, name)
  if name == nil or name == "" then return nil, "spawn sin nombre" end
  local s = spawns[name]
  if not s then return nil, "no existe el spawn '" .. tostring(name) .. "'" end
  return s.x, s.y, s.facing
end

-- El spawn marca el CENTRO de la caja de pies; devuelve la posicion (esquina
-- superior izquierda del sprite) que deja esa caja centrada en el punto
function M.spawn_to_position(sx, sy, box)
  return sx - (box.x + box.w / 2), sy - (box.y + box.h / 2)
end

-- Direccion de mirada al alejarse de la puerta hacia el spawn: eje dominante,
-- con empate gana el vertical
function M.facing_away(from_cx, from_cy, to_x, to_y)
  local dx, dy = to_x - from_cx, to_y - from_cy
  if math.abs(dx) > math.abs(dy) then
    return dx > 0 and "right" or "left"
  end
  return dy < 0 and "up" or "down"
end

-- Destino de una puerta: target_map (nil = el mismo mapa), target_spawn.
-- "@return" en cualquiera de los dos toma ctx.return_map / ctx.return_spawn.
-- Devuelve map, spawn o nil, nil, mensaje.
function M.door_target(door, ctx)
  local props = door.properties or {}
  local map = props.target_map
  local spawn = props.target_spawn
  if map == "" then map = nil end
  if spawn == "" then spawn = nil end
  if map == "@return" then
    map = ctx and ctx.return_map
    if not map then return nil, nil, "la puerta vuelve (@return) pero no hay mapa de origen" end
  end
  if spawn == "@return" then
    spawn = ctx and ctx.return_spawn
    if not spawn then return nil, nil, "la puerta vuelve (@return) pero no hay spawn de origen" end
  end
  if not spawn then return nil, nil, "la puerta no tiene target_spawn" end
  return map, spawn
end

-- ---- fundido a negro --------------------------------------------------------
-- Estados: idle (alpha 0) -> out (0..255) -> hold (255, pausa) -> black (255,
-- espera) -> in (255..0) -> idle. Los eventos salen una sola vez:
-- "out_done" al acabar hold (pasa a black) e "in_done" al acabar in.
-- Un dt mayor que la duracion se recorta: un solo cambio de estado por paso.

function M.new_fade(opts)
  opts = opts or {}
  return {
    out_time = opts.out_time or 0.3,
    in_time = opts.in_time or 0.3,
    hold = opts.hold or 0.05,
    state = "idle",
    t = 0,
  }
end

function M.fade_start_out(f)
  f.state = "out"
  f.t = 0
end

function M.fade_start_in(f)
  f.state = "in"
  f.t = 0
end

-- Pantalla ya negra (p. ej. primer frame de una escena nueva)
function M.fade_set_black(f)
  f.state = "black"
  f.t = 0
end

local function clamp_alpha(v)
  v = math.floor(v + 0.5)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

-- Alpha actual (0-255) sin avanzar el tiempo
function M.fade_alpha(f)
  local s = f.state
  if s == "idle" then return 0 end
  if s == "hold" or s == "black" then return 255 end
  if s == "out" then
    if f.out_time <= 0 then return 255 end
    return clamp_alpha(255 * f.t / f.out_time)
  end
  -- in
  if f.in_time <= 0 then return 0 end
  return clamp_alpha(255 * (1 - f.t / f.in_time))
end

-- Avanza dt; devuelve alpha, evento (nil, "out_done" o "in_done")
function M.fade_step(f, dt)
  local s = f.state
  local event = nil
  if s == "out" then
    f.t = f.t + dt
    if f.t >= f.out_time then
      f.state = "hold"
      f.t = 0
    end
  elseif s == "hold" then
    f.t = f.t + dt
    if f.t >= f.hold then
      f.state = "black"
      f.t = 0
      event = "out_done"
    end
  elseif s == "in" then
    f.t = f.t + dt
    if f.t >= f.in_time then
      f.state = "idle"
      f.t = 0
      event = "in_done"
    end
  end
  return M.fade_alpha(f), event
end

return M
