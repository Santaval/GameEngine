-- Logica pura de la pelea contra el simio de los Caliles (sin motor, determinista). Las posiciones son el
-- CENTRO DE LOS PIES en px de mundo (el jugador: px + 12, py + 32). simio.lua las convierte a entidades.
-- Fases: appear -> chase -> windup -> lunge -> recover -> chase ...; stagger al recibir un golpe;
-- flee -> done al caer el simio; lost si el jugador se queda sin vida.
-- Eventos de step(): appeared, windup, player_hit, player_down, simio_hit, simio_down, miss, cooldown, gone.
local M = {}

M.CONFIG = {
  simio_hp = 6, player_hp = 5,
  chase_speed = 95,          -- px/s (caminar del jugador = 130, correr = 200)
  chase_speed_furia = 110,   -- con la vida del simio <= furia_hp
  furia_hp = 3,
  engage_dist = 44,          -- distancia a la que empieza a preparar el golpe
  windup = 0.6, windup_furia = 0.45,
  lunge_speed = 280, lunge_time = 0.22, lunge_hit_r = 20,
  recover = 0.8,             -- quieto tras la embestida: ventana para castigarlo
  attack_cooldown = 1.4,
  stagger = 0.35, stagger_push = 90, stagger_push_time = 0.15,
  simio_iframes = 0.35, player_iframes = 1.0,
  knock_time = 0.18,         -- el retroceso lo aplica simio.lua con un input temporal
  slash_cd = 0.45, slash_reach = 34, slash_half_w = 18,
  appear_speed = 60, appear_to_y = 1900,
  flee_speed = 180, flee_time = 1.4,
  ARENA = { x = 7420, y = 1776, w = 640, h = 300 },   -- hasta donde llega el simio
  LEASH = { x = 7380, y = 1700, w = 720, h = 420 },   -- el jugador fuera de esto huyo de la pelea
}

local UNIT = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

function M.facing_vec(f)
  local u = UNIT[f] or UNIT.down
  return u[1], u[2]
end

-- "up" | "down" | "left" | "right" segun el eje dominante (para las animaciones walk_ / idle_)
function M.dir_name(dx, dy)
  if math.abs(dx) > math.abs(dy) then return dx > 0 and "right" or "left" end
  return dy > 0 and "down" or "up"
end

function M.in_rect(x, y, r)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- true mientras el jugador siga dentro del area de la pelea
function M.leashed(cfg, px, py) return M.in_rect(px, py, cfg.LEASH) end

-- El golpe del machete: rectangulo corto delante del jugador (alcance y mitad del ancho)
function M.slash_hits(px, py, facing, sx, sy, cfg)
  local vx, vy = M.facing_vec(facing)
  local dx, dy = sx - px, sy - py
  local along = dx * vx + dy * vy
  local perp = dx * -vy + dy * vx
  return along >= 0 and along <= cfg.slash_reach and math.abs(perp) <= cfg.slash_half_w
end

function M.new(cfg, sx, sy)
  return {
    phase = "appear", sx = sx, sy = sy, hp = cfg.simio_hp, php = cfg.player_hp, t = 0,
    cd = 0, inv = 0, pinv = 0, slash_cd = 0, dir = "up",
    ldx = 0, ldy = 1, pdx = 0, pdy = 1, kdx = 0, kdy = 0,
  }
end

function M.furia(st, cfg) return st.hp <= cfg.furia_hp end

local function norm(dx, dy)
  local l = math.sqrt(dx * dx + dy * dy)
  if l < 1e-6 then return 0, 1 end
  return dx / l, dy / l
end

local function clamp_arena(st, cfg)
  local a = cfg.ARENA
  if st.sx < a.x then st.sx = a.x elseif st.sx > a.x + a.w then st.sx = a.x + a.w end
  if st.sy < a.y then st.sy = a.y elseif st.sy > a.y + a.h then st.sy = a.y + a.h end
end

local function move(st, dx, dy, speed, dt)
  st.sx, st.sy = st.sx + dx * speed * dt, st.sy + dy * speed * dt
  st.dir = M.dir_name(dx, dy)
end

local function to_phase(st, phase) st.phase, st.t = phase, 0 end

-- El golpe del jugador (inp.slash es un flanco: una pulsacion = un intento)
local function slash(st, cfg, inp, ev)
  local p = st.phase
  if p == "appear" or p == "flee" or p == "done" or p == "lost" then return end
  if st.slash_cd > 0 then ev[#ev + 1] = "cooldown"; return end
  st.slash_cd = cfg.slash_cd
  if st.inv <= 0 and M.slash_hits(inp.px, inp.py, inp.facing, st.sx, st.sy, cfg) then
    st.hp = st.hp - 1
    st.inv = cfg.simio_iframes
    ev[#ev + 1] = "simio_hit"
    if st.hp <= 0 then
      ev[#ev + 1] = "simio_down"
      to_phase(st, "flee")
    elseif p ~= "lunge" then -- una embestida en curso no se interrumpe (seria demasiado facil)
      st.pdx, st.pdy = norm(st.sx - inp.px, st.sy - inp.py)
      to_phase(st, "stagger")
    end
  else
    ev[#ev + 1] = "miss"
  end
end

-- inp = { px, py, slash, facing }; devuelve la lista de eventos de este paso
function M.step(st, cfg, dt, inp)
  local ev = {}
  if st.phase == "done" or st.phase == "lost" then return ev end
  st.t = st.t + dt
  st.cd = math.max(0, st.cd - dt)
  st.inv = math.max(0, st.inv - dt)
  st.pinv = math.max(0, st.pinv - dt)
  st.slash_cd = math.max(0, st.slash_cd - dt)

  if inp.slash then slash(st, cfg, inp, ev) end
  local p = st.phase

  if p == "appear" then
    move(st, 0, -1, cfg.appear_speed, dt)
    if st.sy <= cfg.appear_to_y then to_phase(st, "chase"); ev[#ev + 1] = "appeared" end
  elseif p == "chase" then
    local dx, dy = norm(inp.px - st.sx, inp.py - st.sy)
    local speed = M.furia(st, cfg) and cfg.chase_speed_furia or cfg.chase_speed
    move(st, dx, dy, speed, dt)
    clamp_arena(st, cfg)
    local dist = math.sqrt((inp.px - st.sx) ^ 2 + (inp.py - st.sy) ^ 2)
    if dist <= cfg.engage_dist and st.cd <= 0 then
      st.ldx, st.ldy = norm(inp.px - st.sx, inp.py - st.sy)
      st.dir = M.dir_name(st.ldx, st.ldy)
      to_phase(st, "windup")
      ev[#ev + 1] = "windup"
    end
  elseif p == "windup" then
    if st.t >= (M.furia(st, cfg) and cfg.windup_furia or cfg.windup) then to_phase(st, "lunge") end
  elseif p == "lunge" then
    move(st, st.ldx, st.ldy, cfg.lunge_speed, dt)
    clamp_arena(st, cfg)
    local dist = math.sqrt((inp.px - st.sx) ^ 2 + (inp.py - st.sy) ^ 2)
    if st.pinv <= 0 and dist <= cfg.lunge_hit_r then
      st.php = st.php - 1
      st.pinv = cfg.player_iframes
      st.kdx, st.kdy = st.ldx, st.ldy
      ev[#ev + 1] = "player_hit"
      if st.php <= 0 then
        ev[#ev + 1] = "player_down"
        to_phase(st, "lost")
        return ev
      end
    end
    if st.t >= cfg.lunge_time then st.cd = cfg.attack_cooldown; to_phase(st, "recover") end
  elseif p == "recover" then
    if st.t >= cfg.recover then to_phase(st, "chase") end
  elseif p == "stagger" then
    if st.t <= cfg.stagger_push_time then
      st.sx, st.sy = st.sx + st.pdx * cfg.stagger_push * dt, st.sy + st.pdy * cfg.stagger_push * dt
      clamp_arena(st, cfg)
    end
    if st.t >= cfg.stagger then to_phase(st, "chase") end
  elseif p == "flee" then
    move(st, 0, 1, cfg.flee_speed, dt)
    if st.t >= cfg.flee_time then to_phase(st, "done"); ev[#ev + 1] = "gone" end
  end
  return ev
end

return M
