-- =====================================================================
--  Director de eventos del mapa (#24), entidad invisible, solo script.
--  Mantiene vivo el mapa: el host lanza eventos por sector ocupado, respeta
--  los limites, los replica a todos y muestra el aviso de Pal Entertainments.
--  - Tipos: conoce los 6 (nombre, color, icono y duracion en
--    map_config.EVENTS.types), pero un tipo solo se lanza cuando el script que
--    lo implementa lo registra en el global map_event_types[tipo] =
--    { pick(sx, sy) -> params | nil, fire(params) -> bool, on_start(ev),
--      on_end(ev) }. pick (host) devuelve un objetivo elegible del sector (con
--    x, y para el icono del minimapa), fire (host) arranca el efecto, y
--    on_start / on_end (opcionales) corren en TODOS los clientes. Hoy solo
--    registran map_reactor_world.lua (Pulso) y map_portal_world.lua (Colapso);
--    #25 y #26 se enchufan sin tocar este archivo.
--  - Sectores: cada sector ocupado por una nave lleva un temporizador de
--    EVENT_INTERVAL s (solo cuenta mientras esta ocupado). Al llegar a 0 el
--    host elige al azar un tipo registrado que no repita el ultimo de ese
--    sector, que no este ya activo ahi y que tenga objetivo. El tope de
--    eventos activos es ceil(jugadores x 3 / 10), minimo 1. Si no sale nada
--    se reintenta en EVENTS.retry s.
--  - Contraccion de la tormenta: temporizador aparte (STORM_CONTRACTION_INTERVAL);
--    elige un sector ocupado, solo una a la vez y tambien cuenta para el tope.
--  - Estado en todos los clientes (map_events, last_type, temporizadores), asi
--    que si el host cae el nuevo sigue: el host manda "event_start" /
--    "event_end" y, a un recien llegado, "event_state" (en respuesta a
--    snapshot_request). Los demas solo esperan el "event_end" del host.
--  - Aviso: una caja (event_banner) arriba, de a uno, y un icono con el marco
--    del sector en el minimapa (solar_hud.lua lee map_events).
--  - Tecla J (debug_event, solo host): pone a 0 el temporizador del sector de
--    la nave local; las reglas de siempre siguen aplicando.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local ui = require("ui_helpers")

local E = cfg.EVENTS
local SECTORS = cfg.SECTORS

-- Orden fijo de los tipos: todos los clientes eligen entre los mismos
local TYPE_ORDER = {
  "reactor_pulse", "portal_collapse", "storm_contraction",
  "pal_signal", "debris_rain", "overcharged_planet",
}
local CONTRACTION = "storm_contraction"

-- Segundos de fundido al entrar y salir del aviso
local FADE = 0.3
-- Fuente del titulo y su ancho aproximado por caracter (DejaVuSansMono)
local TITLE_SIZE = 28
local CHAR_RATIO = 0.6

local last_error = nil
local debug_pressed = ui.edge("debug_event")

-- Estado (map_events es global: lo crea aval_cup.lua y lo lee el minimapa)
-- last_type[clave] = ultimo tipo lanzado en el sector; sector_timer[clave] = s
-- hasta el siguiente evento de ese sector (solo existe si se ocupo alguna vez)
local last_type = {}
local sector_timer = {}
local contraction_timer = nil
local seq = 0

-- Avisos pendientes { name, color, sx, sy } y el que se ve { ..., t }
local banner_queue = {}
local banner = nil

-- event_state recibido antes de tener la semilla, y si ya se aplico uno
local incoming_state = nil
local state_applied = false

-- Esto es de ejecucion, no de generacion del mapa: math.random esta bien
local function rand_range(r)
  return r.min + math.random() * (r.max - r.min)
end

local function sector_key(sx, sy)
  return sx .. ":" .. sy
end

local function hook_of(type)
  return map_event_types and map_event_types[type] or nil
end

-- Copia solo los valores simples de params (numeros, textos y booleanos)
local function copy_params(p)
  local out = {}
  if type(p) ~= "table" then return out end
  for k, v in pairs(p) do
    local tv = type(v)
    if type(k) == "string" and (tv == "number" or tv == "string" or tv == "boolean") then
      out[k] = v
    end
  end
  return out
end

local function count_events()
  local n = 0
  for _ in pairs(map_events) do n = n + 1 end
  return n
end

-- true si ya hay un evento activo de ese tipo (en el sector (sx, sy) si se da)
local function type_active(type, sx, sy)
  for _, ev in pairs(map_events) do
    if ev.type == type and (sx == nil or (ev.sx == sx and ev.sy == sy)) then return true end
  end
  return false
end

-- Tope de eventos activos segun los jugadores conectados
local function event_cap()
  local players = 1 + #net_peers()
  return math.max(1, math.ceil(players * E.per_players.events / E.per_players.players))
end

local function new_id()
  seq = seq + 1
  local me = net_my_id()
  if me == "" then me = "local" end
  return me .. "#" .. seq
end

local function push_banner(type, sx, sy)
  local def = E.types[type]
  banner_queue[#banner_queue + 1] = { name = def.name, color = def.color, sx = sx, sy = sy }
end

-- ---------------------------------------------------------------------
--  Alta y baja de eventos
-- ---------------------------------------------------------------------

-- Anade el evento a todos los clientes; las altas del host y las de la red
-- pasan por aqui. Devuelve false si el id ya existe
local function add_event(ev)
  if map_events[ev.id] ~= nil then return false end
  map_events[ev.id] = ev
  last_type[sector_key(ev.sx, ev.sy)] = ev.type
  push_banner(ev.type, ev.sx, ev.sy)
  local hook = hook_of(ev.type)
  if hook ~= nil and hook.on_start ~= nil then hook.on_start(ev) end
  return true
end

local function remove_event(id)
  local ev = map_events[id]
  if ev == nil then return end
  map_events[id] = nil
  local hook = hook_of(ev.type)
  if hook ~= nil and hook.on_end ~= nil then hook.on_end(ev) end
end

-- Host: termina el evento y lo avisa
local function end_event(id)
  local ev = map_events[id]
  if ev == nil then return end
  remove_event(id)
  net_send("event_end", { id = ev.id, type = ev.type, sx = ev.sx, sy = ev.sy })
end

-- Host: arranca el efecto del tipo y da de alta el evento. false si no salio
local function start_event(type, sx, sy, params)
  local hook = hook_of(type)
  if hook == nil or not hook.fire(params) then return false end
  local ev = {
    id = new_id(), type = type, sx = sx, sy = sy,
    params = copy_params(params), t = E.types[type].duration,
  }
  add_event(ev)
  net_send("event_start", {
    id = ev.id, type = ev.type, sx = sx, sy = sy, params = ev.params, t = ev.t,
  })
  return true
end

-- ---------------------------------------------------------------------
--  Red
-- ---------------------------------------------------------------------

local function to_int(v)
  if type(v) ~= "number" then return nil end
  return math.tointeger(v) or math.tointeger(math.floor(v))
end

-- Evento valido de la red o nil: tipo conocido, sector dentro de la rejilla
local function parse_event(d)
  if type(d) ~= "table" or type(d.id) ~= "string" or type(d.type) ~= "string" then return nil end
  if E.types[d.type] == nil then return nil end
  local sx, sy = to_int(d.sx), to_int(d.sy)
  if sx == nil or sy == nil or sx < 0 or sy < 0 or sx >= SECTORS or sy >= SECTORS then return nil end
  if type(d.t) ~= "number" then return nil end
  return { id = d.id, type = d.type, sx = sx, sy = sy, params = copy_params(d.params), t = d.t }
end

-- Solo se acepta lo del host, y nunca lo propio (el host ya lo aplico)
local function from_host(from)
  return from == net_host_id() and from ~= net_my_id()
end

net_on("event_start", function(data, from)
  if not from_host(from) then return end
  if map_seed == nil then return end
  local ev = parse_event(data)
  if ev ~= nil then add_event(ev) end
end)

net_on("event_end", function(data, from)
  if not from_host(from) then return end
  if type(data) ~= "table" or type(data.id) ~= "string" then return end
  remove_event(data.id)
end)

-- Un jugador acaba de entrar: el host le manda los eventos activos y el ultimo
-- tipo de cada sector, directo
net_on("snapshot_request", function(_, from)
  if not net_is_host() or from == nil or from == "" or from == net_my_id() then return end
  if map_seed == nil then return end
  local list = {}
  for _, ev in pairs(map_events) do
    list[#list + 1] = { id = ev.id, type = ev.type, sx = ev.sx, sy = ev.sy, params = ev.params, t = ev.t }
  end
  local last = {}
  for k, v in pairs(last_type) do last[k] = v end
  net_send("event_state", { events = list, last = last }, from)
end)

-- Reemplaza los eventos y los ultimos tipos con event_state (sin avisos)
local function apply_state(data)
  state_applied = true
  for id in pairs(map_events) do map_events[id] = nil end
  if type(data.events) == "table" then
    for _, d in ipairs(data.events) do
      local ev = parse_event(d)
      if ev ~= nil then map_events[ev.id] = ev end
    end
  end
  last_type = {}
  if type(data.last) == "table" then
    for k, v in pairs(data.last) do
      if type(k) == "string" and type(v) == "string" and E.types[v] ~= nil then last_type[k] = v end
    end
  end
end

net_on("event_state", function(data, from)
  if not from_host(from) then return end
  if type(data) ~= "table" or state_applied then return end
  if map_seed == nil then incoming_state = data
  else apply_state(data) end
end)

-- ---------------------------------------------------------------------
--  Sectores ocupados y temporizadores
-- ---------------------------------------------------------------------

-- Sectores con al menos una nave viva: set clave -> { sx, sy }
local function occupied_sectors()
  local occ = {}
  local function add(x, y)
    local sx, sy = grid.world_to_sector(x, y)
    occ[sector_key(sx, sy)] = { sx = sx, sy = sy }
  end
  if player_entity ~= nil and is_alive(player_entity) then
    add(get_collider_center(player_entity))
  end
  if player_ships ~= nil then
    for id in pairs(player_ships) do
      local e = find_by_net_id(id)
      if e ~= nil and is_alive(e) then add(get_collider_center(e)) end
    end
  end
  return occ
end

-- Tipos registrados (salvo la contraccion) que pueden salir en el sector
-- (sx, sy): distintos del ultimo de ese sector, sin otro activo ahi y con
-- objetivo. Devuelve la lista de { type, params }
local function sector_candidates(sx, sy)
  local list = {}
  local last = last_type[sector_key(sx, sy)]
  for _, type in ipairs(TYPE_ORDER) do
    local hook = hook_of(type)
    if hook ~= nil and type ~= CONTRACTION and type ~= last and not type_active(type, sx, sy) then
      local params = hook.pick(sx, sy)
      if params ~= nil then list[#list + 1] = { type = type, params = params } end
    end
  end
  return list
end

-- Un sector llego a 0: solo el host lanza. true si salio un evento
local function try_sector_event(sx, sy, active, cap)
  if not net_is_host() or active >= cap then return false end
  local list = sector_candidates(sx, sy)
  if #list == 0 then return false end
  local c = list[math.random(1, #list)]
  return start_event(c.type, sx, sy, c.params)
end

-- La contraccion de la tormenta: un sector ocupado al azar que no tuviera ya
-- una contraccion de ultimo evento. true si salio
local function try_contraction(occ, active, cap)
  local hook = hook_of(CONTRACTION)
  if hook == nil or not net_is_host() then return false end
  if type_active(CONTRACTION) or active >= cap then return false end
  local list = {}
  for sx = 0, SECTORS - 1 do
    for sy = 0, SECTORS - 1 do
      local key = sector_key(sx, sy)
      if occ[key] ~= nil and last_type[key] ~= CONTRACTION then
        local params = hook.pick(sx, sy)
        if params ~= nil then list[#list + 1] = { sx = sx, sy = sy, params = params } end
      end
    end
  end
  if #list == 0 then return false end
  local c = list[math.random(1, #list)]
  return start_event(CONTRACTION, c.sx, c.sy, c.params)
end

local function step_events(dt)
  -- Todos llevan la cuenta; el host cierra los eventos, los demas esperan el event_end
  local expired = {}
  for id, ev in pairs(map_events) do
    ev.t = math.max(0, ev.t - dt)
    if ev.t <= 0 then expired[#expired + 1] = id end
  end
  if net_is_host() then
    for _, id in ipairs(expired) do end_event(id) end
  end
end

local function step_sectors(dt, occ, pressed)
  -- Un sector recien ocupado arranca con su espera
  for key in pairs(occ) do
    if sector_timer[key] == nil then sector_timer[key] = rand_range(cfg.EVENT_INTERVAL) end
  end

  -- Tecla J: el sector de la nave local vence ya
  if pressed and net_is_host() and player_entity ~= nil and is_alive(player_entity) then
    local sx, sy = grid.world_to_sector(get_collider_center(player_entity))
    sector_timer[sector_key(sx, sy)] = 0
    print(string.format("[event] sector (%d,%d) forzado (debug)", sx, sy))
  end

  -- En orden de sector para que todos los clientes resuelvan igual
  for sx = 0, SECTORS - 1 do
    for sy = 0, SECTORS - 1 do
      local key = sector_key(sx, sy)
      if occ[key] ~= nil then
        sector_timer[key] = sector_timer[key] - dt
        if sector_timer[key] <= 0 then
          local active = count_events()
          if try_sector_event(sx, sy, active, event_cap()) then
            sector_timer[key] = rand_range(cfg.EVENT_INTERVAL)
          elseif net_is_host() then
            sector_timer[key] = E.retry
          else
            sector_timer[key] = rand_range(cfg.EVENT_INTERVAL)
          end
        end
      end
    end
  end
  return count_events()
end

local function step_contraction(dt, occ)
  contraction_timer = contraction_timer - dt
  if contraction_timer > 0 then return end
  if hook_of(CONTRACTION) == nil or not net_is_host() then
    contraction_timer = rand_range(cfg.STORM_CONTRACTION_INTERVAL)
  elseif try_contraction(occ, count_events(), event_cap()) then
    contraction_timer = rand_range(cfg.STORM_CONTRACTION_INTERVAL)
  else
    contraction_timer = E.retry
  end
end

-- ---------------------------------------------------------------------
--  Aviso
-- ---------------------------------------------------------------------

local function draw_banner(dt)
  if banner == nil and #banner_queue > 0 then
    banner = banner_queue[1]
    banner.t = 0
    local rest = {}
    for i = 2, #banner_queue do rest[#rest + 1] = banner_queue[i] end
    banner_queue = rest
  end
  if banner == nil then return end

  banner.t = banner.t + dt
  if banner.t >= E.banner_time then
    banner = nil
    return
  end
  local f = math.min(1, banner.t / FADE, (E.banner_time - banner.t) / FADE)
  local alpha = math.floor(255 * f)

  local w = get_window_size()
  local b = E.banner
  draw_image("event-banner", (w - b.w) / 2, b.y, b.w, b.h, alpha, "hud", { src = E.banner_src })
  ui.draw_centered(b.y + 10, "PAL ENTERTAINMENTS", "small", 10, 200, 210, 230, alpha)

  local c = banner.color
  local text = string.format("%s  -  SECTOR (%d,%d)", banner.name, banner.sx, banner.sy)
  -- Si el titulo no cabe en la caja se baja a la fuente de 16
  if #text * TITLE_SIZE * CHAR_RATIO > b.w - 60 then
    ui.draw_centered(b.y + 38, text, "default", 16, c[1], c[2], c[3], alpha)
  else
    ui.draw_centered(b.y + 30, text, "debug-big", TITLE_SIZE, c[1], c[2], c[3], alpha)
  end
end

-- ---------------------------------------------------------------------
--  Bucle
-- ---------------------------------------------------------------------

local function step()
  -- Se llama siempre para mantener al dia el detector de flanco
  local pressed = debug_pressed()
  if map_seed == nil then return end
  if contraction_timer == nil then
    contraction_timer = rand_range(cfg.STORM_CONTRACTION_INTERVAL)
    if incoming_state ~= nil then
      apply_state(incoming_state)
      incoming_state = nil
    end
  end

  local dt = get_delta_time()

  local occ = occupied_sectors()
  step_events(dt)
  step_sectors(dt, occ, pressed)
  step_contraction(dt, occ)
  draw_banner(dt)
end

-- update() falla en silencio: se atrapa el error y se imprime una vez
function update()
  local ok, err = pcall(step)
  if not ok and err ~= last_error then
    last_error = err
    print("[event] error: " .. tostring(err))
  end
end
