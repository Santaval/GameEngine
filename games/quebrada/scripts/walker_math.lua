-- Matematica pura del walker (issue #61): sin llamadas al motor, sin globales,
-- sin os ni random. Asi se prueba con un Lua independiente
-- (games/quebrada/tests/walker_math.lua) y walker.lua solo hace de pegamento.
local M = {}

-- Un input diagonal no debe ser mas rapido que uno recto: si el largo pasa de 1
-- se divide por el. Si es menor (analogico) se conserva
function M.normalize_input(dx, dy)
  local len = math.sqrt(dx * dx + dy * dy)
  if len > 1 then return dx / len, dy / len end
  return dx, dy
end

-- Avanza (vx,vy) hacia (tx,ty) como mucho max_delta. Si ya esta a esa distancia
-- devuelve el objetivo exacto (sin deriva, el reposo llega a 0,0 de verdad)
function M.move_toward(vx, vy, tx, ty, max_delta)
  local dx, dy = tx - vx, ty - vy
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist <= max_delta or dist == 0 then return tx, ty end
  local k = max_delta / dist
  return vx + dx * k, vy + dy * k
end

-- Velocidad del siguiente frame: objetivo = direccion * speed. La aceleracion es
-- speed / accel_time (decel_time si no hay input). Tiempo nil o 0 = instantaneo
function M.step_velocity(vx, vy, dirx, diry, speed, accel_time, decel_time, dt)
  local tx, ty = dirx * speed, diry * speed
  local has_input = dirx ~= 0 or diry ~= 0
  local time = has_input and accel_time or decel_time
  if not time or time <= 0 then return tx, ty end
  return M.move_toward(vx, vy, tx, ty, (speed / time) * dt)
end

-- Direccion a la que mira: sale del input (no de la velocidad). Bajo la zona
-- muerta conserva la anterior; en diagonal conserva la anterior si es una de las
-- dos direcciones pulsadas, si no prefiere la horizontal
function M.pick_facing(dx, dy, prev, deadzone)
  deadzone = deadzone or 0.1
  local pressed_x = math.abs(dx) > deadzone
  local pressed_y = math.abs(dy) > deadzone
  if not pressed_x and not pressed_y then return prev end
  local hdir = dx > 0 and "right" or "left"
  local vdir = dy > 0 and "down" or "up"
  if pressed_x and not pressed_y then return hdir end
  if pressed_y and not pressed_x then return vdir end
  if prev == hdir or prev == vdir then return prev end
  return hdir
end

function M.anim_tag(prefix, kind, dir)
  return prefix .. kind .. "_" .. dir
end

-- true si el frame cambio y el nuevo es uno de los que suenan (set: frame -> true)
function M.crossed_frame(prev_frame, frame, frames_set)
  return frame ~= prev_frame and frames_set[frame] == true
end

-- Factor de suavizado independiente del framerate: 1 - e^(-k*dt). k nil o 0 = 1
function M.smooth_factor(k, dt)
  if not k or k <= 0 then return 1 end
  return 1 - math.exp(-k * dt)
end

-- Mueve el centro de la camara lo justo para que el objetivo quede dentro de
-- +-hw / +-hh del centro
function M.deadzone_follow(cx, cy, tx, ty, hw, hh)
  if tx > cx + hw then cx = tx - hw elseif tx < cx - hw then cx = tx + hw end
  if ty > cy + hh then cy = ty - hh elseif ty < cy - hh then cy = ty + hh end
  return cx, cy
end

-- Esquina superior de la camara en un eje: si el mapa cabe en pantalla lo centra,
-- si no la limita a [b_min, b_min + b_size - size_screen]
function M.clamp_axis(pos, size_screen, b_min, b_size)
  if b_size <= size_screen then return b_min + (b_size - size_screen) / 2 end
  local hi = b_min + b_size - size_screen
  if pos < b_min then return b_min end
  if pos > hi then return hi end
  return pos
end

-- Un paso de camara. state = {cx, cy, init} (centro, se crea vacio); cfg.deadzone
-- = {w, h} (tamano total) y cfg.smooth; bounds = {x, y, w, h} o nil. Devuelve la
-- esquina superior izquierda. Limita DESPUES de suavizar para no mostrar nunca
-- nada fuera del mapa, y reescribe el centro limitado en state
function M.camera_step(state, tx, ty, cfg, sw, sh, bounds, dt)
  if not state.init then
    state.init = true
    state.cx, state.cy = tx, ty
  else
    local dz = cfg.deadzone or {}
    local goal_x, goal_y = M.deadzone_follow(state.cx, state.cy, tx, ty,
      (dz.w or 0) / 2, (dz.h or 0) / 2)
    local f = M.smooth_factor(cfg.smooth, dt)
    local dx, dy = goal_x - state.cx, goal_y - state.cy
    if math.abs(dx) < 0.05 then state.cx = goal_x else state.cx = state.cx + dx * f end
    if math.abs(dy) < 0.05 then state.cy = goal_y else state.cy = state.cy + dy * f end
  end

  local x, y = state.cx - sw / 2, state.cy - sh / 2
  if bounds then
    x = M.clamp_axis(x, sw, bounds.x, bounds.w)
    y = M.clamp_axis(y, sh, bounds.y, bounds.h)
    state.cx, state.cy = x + sw / 2, y + sh / 2
  end
  return x, y
end

return M
