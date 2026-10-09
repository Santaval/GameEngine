-- =====================================================================
--  Director del Reactor Remains (entidad invisible, solo script):
--  - Construccion: cuando aval_cup_world.lua fija map_seed crea, en local y sin
--    red (como las rocas), las piezas, los circulos de colision y el nucleo de
--    cada sitio de map_reactor.sites, y publica la lista como el global
--    reactor_sites (el minimapa la dibuja; las tormentas y los eventos la leen).
--  - Pulso del Reactor: reposo -> carga (aviso) -> onda. Al acabar la carga se
--    empuja hacia afuera todo lo que esta dentro del radio: la nave local, las
--    rocas del chunk y los asteroides de red propios. Los choques que provoca
--    el empuje hacen dano por el camino normal (ImpactDamage).
--  - Disparo: el host lanza el pulso con reactor_pulse_fire(i) (el director de
--    eventos lo usara) y avisa a todos con "reactor_pulse". Mientras tanto un
--    temporizador por sitio y la tecla K (debug_pulse) lo disparan.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local reactor = require("map_reactor")
local data = require("map_reactor_data")
local zones = require("player_gravity_zones")
local ui = require("ui_helpers")

local R = cfg.REACTOR
local P = R.pulse

-- Color de la onda (rojo, como el arte del nucleo) y del aro de aviso
local WAVE_COLOR = { 255, 70, 50 }
local WARN_ALPHA = 70
local WAVE_ALPHA = 220
local WAVE_DOT_SPACING = 40

-- Reposo: el nucleo alterna los frames 0 y 1 cada IDLE_PERIOD s. Carga: parpadea
-- entre los 2 y 3 cada FLICKER_PERIOD s. Onda: recorre los frames 4 a 7
local IDLE_PERIOD = 0.8
local FLICKER_PERIOD = 0.12
local WAVE_FIRST_FRAME = 4
local WAVE_LAST_FRAME = 7

local built = false
local sites = nil
-- Estado por sitio: { phase = "idle"|"charge"|"wave", t, timer, core }
local states = {}
local clock = 0
local debug_pressed = ui.edge("debug_pulse")
local last_error = nil

-- Segundos hasta el siguiente pulso automatico (solo lo usa el host). Esto es
-- de ejecucion, no de generacion del mapa: math.random esta bien
local function next_interval()
  return P.interval.min + math.random() * (P.interval.max - P.interval.min)
end

-- Frame i de la hoja del nucleo (core_cols por fila)
local function set_frame(core, i)
  local size = R.core_frame
  set_sprite_frame(core, (i % R.core_cols) * size, (i // R.core_cols) * size)
end

-- Crea todos los sitios (piezas, colliders y nucleo, en ese orden: el
-- RenderSystem dibuja en orden de creacion) y publica reactor_sites
local function build()
  sites = reactor.sites(map_seed)
  states = {}
  local colliders = 0
  for i, site in ipairs(sites) do
    for _, piece in ipairs(site.pieces) do spawn_local("reactor_piece.lua", piece) end
    for _, c in ipairs(site.colliders) do
      spawn_local("reactor_collider.lua", c)
      colliders = colliders + 1
    end
    states[i] = {
      phase = "idle", t = 0, timer = next_interval(),
      core = spawn_local("reactor_core.lua", site.core),
    }
  end
  reactor_sites = sites
  built = true
  print(string.format("[reactor] %d sitios, %d colliders", #sites, colliders))
  for i, site in ipairs(sites) do
    print(string.format("[reactor]  #%d %s en (%d, %d)", i, site.variant, site.x, site.y))
  end
end

-- Suma `push` px/s hacia afuera (desde cx, cy) a la velocidad de la entidad e,
-- que esta en (ex, ey). Empuja fuera de la banda de max_speed: set_velocity no
-- la topa (ver asteroid.lua)
local function push_entity(e, cx, cy, ex, ey, radius)
  local dx, dy = ex - cx, ey - cy
  local d = math.sqrt(dx * dx + dy * dy)
  if d >= radius then return end
  -- Pegado al nucleo sale max_push y cae linealmente; min_push es el suelo
  local push = math.max(P.min_push, P.max_push * (1 - d / radius))
  local ux, uy
  if d < 0.001 then ux, uy = 1, 0 else ux, uy = dx / d, dy / d end
  local vx, vy = get_velocity(e)
  set_velocity(e, vx + ux * push, vy + uy * push)
end

-- Aplica el empuje del sitio: la nave local, las rocas de chunk (cada cliente
-- mueve su copia) y los asteroides de red que son nuestros
local function apply_push(site)
  if player_entity ~= nil and is_alive(player_entity) then
    local ex, ey = get_collider_center(player_entity)
    push_entity(player_entity, site.x, site.y, ex, ey, P.radius)
  end

  if map_rocks_near ~= nil then
    for _, e in ipairs(map_rocks_near(site.x, site.y, P.radius)) do
      local ex, ey = get_collider_center(e)
      push_entity(e, site.x, site.y, ex, ey, P.radius)
    end
  end

  if drifting_asteroids ~= nil then
    for id in pairs(drifting_asteroids) do
      local e = find_by_net_id(id)
      if e ~= nil and is_alive(e) and is_local(e) then
        local ex, ey = get_collider_center(e)
        push_entity(e, site.x, site.y, ex, ey, P.radius)
      end
    end
  end
end

-- Arranca la carga del sitio i (todos los clientes). Un sitio ocupado la ignora
local function start_charge(i)
  local st = states[i]
  if st == nil or st.phase ~= "idle" then return false end
  st.phase = "charge"
  st.t = 0
  return true
end

-- Dispara el pulso del sitio i: solo el host. Lo llamara el director de eventos;
-- mientras tanto lo llaman el temporizador y la tecla K. Devuelve true si salio
function reactor_pulse_fire(i)
  if not built or not net_is_host() then return false end
  if not start_charge(i) then return false end
  net_send("reactor_pulse", { i = i })
  return true
end

-- Solo se acepta el pulso del host, y nunca el propio (el host ya lo arranco)
net_on("reactor_pulse", function(data, from)
  if from ~= net_host_id() then return end
  if from == net_my_id() then return end
  if type(data) ~= "table" or type(data.i) ~= "number" then return end
  if not built then return end
  start_charge(math.tointeger(data.i) or -1)
end)

-- Aviso centrado mientras el sitio carga y la nave esta a warn_radius
local function draw_warning(site)
  if player_entity == nil or not is_alive(player_entity) then return end
  local px, py = get_collider_center(player_entity)
  local dx, dy = px - site.x, py - site.y
  if dx * dx + dy * dy > P.warn_radius * P.warn_radius then return end
  local _, h = get_window_size()
  ui.draw_centered(h * 0.2, "PULSO DEL REACTOR", "debug-big", 28, WAVE_COLOR[1], WAVE_COLOR[2], WAVE_COLOR[3], 255)
end

-- Sitio mas cercano a la nave local (para la tecla de depuracion)
local function nearest_site()
  if player_entity == nil or not is_alive(player_entity) then return nil end
  local px, py = get_collider_center(player_entity)
  local best, best_d = nil, math.huge
  for i, site in ipairs(sites) do
    local d = (site.x - px) ^ 2 + (site.y - py) ^ 2
    if d < best_d then best, best_d = i, d end
  end
  return best
end

-- Avanza el estado de un sitio, anima su nucleo y dibuja aro y aviso
local function step_site(i, site, st, dt)
  if st.phase == "idle" then
    set_frame(st.core, math.floor(clock / IDLE_PERIOD + i) % 2)
    if net_is_host() then
      st.timer = st.timer - dt
      if st.timer <= 0 then
        st.timer = next_interval()
        reactor_pulse_fire(i)
      end
    end

  elseif st.phase == "charge" then
    st.t = st.t + dt
    set_frame(st.core, 2 + math.floor(st.t / FLICKER_PERIOD) % 2)
    draw_warning(site)
    zones.draw_ring(site, P.radius, WAVE_COLOR, WARN_ALPHA, WAVE_DOT_SPACING)
    if st.t >= P.charge then
      apply_push(site)
      st.phase = "wave"
      st.t = 0
    end

  elseif st.phase == "wave" then
    st.t = st.t + dt
    local f = math.min(1, st.t / P.wave_time)
    local frame = WAVE_FIRST_FRAME + math.floor(f * (WAVE_LAST_FRAME - WAVE_FIRST_FRAME + 1))
    set_frame(st.core, math.min(frame, WAVE_LAST_FRAME))
    -- La onda crece del nucleo al radio del empuje y se desvanece
    local start = site.core.size * data.CORE_RADIUS
    local radius = start + (P.radius - start) * f
    zones.draw_ring(site, radius, WAVE_COLOR, math.floor(WAVE_ALPHA * (1 - f)), WAVE_DOT_SPACING)
    if st.t >= P.wave_time then
      st.phase = "idle"
      st.timer = next_interval()
    end
  end
end

local function step()
  if not built then
    if map_seed == nil then return end
    build()
  end

  local dt = get_delta_time()
  clock = clock + dt

  -- Se llama siempre para mantener al dia el detector de flanco
  local pressed = debug_pressed()
  if pressed and net_is_host() then
    local i = nearest_site()
    if i ~= nil and reactor_pulse_fire(i) then
      print(string.format("[reactor] pulso del sitio #%d (debug)", i))
    end
  end

  for i, site in ipairs(sites) do
    step_site(i, site, states[i], dt)
  end
end

-- update() falla en silencio: se atrapa el error y se imprime una vez
function update()
  local ok, err = pcall(step)
  if not ok and err ~= last_error then
    last_error = err
    print("[reactor] error: " .. tostring(err))
  end
end
