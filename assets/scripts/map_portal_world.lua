-- =====================================================================
--  Director de los portales estables (#22), entidad invisible, solo script.
--  Espera a map_seed (como el resto de directores), publica el global
--  portal_sites (los pares de map_portals.lua; el minimapa lo lee) y:
--  - dibuja los portales, el halo de aviso, el destello de salida y la
--    distorsion al entrar y salir;
--  - cierra un par mientras una tormenta errante cubre uno de sus extremos y
--    avisa con un halo en el extremo opuesto si una se acerca;
--  - mueve la nave local: tiron suave, entrada, 0.75 s de transito (el
--    extremo de salida destella, tambien en los demas clientes) y salida con
--    la misma rapidez sobre el eje del portal. Lo aplica el duenio de la nave
--    y lo replica con el evento "teleport";
--  - deja pasar las balas (portal_bullet_step, lo llama bullet_lifetime.lua).
--  Publica el global local_portal_transit (lo lee player.lua).
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local portals = require("map_portals")
local storm = require("map_storm")

local P = cfg.PORTAL
local WARNING = cfg.PORTAL_EXIT_WARNING

local VIOLET = { 123, 44, 191 }
local VIOLET_GLOW = { 199, 125, 255 }

-- Alfa del portal de un par cerrado por una tormenta
local CLOSED_ALPHA = 90
-- Margen (px) fuera de pantalla antes de dejar de dibujar un extremo
local CULL_PAD = 400

-- Caja del cooldown (px de pantalla) y su distancia al borde de abajo
local BOX = 32
local BOX_BOTTOM = 90

local sites = nil
local by_id = {}
local clock = 0
local last_error = nil

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
  local pair = by_id[e.pair]
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
  for _, pair in ipairs(sites.pairs) do
    for _, e in ipairs({ pair.a, pair.b }) do
      if inside_storm(list, e.x, e.y, 0) then
        closed[pair.id] = true
      end
      if inside_storm(list, e.x, e.y, P.storm_warn_pad) then
        -- El halo avisa en el extremo opuesto (el de salida)
        warned[key(other_end(e))] = true
      end
    end
  end
end

-- ---------------------------------------------------------------------
--  Dibujo
-- ---------------------------------------------------------------------

local function draw_portals(camX, camY, sw, sh)
  local S = P.sheets
  for _, e in ipairs(sites.ends) do
    if on_screen(e.x, e.y, camX, camY, sw, sh) then
      if warned[key(e)] then
        local f = math.floor(clock * P.fps) % S.halo.count
        draw_frame("portal-warning-halo", S.halo, f, e.x, e.y, P.halo_size, 0, 255, camX, camY)
      end
      -- El arte tiene la muesca hacia arriba: el eje de salida es angle
      local f = math.floor(clock * P.fps) % S.stable.count
      local alpha = closed[e.pair] and CLOSED_ALPHA or 255
      draw_frame("portal-stable", S.stable, f, e.x, e.y, P.draw_size, math.deg(e.angle) + 90, alpha, camX, camY)
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

local function enter(ship, e, cx, cy)
  local vx, vy = get_velocity(ship)
  local px, py = get_position(ship)
  local to = other_end(e)
  transit = {
    to = to, t = WARNING, speed = math.sqrt(vx * vx + vy * vy),
    x = e.x, y = e.y, ox = cx - px, oy = cy - py,
  }
  local_portal_transit = true
  park(ship)
  add_flash(to)
  add_warp(e.x, e.y)
  if net_is_online() then
    net_send("portal_warn", { pair = to.pair, side = to.side })
  end
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

-- Extremo abierto mas cercano a (cx, cy) dentro de pull_radius, y su distancia
local function nearest_open_end(cx, cy)
  local best, best_d2 = nil, P.pull_radius * P.pull_radius
  for _, e in ipairs(sites.ends) do
    if not closed[e.pair] then
      local d2 = (e.x - cx) ^ 2 + (e.y - cy) ^ 2
      if d2 < best_d2 then best, best_d2 = e, d2 end
    end
  end
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
  local e, d = nearest_open_end(cx, cy)
  if e == nil then return end
  if d <= P.enter_radius then
    enter(ship, e, cx, cy)
  elseif d > 0 then
    -- Tiron suave hacia el centro del portal
    local vx, vy = get_velocity(ship)
    local add = P.pull_accel * dt / d
    set_velocity(ship, vx + (e.x - cx) * add, vy + (e.y - cy) * add)
  end
end

-- ---------------------------------------------------------------------
--  Red
-- ---------------------------------------------------------------------

-- Otro jugador va a salir por ese extremo: destella para todos
net_on("portal_warn", function(data, from)
  if sites == nil or type(data) ~= "table" then return end
  local pair = by_id[math.tointeger(data.pair) or -1]
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

function portal_bullet_step(e)
  if sites == nil then return false end
  local cx, cy = get_collider_center(e)
  local r2 = P.enter_radius * P.enter_radius
  for _, en in ipairs(sites.ends) do
    if not closed[en.pair] and (cx - en.x) ^ 2 + (cy - en.y) ^ 2 < r2 then
      local to = other_end(en)
      local px, py = get_position(e)
      local vx, vy = get_velocity(e)
      local speed = math.sqrt(vx * vx + vy * vy)
      local ux, uy = math.cos(to.angle), math.sin(to.angle)
      local nx, ny = to.x + ux * P.exit_offset, to.y + uy * P.exit_offset
      set_position(e, nx - (cx - px), ny - (cy - py))
      set_velocity(e, ux * speed, uy * speed)
      set_rotation_absolute(e, to.angle)
      return true
    end
  end
  return false
end

local function step()
  if sites == nil then
    if map_seed == nil then return end
    sites = portals.sites(map_seed)
    portal_sites = sites
    for _, pair in ipairs(sites.pairs) do by_id[pair.id] = pair end
  end

  local dt = get_delta_time()
  clock = clock + dt
  local camX, camY = get_camera_position()
  local sw, sh = get_screen_size()

  update_storm_state()
  draw_portals(camX, camY, sw, sh)
  draw_flashes(dt, camX, camY, sw, sh)
  draw_warps(dt, camX, camY, sw, sh)
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
