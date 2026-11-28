-- Logica pura de la luz companera de la noche del chequelo (issue #81). Sin llamadas al motor.
-- La luz solo se mueve a lo largo de la ruta (objetos `route` del mapa) con una velocidad maxima
-- normal: caminando el jugador la sigue de cerca; corriendo ella acelera para no quedarse atras, y al parar espera.
local M = {}

M.CONFIG = {
  speed = 62,            -- px/s de la luz yendo al paso del jugador (caminar = 60, correr = 400)
  catchup_speed = 520,   -- px/s maximos al alcanzar al jugador que corre (mayor que correr)
  catchup_gap = 8,       -- px de retraso sobre el objetivo a partir de los que acelera
  catchup_gain = 30,     -- px/s extra por cada px de retraso
  lead_distance = 40,    -- distancia por delante del jugador mientras camina
  wait_distance = 56,    -- distancia a la que se queda cuando el jugador se detiene
  light_radius = 64,
  light_intensity = 0.95,
  light_rgb = { 255, 220, 150 },
  light_flicker = 0.05,
  float_height = 10,     -- px que flota sobre el camino
  stop_speed = 6,        -- px/s bajo los cuales el jugador cuenta como quieto
  stop_time = 0.4,       -- s quieto antes de que la luz espere
  move_speed = 20,       -- px/s con los que el jugador cuenta como en marcha
  appear_time = 0.8,
  leave_time = 2.0,
  extinguish_time = 1.2,
  pulse_period = 1.6,
  pulse_depth = 0.25,
  drift_max = 12,        -- desvio lateral maximo (px), dentro del trigger del camino
  drift_range = 260,     -- px de ruta a cada lado del desvio donde empieza a asomarse
  drift_threshold = 0.35,
  drift_freq = 0.15,
  seed = 81,
  end_margin = 24,       -- al llegar a este margen del final de la ruta se apaga
  max_track_jump = 200,  -- salto del jugador sobre la ruta que se trata como teletransporte
  sound_id = nil,        -- id de sonido (nil = sin sonido, ver docs/zona1.md)
  sound_volume = 0.5,
  sound_min = 48,
  sound_max = 320,
}

-- ---------------------------------------------------------------- ruta

function M.build_path(points)
  local pts, cum = {}, { 0 }
  local len = 0
  for i, p in ipairs(points) do
    pts[i] = { x = p.x, y = p.y }
    if i > 1 then
      local dx, dy = p.x - points[i - 1].x, p.y - points[i - 1].y
      len = len + math.sqrt(dx * dx + dy * dy)
      cum[i] = len
    end
  end
  return { pts = pts, cum = cum, len = len }
end

-- Ruta desde los objetos de Tiled de tipo `route`, ordenados por nombre (route_00, route_01...)
function M.route_from_objects(objects, kind)
  kind = kind or "route"
  local list = {}
  for _, o in ipairs(objects or {}) do
    if o.type == kind then list[#list + 1] = o end
  end
  if #list < 2 then return nil end
  -- Ordenacion por insercion (el Lua del motor no trae table.sort)
  for i = 2, #list do
    local o, j = list[i], i - 1
    while j >= 1 and (list[j].name or "") > (o.name or "") do
      list[j + 1] = list[j]
      j = j - 1
    end
    list[j + 1] = o
  end
  local pts = {}
  for i, o in ipairs(list) do pts[i] = { x = o.x, y = o.y } end
  return M.build_path(pts)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Punto en la distancia s: devuelve x, y y la normal (nx, ny) del tramo (giro a la derecha del avance)
function M.point_at(path, s)
  s = clamp(s, 0, path.len)
  local n = #path.pts
  local i = 1
  while i < n - 1 and path.cum[i + 1] < s do i = i + 1 end
  local a, b = path.pts[i], path.pts[i + 1]
  local seg = path.cum[i + 1] - path.cum[i]
  local dx, dy = b.x - a.x, b.y - a.y
  local dl = math.sqrt(dx * dx + dy * dy)
  if dl == 0 then return a.x, a.y, 0, 1 end
  local t = seg > 0 and (s - path.cum[i]) / seg or 0
  return a.x + dx * t, a.y + dy * t, -dy / dl, dx / dl
end

-- Proyeccion de (x, y) sobre la ruta: devuelve s y la distancia. Con empate gana el mas cercano a hint_s
function M.project(path, x, y, hint_s)
  local best_s, best_d = 0, math.huge
  for i = 1, #path.pts - 1 do
    local a, b = path.pts[i], path.pts[i + 1]
    local dx, dy = b.x - a.x, b.y - a.y
    local l2 = dx * dx + dy * dy
    local t = 0
    if l2 > 0 then t = clamp(((x - a.x) * dx + (y - a.y) * dy) / l2, 0, 1) end
    local qx, qy = a.x + dx * t, a.y + dy * t
    local d = math.sqrt((x - qx) ^ 2 + (y - qy) ^ 2)
    local s = path.cum[i] + t * (path.cum[i + 1] - path.cum[i])
    local better = d < best_d - 0.01
    if not better and math.abs(d - best_d) <= 0.01 and hint_s then
      better = math.abs(s - hint_s) < math.abs(best_s - hint_s)
    end
    if better then best_s, best_d = s, d end
  end
  return best_s, best_d
end

-- ---------------------------------------------------------------- desvios

-- Triggers `detour_*`: posicion s del desvio y lado (+1 / -1 segun la normal de la ruta)
function M.detours_from_objects(path, objects)
  local out = {}
  for _, o in ipairs(objects or {}) do
    local trig = o.properties and o.properties.trigger
    if type(trig) == "string" and trig:match("^detour_") then
      local r = o.rect or { x = o.x, y = o.y, w = o.width or 0, h = o.height or 0 }
      local cx, cy = r.x + r.w / 2, r.y + r.h / 2
      local s = M.project(path, cx, cy)
      local px, py, nx, ny = M.point_at(path, s)
      local dot = (cx - px) * nx + (cy - py) * ny
      out[#out + 1] = { name = trig, s = s, side = dot >= 0 and 1 or -1 }
    end
  end
  return out
end

-- ---------------------------------------------------------------- ruido y deriva

local function hash(seed, i)
  local n = (i * 374761393 + seed * 668265263) % 4294967296
  n = ((n ~ (n >> 13)) * 1274126177) % 4294967296
  n = n ~ (n >> 16)
  return (n % 100000) / 100000
end

-- Ruido 0..1 determinista: lattice entero + interpolacion coseno
function M.noise(seed, t)
  local i = math.floor(t)
  local f = t - i
  local u = (1 - math.cos(f * math.pi)) / 2
  local a, b = hash(seed, i), hash(seed, i + 1)
  return a + (b - a) * u
end

-- Desvio lateral (px, con signo) hacia el desvio cercano, solo cuando el ruido supera el umbral
function M.drift(st, detours, cfg, t)
  local best_w, best_side = 0, 0
  for _, d in ipairs(detours or {}) do
    local dist = math.abs(st.s - d.s)
    local w = 1 - dist / cfg.drift_range
    if w > best_w then best_w, best_side = w, d.side end
  end
  if best_w <= 0 then return 0 end
  local n = M.noise(cfg.seed, t * cfg.drift_freq)
  local gate = clamp((n - cfg.drift_threshold) / (1 - cfg.drift_threshold), 0, 1)
  return best_side * cfg.drift_max * best_w * gate
end

-- ---------------------------------------------------------------- estado

function M.new()
  return { state = "hidden", s = 0, t = 0, timer = 0, player_s = nil, player_v = 0, still = 0, offset = 0 }
end

local function go(st, state)
  st.state = state
  st.timer = 0
end

-- inp = { px, py, light_appears, off_road, arrived, night_active }
function M.step(st, path, detours, cfg, dt, inp)
  st.t = st.t + dt
  st.timer = st.timer + dt

  -- Seguimiento del jugador sobre la ruta
  local ps = M.project(path, inp.px, inp.py, st.player_s)
  if st.player_s == nil or math.abs(ps - st.player_s) > cfg.max_track_jump then
    st.player_v = 0
    st.still = 0
  elseif dt > 0 then
    local v = (ps - st.player_s) / dt
    st.player_v = st.player_v + (v - st.player_v) * 0.3
    if math.abs(st.player_v) < cfg.stop_speed then
      st.still = st.still + dt
    else
      st.still = 0
    end
  end
  st.player_s = ps

  local state = st.state
  if not inp.light_appears then
    if state ~= "hidden" then go(st, "hidden") end
    st.offset = 0
    return
  end

  if state == "hidden" then
    if inp.night_active and not inp.off_road and not inp.arrived then
      st.s = clamp(ps + cfg.lead_distance, 0, path.len)
      st.offset = 0
      go(st, "appearing")
    end
    return
  end
  if state == "gone" then return end

  -- Transiciones comunes
  if state == "appearing" or state == "guiding" or state == "waiting" then
    if inp.off_road then
      go(st, "extinguishing")
    elseif inp.arrived or not inp.night_active or st.s >= path.len - cfg.end_margin then
      go(st, "leaving")
    end
  end
  state = st.state

  if state == "appearing" then
    if st.timer >= cfg.appear_time then go(st, "guiding") end
  elseif state == "guiding" then
    if st.still >= cfg.stop_time or st.s - ps > cfg.lead_distance + 16 then go(st, "waiting") end
  elseif state == "waiting" then
    if st.player_v > cfg.move_speed and st.s - ps < cfg.wait_distance then go(st, "guiding") end
  elseif state == "leaving" then
    if st.timer >= cfg.leave_time then go(st, "gone") end
  elseif state == "extinguishing" then
    if st.timer >= cfg.extinguish_time then go(st, "gone") end
  end
  state = st.state

  -- Movimiento: nunca retrocede
  if state == "guiding" or state == "waiting" then
    local target = ps + (state == "guiding" and cfg.lead_distance or cfg.wait_distance)
    if target > st.s then
      -- Al paso normal va a `speed`; si el jugador corre y la deja atras, acelera hasta alcanzarlo
      local lag = target - st.s
      local speed = cfg.speed
      if lag > cfg.catchup_gap then
        speed = clamp(cfg.speed + (lag - cfg.catchup_gap) * cfg.catchup_gain, cfg.speed, cfg.catchup_speed)
      end
      st.s = st.s + math.min(lag, speed * dt)
    end
    st.s = clamp(st.s, 0, path.len)
    st.offset = M.drift(st, detours, cfg, st.t)
  elseif state == "leaving" or state == "extinguishing" then
    st.offset = st.offset * math.max(0, 1 - 3 * dt)
  end
end

-- Datos de dibujo: { x, y, intensity, flicker, radius, anim }
function M.visual(st, path, cfg)
  local state = st.state
  if state == "hidden" or state == "gone" then
    return { x = 0, y = 0, intensity = 0, flicker = 0, radius = cfg.light_radius, anim = nil }
  end
  local x, y, nx, ny = M.point_at(path, st.s)
  x, y = x + nx * st.offset, y + ny * st.offset - cfg.float_height

  local base = cfg.light_intensity
  local intensity, flicker, anim = base, cfg.light_flicker, "idle"
  if state == "appearing" then
    intensity = base * clamp(st.timer / cfg.appear_time, 0, 1)
    anim = "appear"
  elseif state == "waiting" then
    local w = (1 - cfg.pulse_depth) + cfg.pulse_depth * (0.5 + 0.5 * math.sin(st.t * 2 * math.pi / cfg.pulse_period))
    intensity = base * w
  elseif state == "leaving" then
    intensity = base * (1 - clamp(st.timer / cfg.leave_time, 0, 1))
    anim = "fade"
  elseif state == "extinguishing" then
    intensity = base * (1 - clamp(st.timer / cfg.extinguish_time, 0, 1))
    flicker = 0.6
    anim = "fade"
  end
  return { x = x, y = y, intensity = intensity, flicker = flicker, radius = cfg.light_radius, anim = anim }
end

return M
