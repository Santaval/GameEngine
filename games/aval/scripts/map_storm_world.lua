-- =====================================================================
--  Director de las tormentas (entidad invisible, solo script):
--  - Borde: dibuja la banda de tormenta y su borde irregular.
--  - Errantes (#21): el host mantiene WANDERING_STORM.count tormentas vivas
--    (net_spawn world = true); todos las dibujan, y la nave local recibe
--    dano por tiempo dentro y un empuje en la mitad delantera.
--  - Contraccion (#25): map_storm_contraction.lua dibuja la del evento activo
--    y dice si la nave local esta en su zona; aqui se le aplica el dano.
--  Espera a map_seed (como el resto de directores). Publica el global
--  local_in_storm (borde, errante o contraccion).
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local storm = require("map_storm")
local ui = require("ui_helpers")
local contraction = require("map_storm_contraction")

local S = cfg.STORM
local WS = cfg.WANDERING_STORM
local SC = cfg.STORM_CONTRACTION
local B = cfg.STORM_BAND
local W = cfg.WORLD_SIZE

-- Estado compartido de las errantes (netId -> true / netId -> radio); la
-- escena los reinicia y wandering_storm.lua los llena en cada cliente
wandering_storms = wandering_storms or {}
wandering_storm_radius = wandering_storm_radius or {}

-- Segundos entre dos spawns: la tormenta nueva se anota en su primer update(),
-- sin esto el host contaria de menos y crearia de mas
local SPAWN_COOLDOWN = 0.5

local clock = 0
local dmg = storm.new_damage()
local wdmg = storm.new_damage()
local cdmg = storm.new_damage()
local last_error = nil
local spawn_cooldown = 0
local initial_phase = nil
local spawned = 0

local function rand_range(r)
  return r.min + math.random() * (r.max - r.min)
end

-- Spawn de una tormenta: las iniciales en un punto interior lejos del
-- spawn; las de reposicion fuera del mundo, rumbo a la zona central
local function spawn_wandering()
  local r = rand_range(WS.radius)
  local speed = rand_range(WS.speed)
  local x, y, heading
  if initial_phase then
    local lo, hi = B + r, W - B - r
    local sp = cfg.PLAYER_SPAWN
    for _ = 1, 20 do
      x = lo + math.random() * (hi - lo)
      y = lo + math.random() * (hi - lo)
      local dx, dy = x - sp.x, y - sp.y
      if dx * dx + dy * dy >= WS.spawn_clear * WS.spawn_clear then break end
    end
    heading = math.random() * 2 * math.pi
  else
    local side = math.random(1, 4)
    local t = math.random() * W
    if side == 1 then x, y = t, -r
    elseif side == 2 then x, y = t, W + r
    elseif side == 3 then x, y = -r, t
    else x, y = W + r, t end
    local tx = W / 3 + math.random() * W / 3
    local ty = W / 3 + math.random() * W / 3
    heading = math.atan2(ty - y, tx - x)
  end
  net_spawn("wandering_storm.lua", {
    pos = { x, y },
    vel = { math.cos(heading) * speed, math.sin(heading) * speed },
    radius = r,
    world = true,
  })
  spawned = spawned + 1
  spawn_cooldown = SPAWN_COOLDOWN
end

-- Empuja a la nave local si esta en la mitad delantera de la tormenta w
local function push_ship(w, px, py, dt)
  local dx, dy = px - w.x, py - w.y
  local reach = w.r + WS.front_pad
  if dx * dx + dy * dy >= reach * reach then return end
  local sp = math.sqrt(w.vx * w.vx + w.vy * w.vy)
  if sp < 0.001 then return end
  local ux, uy = w.vx / sp, w.vy / sp
  if dx * ux + dy * uy <= 0 then return end
  local vx, vy = get_velocity(player_entity)
  local along = vx * ux + vy * uy
  if along < WS.push_speed then
    local add = math.min(WS.push_speed - along, WS.push_accel * dt)
    set_velocity(player_entity, vx + ux * add, vy + uy * add)
  end
end

local function step()
  if map_seed == nil then return end

  local dt = get_delta_time()
  clock = clock + dt
  local camX, camY = get_camera_position()
  local sw, sh = get_screen_size()
  local frame = storm.frame(clock)

  storm.draw_fill(camX, camY, sw, sh, frame, storm.in_border)

  -- Borde irregular sobre el rectangulo interior [B, W-B]^2, lado irregular hacia dentro
  storm.draw_edge_segment(B, W - B, W - B, W - B, 0, camX, camY, sw, sh, frame)
  storm.draw_edge_segment(B, B, W - B, B, 180, camX, camY, sw, sh, frame)
  storm.draw_edge_segment(B, B, B, W - B, 90, camX, camY, sw, sh, frame)
  storm.draw_edge_segment(W - B, B, W - B, W - B, 270, camX, camY, sw, sh, frame)

  -- Errantes: el host repone hasta WS.count (la cuenta sale de la tabla que
  -- llena cada cliente, asi un host nuevo tras migrar sigue sin duplicar)
  local list = storm.wandering()
  spawn_cooldown = spawn_cooldown - dt
  if net_is_host() and spawn_cooldown <= 0 and #list < WS.count then
    if initial_phase == nil then initial_phase = (clock < 1 and #list == 0) end
    if initial_phase and spawned >= WS.count then initial_phase = false end
    spawn_wandering()
  end

  for _, w in ipairs(list) do
    if w.x + w.r >= camX and w.x - w.r <= camX + sw and w.y + w.r >= camY and w.y - w.r <= camY + sh then
      local r2 = w.r * w.r
      local cx, cy = w.x, w.y
      storm.draw_fill(camX, camY, sw, sh, frame, function(tx, ty)
        local dx, dy = tx - cx, ty - cy
        return dx * dx + dy * dy < r2
      end, cx - w.r, cy - w.r, WS.tile_alpha)
      storm.draw_edge_ring(cx, cy, w.r, WS.edge_height, camX, camY, sw, sh, frame)
    end
  end

  -- Contraccion: dibuja y dice si la nave local esta en su zona
  local alive = player_entity ~= nil and is_alive(player_entity)
  local x, y
  if alive then x, y = get_collider_center(player_entity) end
  local in_c = contraction.step(dt, camX, camY, sw, sh, frame, x, y)

  local inside = false
  if alive then
    local in_border = storm.in_border(x, y)
    local in_w = storm.in_wandering(x, y)
    storm.tick_damage(dmg, player_entity, in_border, dt)
    storm.tick_damage(wdmg, player_entity, in_w, dt, WS.damage, WS.tick)
    storm.tick_damage(cdmg, player_entity, in_c, dt, SC.damage, SC.tick)
    for _, w in ipairs(list) do push_ship(w, x, y, dt) end
    inside = in_border or in_w or in_c
  else
    dmg.acc = 0
    wdmg.acc = 0
    cdmg.acc = 0
  end
  local_in_storm = inside

  if inside then
    local ww, wh = get_window_size()
    storm.draw_tint(ww, wh, S.tint_alpha)
    ui.draw_centered(wh * 0.2, "TORMENTA", "debug-big", 28, 157, 2, 8, 255)
  end
end

-- update() falla en silencio: se atrapa el error y se imprime una vez
function update()
  local ok, err = pcall(step)
  if not ok and err ~= last_error then
    last_error = err
    print("[storm] error: " .. tostring(err))
  end
end
