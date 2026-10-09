-- =====================================================================
--  Director de los portales (#22 estables, #23 inestables, nexus y colapso),
--  entidad invisible, solo script.
--  Espera a map_seed (como el resto de directores), publica el global
--  portal_sites ({ends, nexus, collapsing}; el minimapa lo lee) y:
--  - dibuja los portales, el halo de aviso, el destello de salida y la
--    distorsion al entrar y salir;
--  - cierra un par mientras una tormenta errante cubre uno de sus extremos y
--    avisa con un halo en el extremo opuesto si una se acerca;
--  - mueve la nave local: tiron suave, entrada, 0.75 s de transito (el
--    extremo de salida destella, tambien en los demas clientes) y salida con
--    la misma rapidez sobre el eje del portal. Lo aplica el duenio de la nave
--    y lo replica con el evento "teleport";
--  - deja pasar las balas (portal_bullet_step, lo llama bullet_lifetime.lua).
--  #23, todo del host y replicado:
--  - Colapso: tras PORTAL_COLLAPSE.warning s un par estable parpadea como
--    inestable y se cierra; su sitio vuelve a la cola y el par (mismo id)
--    se abre en el primer sitio libre de otros sectores. Siempre hay 12.
--    portal_collapse_fire(id) lo dispara (el director de eventos, #24); hasta
--    entonces lo hacen un temporizador del host y la tecla L (debug_collapse).
--  - Nexus: 4 bocas; el angulo de entrada elige la salida (E, S, O, N).
--  - Inestables: entidades unstable_portal.lua (net_spawn world = true) de
--    ida, a un punto al azar; destruyen las balas. El host las repone.
--  - Un recien llegado recibe portal_state (historial de colapsos, avisos en
--    curso y vida de los inestables) en respuesta a snapshot_request.
--  Publica el global local_portal_transit (lo lee player.lua).
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local portals = require("map_portals")
local storm = require("map_storm")
local ui = require("ui_helpers")

local P = cfg.PORTAL
local WARNING = cfg.PORTAL_EXIT_WARNING
local UP = cfg.UNSTABLE_PORTAL
local NX = cfg.NEXUS
local PC = cfg.PORTAL_COLLAPSE
local B = cfg.STORM_BAND
local W = cfg.WORLD_SIZE
local CLEAR = cfg.PORTAL_CLEAR_RADIUS

local VIOLET = { 123, 44, 191 }
local VIOLET_GLOW = { 199, 125, 255 }

-- Alfa del portal de un par cerrado por una tormenta
local CLOSED_ALPHA = 90
-- Margen (px) fuera de pantalla antes de dejar de dibujar un extremo
local CULL_PAD = 400

-- Caja del cooldown (px de pantalla) y su distancia al borde de abajo
local BOX = 32
local BOX_BOTTOM = 90

-- Distancia (px) a la que se ve el aviso de colapso de un par
local COLLAPSE_WARN_DIST = 2000
local COLLAPSE_COLOR = { 255, 90, 90 }
-- Parpadeo del par que colapsa: periodo (s), y el mas rapido de los ultimos 3 s
local BLINK_SLOW = 0.15
local BLINK_FAST = 0.07
local FAST_TIME = 3
-- Cambio de frame del inestable (s): salta de forma irregular
local UNSTABLE_STEP = 0.09

local sites = nil
local clock = 0
local last_error = nil
local debug_pressed = ui.edge("debug_collapse")

-- Estado vivo (#23): pairs (id -> par, con open = s que faltan para poder
-- entrar), ends (lista plana, se rehace al cambiar), pool (cola de sitios
-- libres). history: ids de los pares colapsados, en orden (lo reenvia el host
-- a un recien llegado). collapsing[id] = { t = s hasta cerrar }
local live = { pairs = {}, ends = {}, pool = {} }
local history = {}
local collapsing = {}
-- Efectos de cierre { x, y, angle, t } y estado visual de cada inestable
local collapse_fx = {}
local ustate = {}
-- Temporizador de colapso, tiradas del host para los inestables
local collapse_timer = 0
local spawn_cooldown = 1
local spawn_roll = 1
-- portal_state recibido antes de tener la semilla, y si ya se aplico uno
local incoming_state = nil
local state_applied = false

-- Par cerrado (pair -> true) y extremos con halo ("pair:side" -> true); se
-- recalculan cada frame
local closed = {}
local warned = {}

-- Destellos de salida { e = extremo, t }, distorsiones { x, y, t } y nave local
local flashes = {}
local warps = {}
local cooldown = 0
local transit = nil

local_portal_transit = false

local function key(e)
  return e.pair .. ":" .. e.side
end

local function other_end(e)
  local pair = live.pairs[e.pair]
  if e.side == "a" then return pair.b end
  return pair.a
end

-- Rect fuente del frame i de una hoja de P.sheets y alto de dibujo para un
-- ancho dw (se conserva la proporcion del frame)
local function frame_of(sheet, i)
  local fw = math.floor(sheet.w / sheet.count)
  return { x = math.floor(i * sheet.w / sheet.count), y = 0, w = fw, h = sheet.h }, fw
end

-- Dibuja un frame centrado en (x, y) del mundo. angle en grados
local function draw_frame(asset, sheet, i, x, y, size, angle, alpha, camX, camY)
  local src, fw = frame_of(sheet, i)
  local dh = size * sheet.h / fw
  draw_image(asset, x - camX - size / 2, y - camY - dh / 2, size, dh, alpha, "front",
    { src = src, angle = angle })
end

local function on_screen(x, y, camX, camY, sw, sh)
  return x >= camX - CULL_PAD and x <= camX + sw + CULL_PAD
     and y >= camY - CULL_PAD and y <= camY + sh + CULL_PAD
end

local function add_warp(x, y)
  warps[#warps + 1] = { x = x, y = y, t = 0 }
end

local function add_flash(e)
  flashes[#flashes + 1] = { e = e, t = 0 }
end

local function rand_range(r)
  return r.min + math.random() * (r.max - r.min)
end

-- Copia un sitio como par vivo con id; open = s hasta poder entrar
local function assign(slot, id, open)
  local a, b = {}, {}
  for k, v in pairs(slot.a) do a[k] = v end
  for k, v in pairs(slot.b) do b[k] = v end
  a.pair = id
  b.pair = id
  return { id = id, a = a, b = b, open = open }
end

-- Rehace la lista plana de extremos (en orden de id: igual en todos los
-- clientes) y la republica para el minimapa
local function rebuild_ends()
  local list = {}
  for id = 1, cfg.STABLE_PORTAL_PAIRS do
    local pair = live.pairs[id]
    if pair ~= nil then
      list[#list + 1] = pair.a
      list[#list + 1] = pair.b
    end
  end
  live.ends = list
  if portal_sites ~= nil then portal_sites.ends = list end
end

-- true si un extremo se puede usar: sin tormenta encima y ya abierto del todo
local function end_open(e)
  return not closed[e.pair] and live.pairs[e.pair].open <= 0
end

-- true si el inestable u (entrada de unstable_portals) ya abrio y no se cierra
local function unstable_open(u)
  return u.age >= UP.open_time and u.life > 0
end

-- true si (x, y) esta en alguna de las tormentas de la lista (mas pad px)
local function inside_storm(list, x, y, pad)
  for _, w in ipairs(list) do
    local dx, dy = x - w.x, y - w.y
    local rr = w.r + pad
    if dx * dx + dy * dy < rr * rr then return true end
  end
  return false
end

-- Recalcula que pares estan cerrados y que extremos llevan halo
local function update_storm_state()
  closed = {}
  warned = {}
  local list = storm.wandering()
  if #list == 0 then return end
  for _, e in ipairs(live.ends) do
    if inside_storm(list, e.x, e.y, 0) then
      closed[e.pair] = true
    end
    if inside_storm(list, e.x, e.y, P.storm_warn_pad) then
      -- El halo avisa en el extremo opuesto (el de salida)
      warned[key(other_end(e))] = true
    end
  end
end

-- ---------------------------------------------------------------------
--  Dibujo
-- ---------------------------------------------------------------------

-- true si el parpadeo esta en su fase apagada; t = s que quedan
local function blink_off(t)
  local period = t < FAST_TIME and BLINK_FAST or BLINK_SLOW
  return math.floor(clock / period) % 2 == 1
end

local function draw_portals(camX, camY, sw, sh)
  local S = P.sheets
  local n = sites.nexus
  if n ~= nil and on_screen(n.x, n.y, camX, camY, sw, sh) then
    local f = math.floor(clock * P.fps) % S.nexus.count
    draw_frame("nexus", S.nexus, f, n.x, n.y, NX.draw_size, 0, 255, camX, camY)
  end
  for _, e in ipairs(live.ends) do
    if on_screen(e.x, e.y, camX, camY, sw, sh) then
      if warned[key(e)] then
        local f = math.floor(clock * P.fps) % S.halo.count
        draw_frame("portal-warning-halo", S.halo, f, e.x, e.y, P.halo_size, 0, 255, camX, camY)
      end
      -- El arte tiene la muesca hacia arriba: el eje de salida es angle
      local pair = live.pairs[e.pair]
      local col = collapsing[e.pair]
      local angle = math.deg(e.angle) + 90
      if pair.open > 0 then
        -- Par recien abierto: anima portal-open, aun no se puede entrar
        local f = math.min(S.open.count - 1, math.floor((1 - pair.open / UP.open_time) * S.open.count))
        draw_frame("portal-open", S.open, f, e.x, e.y, P.draw_size, angle, 255, camX, camY)
      elseif col ~= nil then
        -- Aviso de colapso: se ve inestable y parpadea
        local f = math.floor(clock * P.fps) % S.unstable.count
        local alpha = blink_off(col.t) and 80 or 255
        draw_frame("portal-unstable", S.unstable, f, e.x, e.y, P.draw_size, angle, alpha, camX, camY)
      else
        local f = math.floor(clock * P.fps) % S.stable.count
        local alpha = closed[e.pair] and CLOSED_ALPHA or 255
        draw_frame("portal-stable", S.stable, f, e.x, e.y, P.draw_size, angle, alpha, camX, camY)
      end
    end
  end
end

-- Cierre de los extremos de un par que colapso (portal-collapse)
local function draw_collapse_fx(dt, camX, camY, sw, sh)
  local S = P.sheets.collapse
  local keep = {}
  for _, fx in ipairs(collapse_fx) do
    fx.t = fx.t + dt
    if fx.t < UP.collapse_time then
      keep[#keep + 1] = fx
      if on_screen(fx.x, fx.y, camX, camY, sw, sh) then
        local f = math.min(S.count - 1, math.floor(fx.t / UP.collapse_time * S.count))
        draw_frame("portal-collapse", S, f, fx.x, fx.y, P.draw_size, math.deg(fx.angle) + 90, 255, camX, camY)
      end
    end
  end
  collapse_fx = keep
end

-- Portales inestables: los anota unstable_portal.lua en unstable_portals. Aqui
-- se descartan los que ya no existen y se dibujan segun edad y vida
local function draw_unstable(dt, camX, camY, sw, sh)
  if unstable_portals == nil then return end
  local S = P.sheets
  for id, u in pairs(unstable_portals) do
    local e = find_by_net_id(id)
    if e == nil or not is_alive(e) then
      unstable_portals[id] = nil
      ustate[id] = nil
    elseif on_screen(u.x, u.y, camX, camY, sw, sh) then
      if u.life <= 0 then
        local f = math.min(S.collapse.count - 1, math.floor(-u.life / UP.collapse_time * S.collapse.count))
        draw_frame("portal-collapse", S.collapse, f, u.x, u.y, UP.draw_size, 0, 255, camX, camY)
      elseif u.age < UP.open_time then
        local f = math.min(S.open.count - 1, math.floor(u.age / UP.open_time * S.open.count))
        draw_frame("portal-open", S.open, f, u.x, u.y, UP.draw_size, 0, 255, camX, camY)
      else
        -- Frames en orden irregular: salta 1-3 pasos cada UNSTABLE_STEP
        local st = ustate[id]
        if st == nil then st = { f = 0, t = 0 } ustate[id] = st end
        st.t = st.t + dt
        if st.t >= UNSTABLE_STEP then
          st.t = 0
          st.f = (st.f + math.random(1, 3)) % S.unstable.count
        end
        local alpha = 255
        if u.life <= UP.flicker_time and blink_off(u.life) then alpha = 60 end
        draw_frame("portal-unstable", S.unstable, st.f, u.x, u.y, UP.draw_size, 0, alpha, camX, camY)
      end
    end
  end
end

local function draw_flashes(dt, camX, camY, sw, sh)
  local S = P.sheets.flash
  local keep = {}
  for _, fl in ipairs(flashes) do
    fl.t = fl.t + dt
    if fl.t < WARNING then
      keep[#keep + 1] = fl
      local e = fl.e
      if on_screen(e.x, e.y, camX, camY, sw, sh) then
        local f = math.min(S.count - 1, math.floor(fl.t / WARNING * S.count))
        draw_frame("portal-exit-flash", S, f, e.x, e.y, P.flash_size, math.deg(e.angle) + 90, 255, camX, camY)
      end
    end
  end
  flashes = keep
end

local function draw_warps(dt, camX, camY, sw, sh)
  local S = P.sheets.warp
  local keep = {}
  for _, w in ipairs(warps) do
    w.t = w.t + dt
    if w.t < P.warp_time then
      keep[#keep + 1] = w
      if on_screen(w.x, w.y, camX, camY, sw, sh) then
        local f = math.min(S.count - 1, math.floor(w.t / P.warp_time * S.count))
        draw_frame("portal-warp", S, f, w.x, w.y, P.warp_size, 0, 255, camX, camY)
      end
    end
  end
  warps = keep
end

-- Caja de cooldown (sustituye a portal_cooldown.png): se llena de abajo hacia
-- arriba en proporcion al tiempo que queda, con los segundos al lado
local function draw_cooldown()
  if cooldown <= 0 then return end
  local sw, sh = get_screen_size()
  local x, y = (sw - BOX) / 2, sh - BOX_BOTTOM
  local h = BOX * cooldown / cfg.PORTAL_COOLDOWN
  draw_rect(x, y + BOX - h, BOX, h, VIOLET[1], VIOLET[2], VIOLET[3], 255)
  draw_rect(x, y, BOX, BOX, VIOLET_GLOW[1], VIOLET_GLOW[2], VIOLET_GLOW[3], 255, false)
  draw_text(x + BOX + 8, y + 8, string.format("%.1f", cooldown), "default", VIOLET_GLOW[1], VIOLET_GLOW[2], VIOLET_GLOW[3], 255)
end

-- ---------------------------------------------------------------------
--  Nave local
-- ---------------------------------------------------------------------

-- Deja el centro de la nave sobre el portal, quieta
local function park(ship)
  set_position(ship, transit.x - transit.ox, transit.y - transit.oy)
  set_velocity(ship, 0, 0)
  set_acceleration(ship, 0, 0)
end

local function cancel_transit()
  transit = nil
  local_portal_transit = false
end

-- Salida del nexus para un punto (x, y): el angulo respecto al centro es la
-- boca por la que se entro (cubos de 90 grados centrados en E, S, O, N)
local function nexus_exit(n, x, y)
  local a = math.atan(y - n.y, x - n.x)
  local bucket = math.floor((a + math.pi / 4) / (math.pi / 2)) % 4
  return n.exits[bucket + 1]
end

-- Destino al azar de un portal inestable: un punto valido del mundo con un eje
-- al azar. nil si no hay sitio tras UP.tries intentos (la nave no entra)
local function random_destination()
  local lo = B + CLEAR
  local hi = W - lo
  for _ = 1, UP.tries do
    local x = lo + math.random() * (hi - lo)
    local y = lo + math.random() * (hi - lo)
    if portals.valid_point(map_seed, x, y) then
      return { x = x, y = y, angle = math.random() * 2 * math.pi }
    end
  end
  return nil
end

-- Entra en el objetivo t (de find_target). Devuelve false si no pudo
local function enter(ship, t, cx, cy)
  local to
  if t.kind == "end" then
    to = other_end(t.ref)
  elseif t.kind == "nexus" then
    to = nexus_exit(t.ref, cx, cy)
  else
    to = random_destination()
  end
  if to == nil then return false end

  local vx, vy = get_velocity(ship)
  local px, py = get_position(ship)
  transit = {
    to = to, t = WARNING, speed = math.sqrt(vx * vx + vy * vy),
    x = t.x, y = t.y, ox = cx - px, oy = cy - py,
  }
  local_portal_transit = true
  park(ship)
  add_warp(t.x, t.y)
  -- El destino del inestable no se avisa: nadie sabe donde sale
  if t.kind ~= "unstable" then
    add_flash(to)
    if net_is_online() then
      if t.kind == "end" then
        net_send("portal_warn", { pair = to.pair, side = to.side })
      else
        net_send("portal_warn", { nexus = to.dir })
      end
    end
  end
  return true
end

local function leave(ship)
  local to = transit.to
  local ux, uy = math.cos(to.angle), math.sin(to.angle)
  local nx, ny = to.x + ux * P.exit_offset, to.y + uy * P.exit_offset
  local x, y = nx - transit.ox, ny - transit.oy
  local speed = math.max(transit.speed, P.min_exit_speed)
  set_position(ship, x, y)
  set_velocity(ship, ux * speed, uy * speed)
  cooldown = cfg.PORTAL_COOLDOWN
  add_warp(nx, ny)
  cancel_transit()
  -- x, y es la esquina sup-izq (como get_position)
  if net_is_online() then
    local id = get_net_id(ship)
    if id ~= nil then
      net_send("teleport", { netId = id, x = x, y = y, vx = ux * speed, vy = uy * speed })
    end
  end
end

-- Objetivo abierto mas cercano a (cx, cy) dentro de su radio de tiron: un
-- extremo estable, el nexus o un inestable. Devuelve { kind, ref, x, y, enter,
-- accel } y la distancia, o nil
local function find_target(cx, cy)
  local best, best_d2 = nil, math.huge
  local function consider(kind, ref, x, y, enter, pull, accel)
    local d2 = (x - cx) ^ 2 + (y - cy) ^ 2
    if d2 < pull * pull and d2 < best_d2 then
      best_d2 = d2
      best = { kind = kind, ref = ref, x = x, y = y, enter = enter, accel = accel }
    end
  end
  for _, e in ipairs(live.ends) do
    if end_open(e) then consider("end", e, e.x, e.y, P.enter_radius, P.pull_radius, P.pull_accel) end
  end
  local n = sites.nexus
  if n ~= nil then consider("nexus", n, n.x, n.y, NX.enter_radius, NX.pull_radius, P.pull_accel) end
  if unstable_portals ~= nil then
    for _, u in pairs(unstable_portals) do
      if unstable_open(u) then
        consider("unstable", u, u.x, u.y, UP.enter_radius, P.pull_radius, P.pull_accel / 2)
      end
    end
  end
  if best == nil then return nil end
  return best, math.sqrt(best_d2)
end

local function step_ship(dt)
  local ship = player_entity
  if ship == nil or not is_alive(ship) then
    if transit ~= nil then cancel_transit() end
    return
  end

  cooldown = math.max(0, cooldown - dt)

  if transit ~= nil then
    park(ship)
    transit.t = transit.t - dt
    if transit.t <= 0 then leave(ship) end
    return
  end

  if cooldown > 0 then return end

  local cx, cy = get_collider_center(ship)
  local t, d = find_target(cx, cy)
  if t == nil then return end
  if d <= t.enter and enter(ship, t, cx, cy) then return end
  if d > 0 then
    -- Tiron suave hacia el centro del portal
    local vx, vy = get_velocity(ship)
    local add = t.accel * dt / d
    set_velocity(ship, vx + (t.x - cx) * add, vy + (t.y - cy) * add)
  end
end

-- ---------------------------------------------------------------------
--  Colapso de pares (#23)
-- ---------------------------------------------------------------------

-- Primer sitio de la cola que no comparte sector con los extremos de old; si
-- no hay, el primero. Devuelve su indice
local function pick_slot(old)
  local function shares(slot)
    for _, e in ipairs({ slot.a, slot.b }) do
      for _, o in ipairs({ old.a, old.b }) do
        if e.sx == o.sx and e.sy == o.sy then return true end
      end
    end
    return false
  end
  for i, slot in ipairs(live.pool) do
    if not shares(slot) then return i end
  end
  return 1
end

-- Cierra el par id y abre uno nuevo con el mismo id en otro sitio. animate =
-- false al reconstruir el historial de un recien llegado (sin efectos)
local function finish_collapse(id, animate)
  local old = live.pairs[id]
  if old == nil then return end
  collapsing[id] = nil
  if animate then
    for _, e in ipairs({ old.a, old.b }) do
      collapse_fx[#collapse_fx + 1] = { x = e.x, y = e.y, angle = e.angle, t = 0 }
    end
  end

  -- El sitio viejo va al final de la cola; se toma el primer sitio libre
  live.pool[#live.pool + 1] = old
  local idx = pick_slot(old)
  local slot = live.pool[idx]
  local rest = {}
  for i, p in ipairs(live.pool) do
    if i ~= idx then rest[#rest + 1] = p end
  end
  live.pool = rest

  live.pairs[id] = assign(slot, id, animate and UP.open_time or 0)
  history[#history + 1] = id
  rebuild_ends()
end

-- Empieza el aviso de colapso del par id. false si no existe o ya colapsa
local function start_collapse(id, t)
  if live.pairs[id] == nil or collapsing[id] ~= nil then return false end
  collapsing[id] = { t = t or PC.warning }
  return true
end

-- Dispara un colapso: solo el host. Lo llamara el director de eventos (#24);
-- mientras tanto lo llaman el temporizador y la tecla L. Sin id elige un par
-- al azar que no este colapsando. Devuelve el id o false
function portal_collapse_fire(id)
  if sites == nil or not net_is_host() then return false end
  if id == nil then
    local free = {}
    for i = 1, cfg.STABLE_PORTAL_PAIRS do
      if live.pairs[i] ~= nil and collapsing[i] == nil then free[#free + 1] = i end
    end
    if #free == 0 then return false end
    id = free[math.random(1, #free)]
  end
  if not start_collapse(id) then return false end
  if net_is_online() then net_send("portal_collapse", { pair = id }) end
  return id
end

-- Solo se acepta el colapso del host, y nunca el propio (el host ya lo arranco)
net_on("portal_collapse", function(data, from)
  if from ~= net_host_id() then return end
  if from == net_my_id() then return end
  if type(data) ~= "table" or type(data.pair) ~= "number" then return end
  if sites == nil then return end
  start_collapse(math.tointeger(data.pair) or -1)
end)

-- Un jugador acaba de entrar: el host le manda el historial de colapsos, los
-- avisos en curso y la vida de los inestables, directo (la escena base le llega
-- con el snapshot)
net_on("snapshot_request", function(_, from)
  if not net_is_host() or from == nil or from == "" or from == net_my_id() then return end
  if sites == nil then return end

  local hist = {}
  for i, id in ipairs(history) do hist[i] = id end
  local pending = {}
  for id = 1, cfg.STABLE_PORTAL_PAIRS do
    local c = collapsing[id]
    if c ~= nil then pending[#pending + 1] = { pair = id, t = c.t } end
  end
  local unstable = {}
  if unstable_portals ~= nil then
    for id, u in pairs(unstable_portals) do unstable[id] = u.life end
  end
  net_send("portal_state", { history = hist, pending = pending, unstable = unstable }, from)
end)

-- Reconstruye el estado vivo con portal_state: el historial sin animaciones, y
-- luego los avisos en curso y la vida de los inestables
local function apply_state(data)
  state_applied = true
  if type(data.history) == "table" then
    for _, id in ipairs(data.history) do
      finish_collapse(math.tointeger(id) or -1, false)
    end
  end
  if type(data.pending) == "table" then
    for _, p in ipairs(data.pending) do
      if type(p) == "table" and type(p.pair) == "number" and type(p.t) == "number" then
        local id = math.tointeger(p.pair) or -1
        if collapsing[id] ~= nil then collapsing[id].t = p.t
        else start_collapse(id, p.t) end
      end
    end
  end
  if type(data.unstable) == "table" and unstable_portal_life_fix ~= nil then
    for id, life in pairs(data.unstable) do
      if type(id) == "string" and type(life) == "number" then unstable_portal_life_fix[id] = life end
    end
  end
end

net_on("portal_state", function(data, from)
  if from ~= net_host_id() or from == net_my_id() then return end
  if type(data) ~= "table" or state_applied then return end
  if sites == nil then incoming_state = data
  else apply_state(data) end
end)

-- Avanza los avisos: al llegar a 0 el par se cierra y se abre otro. En orden de
-- id para que todos los clientes resuelvan igual
local function step_collapses(dt)
  for id = 1, cfg.STABLE_PORTAL_PAIRS do
    local c = collapsing[id]
    if c ~= nil then
      c.t = c.t - dt
      if c.t <= 0 then finish_collapse(id, true) end
    end
    local pair = live.pairs[id]
    if pair ~= nil and pair.open > 0 then pair.open = math.max(0, pair.open - dt) end
  end

  -- Todos llevan la cuenta (si el host cae, el nuevo sigue); solo el host dispara
  collapse_timer = collapse_timer - dt
  if collapse_timer <= 0 then
    collapse_timer = rand_range(PC.interval)
    portal_collapse_fire()
  end
  if debug_pressed() and net_is_host() then
    local id = portal_collapse_fire()
    if id then print(string.format("[portal] colapso del par #%d (debug)", id)) end
  end
end

-- Aviso centrado si la nave local esta cerca de un par que colapsa
local function draw_collapse_warning()
  if player_entity == nil or not is_alive(player_entity) then return end
  local px, py = get_collider_center(player_entity)
  local best = nil
  for id, c in pairs(collapsing) do
    local pair = live.pairs[id]
    if pair ~= nil then
      for _, e in ipairs({ pair.a, pair.b }) do
        local dx, dy = px - e.x, py - e.y
        if dx * dx + dy * dy <= COLLAPSE_WARN_DIST * COLLAPSE_WARN_DIST then
          if best == nil or c.t < best then best = c.t end
        end
      end
    end
  end
  if best == nil then return end
  local _, h = get_window_size()
  ui.draw_centered(h * 0.2, string.format("COLAPSO DE PORTAL %d", math.ceil(best)), "debug-big", 28,
    COLLAPSE_COLOR[1], COLLAPSE_COLOR[2], COLLAPSE_COLOR[3], 255)
end

-- ---------------------------------------------------------------------
--  Portales inestables: spawn del host
-- ---------------------------------------------------------------------

-- Crea un portal inestable en un punto valido lejos del spawn. true si lo creo
local function spawn_unstable()
  local lo = B + CLEAR
  local hi = W - lo
  local sp = cfg.PLAYER_SPAWN
  for _ = 1, UP.tries do
    local x = lo + math.random() * (hi - lo)
    local y = lo + math.random() * (hi - lo)
    local dx, dy = x - sp.x, y - sp.y
    if dx * dx + dy * dy >= UP.spawn_clear * UP.spawn_clear and portals.valid_point(map_seed, x, y) then
      net_spawn("unstable_portal.lua", {
        pos = { x, y },
        life = rand_range(cfg.UNSTABLE_PORTAL_LIFE),
        world = true,
      })
      return true
    end
  end
  return false
end

-- El host repone hasta ceil(jugadores / per_players) x tirada. La cuenta sale
-- de la tabla que llena cada cliente, asi un host nuevo tras migrar no duplica
local function step_unstable_spawn(dt)
  spawn_cooldown = spawn_cooldown - dt
  if not net_is_host() or spawn_cooldown > 0 then return end
  local count = 0
  if unstable_portals ~= nil then
    for _ in pairs(unstable_portals) do count = count + 1 end
  end
  local players = math.max(1, #net_peers() + 1)
  local target = math.ceil(players / UP.per_players) * spawn_roll
  if count >= target then return end
  if spawn_unstable() then
    spawn_roll = math.random(UP.count.min, UP.count.max)
    spawn_cooldown = rand_range(UP.spawn_interval)
  else
    spawn_cooldown = 1
  end
end

-- ---------------------------------------------------------------------
--  Red
-- ---------------------------------------------------------------------

-- Otro jugador va a salir por ese extremo (o por una boca del nexus): destella
-- para todos
net_on("portal_warn", function(data, from)
  if sites == nil or type(data) ~= "table" then return end
  if data.nexus ~= nil then
    local n = sites.nexus
    local d = math.tointeger(data.nexus)
    if n ~= nil and d ~= nil and n.exits[d + 1] ~= nil then add_flash(n.exits[d + 1]) end
    return
  end
  local pair = live.pairs[math.tointeger(data.pair) or -1]
  if pair == nil then return end
  if data.side == "a" then add_flash(pair.a)
  elseif data.side == "b" then add_flash(pair.b) end
end)

-- El duenio de una nave ya la teletransporto: se coloca la copia sin pasar por
-- la correccion de deriva
net_on("teleport", function(data, from)
  if type(data) ~= "table" or type(data.netId) ~= "string" then return end
  if type(data.x) ~= "number" or type(data.y) ~= "number" then return end
  if type(data.vx) ~= "number" or type(data.vy) ~= "number" then return end
  local e = find_by_net_id(data.netId)
  if e == nil or not is_alive(e) or is_local(e) then return end
  -- Solo vale el aviso del duenio
  if get_owner(e) ~= from then return end
  set_position(e, data.x, data.y)
  set_velocity(e, data.vx, data.vy)
  net_reset_correction(e)
  local cx, cy = get_collider_center(e)
  add_warp(cx, cy)
end)

-- ---------------------------------------------------------------------
--  Balas: lo llama bullet_lifetime.lua con la bala (una vez por bala). Si
--  esta sobre un extremo abierto, sale por el otro con la misma rapidez
--  sobre su eje. Devuelve true si la movio
-- ---------------------------------------------------------------------

-- Saca la bala e (centro cx, cy) por el destino to con la misma rapidez
local function bullet_hop(e, cx, cy, to)
  local px, py = get_position(e)
  local vx, vy = get_velocity(e)
  local speed = math.sqrt(vx * vx + vy * vy)
  local ux, uy = math.cos(to.angle), math.sin(to.angle)
  local nx, ny = to.x + ux * P.exit_offset, to.y + uy * P.exit_offset
  set_position(e, nx - (cx - px), ny - (cy - py))
  set_velocity(e, ux * speed, uy * speed)
  set_rotation_absolute(e, to.angle)
end

-- ported = la bala ya salto una vez. Devuelve true si la movio, "destroyed" si
-- un portal inestable la destruyo (ya no existe) y false si no hizo nada
function portal_bullet_step(e, ported)
  if sites == nil then return false end
  local cx, cy = get_collider_center(e)

  -- Inestables primero: se comen las balas (aunque ya hayan saltado)
  if unstable_portals ~= nil then
    local r2 = UP.enter_radius * UP.enter_radius
    for _, u in pairs(unstable_portals) do
      if unstable_open(u) and (cx - u.x) ^ 2 + (cy - u.y) ^ 2 < r2 then
        destroy_entity(e)
        return "destroyed"
      end
    end
  end
  if ported then return false end

  local r2 = P.enter_radius * P.enter_radius
  for _, en in ipairs(live.ends) do
    if end_open(en) and (cx - en.x) ^ 2 + (cy - en.y) ^ 2 < r2 then
      bullet_hop(e, cx, cy, other_end(en))
      return true
    end
  end

  local n = sites.nexus
  if n ~= nil and (cx - n.x) ^ 2 + (cy - n.y) ^ 2 < NX.enter_radius * NX.enter_radius then
    bullet_hop(e, cx, cy, nexus_exit(n, cx, cy))
    return true
  end
  return false
end

local function step()
  if sites == nil then
    if map_seed == nil then return end
    sites = portals.sites(map_seed)
    for _, pair in ipairs(sites.pairs) do live.pairs[pair.id] = assign(pair, pair.id, 0) end
    for _, slot in ipairs(sites.reserve) do live.pool[#live.pool + 1] = slot end
    portal_sites = { ends = live.ends, nexus = sites.nexus, collapsing = collapsing }
    rebuild_ends()
    collapse_timer = rand_range(PC.interval)
    spawn_roll = math.random(UP.count.min, UP.count.max)
    if incoming_state ~= nil then
      apply_state(incoming_state)
      incoming_state = nil
    end
  end

  local dt = get_delta_time()
  clock = clock + dt
  local camX, camY = get_camera_position()
  local sw, sh = get_screen_size()

  step_collapses(dt)
  step_unstable_spawn(dt)
  update_storm_state()
  draw_portals(camX, camY, sw, sh)
  draw_unstable(dt, camX, camY, sw, sh)
  draw_collapse_fx(dt, camX, camY, sw, sh)
  draw_flashes(dt, camX, camY, sw, sh)
  draw_warps(dt, camX, camY, sw, sh)
  draw_collapse_warning()
  step_ship(dt)
  draw_cooldown()
end

-- update() falla en silencio: se atrapa el error y se imprime una vez
function update()
  local ok, err = pcall(step)
  if not ok and err ~= last_error then
    last_error = err
    print("[portal] error: " .. tostring(err))
  end
end
