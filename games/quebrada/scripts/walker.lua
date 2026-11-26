-- Walker top-down reutilizable (issue #61): movimiento con aceleracion, facing de
-- 4 direcciones, animacion por tag, camara con deadzone y callback de pasos.
-- Sirve para el jugador y para NPCs que caminan. La matematica esta en
-- walker_math.lua (probada sin motor); aqui solo se pega con el motor.
--
-- Uso (un script por entidad; cada entidad necesita su propio cfg/closure):
--   update = require("walker").make_update({ ...cfg... })
--
-- Tags de animacion: tag_prefix .. kind .. "_" .. dir, con kind "idle" / "walk"
-- y dir "down" / "up" / "left" / "right" (p. ej. "walk_left"). Correr reutiliza
-- los tags de caminar salvo que se de run_kind.
--
-- Config (todo opcional; ver M.DEFAULTS):
--   walk_speed, run_speed    px/s (60 / 100)
--   accel_time, decel_time   s para llegar a la velocidad / parar (0.08 / 0.05); 0 = instantaneo
--   tag_prefix               prefijo de los tags ("")
--   walk_kind, idle_kind     "walk" / "idle"; run_kind = nil usa walk_kind
--   start_facing             "down"
--   min_move_speed           px/s a partir de los cuales cuenta como "moviendose" (8)
--   mirror_left              true: la izquierda usa el tag "right" con set_sprite_flip
--   input                    "keyboard" o function(entity, dt) -> dx, dy, run
--   actions                  nombres de accion por direccion; una tecla por nombre
--                            (WASD y flechas son dos nombres: walk_up y walk_up_alt)
--                            { up={..}, down={..}, left={..}, right={..}, run={..} }
--   camera = {
--     follow   = true,
--     deadzone = {w=24, h=16},   tamano TOTAL de la zona donde el objetivo no mueve la camara
--     smooth   = 10,             1/s; 0 = pegada
--     box      = {x,y,w,h},      caja objetivo respecto a get_position (px, escala ya aplicada)
--     bounds   = {x,y,w,h},      limites del mundo; nil = el mapa TMX (get_tile_map_size) o sin limite
--   }
--   footsteps = {
--     frames = {1, 3},           frames (base 0, relativos al tag) en los que cae un paso
--     stride = 14,               px por paso si frames es nil o no hay get_animation_frame
--     on_footstep = function(entity, foot) end,   foot = "left" | "right"; aqui se enchufara el audio
--   }
--
-- API del objeto: M.new(cfg), obj:step(entity), obj:get_facing(),
-- obj:set_facing(dir), obj:is_moving(). M.make_update(cfg) devuelve el closure y
-- el objeto (`local fn, obj = make_update(cfg)`).
local math2 = require("walker_math")

local M = {}

M.DEFAULTS = {
  walk_speed = 60,
  run_speed = 100,
  accel_time = 0.08,
  decel_time = 0.05,
  tag_prefix = "",
  walk_kind = "walk",
  idle_kind = "idle",
  run_kind = nil,
  start_facing = "down",
  min_move_speed = 8,
  input = "keyboard",
  actions = {
    up = { "walk_up", "walk_up_alt" },
    down = { "walk_down", "walk_down_alt" },
    left = { "walk_left", "walk_left_alt" },
    right = { "walk_right", "walk_right_alt" },
    run = { "run", "run_alt" },
  },
  mirror_left = false,
  camera = nil,
  footsteps = nil,
}

local Walker = {}
Walker.__index = Walker

-- true si alguna de las acciones de la lista esta pulsada
local function any_held(list)
  for i = 1, #list do
    if is_action_activated(list[i]) then return true end
  end
  return false
end

local function read_keyboard(actions)
  local dx, dy = 0, 0
  if any_held(actions.right) then dx = dx + 1 end
  if any_held(actions.left) then dx = dx - 1 end
  if any_held(actions.down) then dy = dy + 1 end
  if any_held(actions.up) then dy = dy - 1 end
  return dx, dy, any_held(actions.run)
end

function M.new(cfg)
  cfg = cfg or {}
  local o = {}
  for k, v in pairs(M.DEFAULTS) do o[k] = v end
  for k, v in pairs(cfg) do o[k] = v end
  -- actions se mezcla por direccion para poder cambiar solo una
  o.actions = {}
  for k, v in pairs(M.DEFAULTS.actions) do o.actions[k] = v end
  if cfg.actions then
    for k, v in pairs(cfg.actions) do o.actions[k] = v end
  end

  o.facing = o.start_facing
  o.moving = false
  o.cam_state = {}
  o.prev_tag = nil
  o.prev_frame = nil
  o.stride_acc = 0
  o.foot = "left"
  if o.footsteps and o.footsteps.frames then
    o.frame_set = {}
    for _, f in ipairs(o.footsteps.frames) do o.frame_set[f] = true end
  end
  return setmetatable(o, Walker)
end

function Walker:get_facing() return self.facing end
function Walker:set_facing(dir) self.facing = dir end
function Walker:is_moving() return self.moving end

-- Dispara el paso y alterna el pie
function Walker:emit_footstep(entity)
  local foot = self.foot
  self.foot = (foot == "left") and "right" or "left"
  local cb = self.footsteps.on_footstep
  if cb then cb(entity, foot) end
end

function Walker:update_footsteps(entity, tag, speed, dt)
  if not self.moving then
    self.prev_frame = nil
    self.stride_acc = 0
    return
  end

  local frame = nil
  if self.frame_set and get_animation_frame then
    frame = get_animation_frame(entity)
  end

  if frame and frame >= 0 then
    -- Al cambiar de tag (o al empezar a andar) se toma el frame actual como
    -- referencia: el frame 0 no debe disparar un paso falso
    if self.prev_frame == nil or tag ~= self.prev_tag then
      self.prev_frame = frame
    else
      if math2.crossed_frame(self.prev_frame, frame, self.frame_set) then
        self:emit_footstep(entity)
      end
      self.prev_frame = frame
    end
  else
    -- Sin consulta de frame: un paso cada `stride` px recorridos
    local stride = self.footsteps.stride or 14
    self.stride_acc = self.stride_acc + speed * dt
    if self.stride_acc >= stride then
      self.stride_acc = self.stride_acc - stride
      self:emit_footstep(entity)
    end
  end
end

function Walker:update_camera(entity, dt)
  local cam = self.camera
  if not cam or cam.follow == false then return end

  local px, py = get_position(entity)
  local box = cam.box or { x = 0, y = 0, w = 0, h = 0 }
  local tx = px + box.x + box.w / 2
  local ty = py + box.y + box.h / 2

  local bounds = cam.bounds
  if not bounds and get_tile_map_size then
    local mw, mh = get_tile_map_size()
    if mw and mw > 0 and mh and mh > 0 then bounds = { x = 0, y = 0, w = mw, h = mh } end
  end

  local sw, sh = get_screen_size()
  local x, y = math2.camera_step(self.cam_state, tx, ty, cam, sw, sh, bounds, dt)
  -- Si aparece temblor de subpixel con pixel_perfect: floor(x + 0.5) antes de enviar
  set_camera_position(x, y)
end

function Walker:step(entity)
  -- Un frame largo (carga, pausa) no debe disparar la fisica
  local dt = math.min(get_delta_time(), 0.05)

  -- 1. Input
  local dx, dy, run
  if type(self.input) == "function" then
    dx, dy, run = self.input(entity, dt)
    dx, dy = dx or 0, dy or 0
  else
    dx, dy, run = read_keyboard(self.actions)
  end
  dx, dy = math2.normalize_input(dx, dy)

  -- 2. Velocidad (el mover de BoxCollider barre y desliza; nunca set_position)
  local speed = run and self.run_speed or self.walk_speed
  local vx, vy = get_velocity(entity)
  vx, vy = math2.step_velocity(vx, vy, dx, dy, speed, self.accel_time, self.decel_time, dt)
  set_velocity(entity, vx, vy)

  -- 3. Facing e "is moving"
  self.facing = math2.pick_facing(dx, dy, self.facing)
  local has_input = dx ~= 0 or dy ~= 0
  local cur_speed = math.sqrt(vx * vx + vy * vy)
  self.moving = has_input and cur_speed >= self.min_move_speed

  -- 4. Animacion: play_animation es no-op si el tag ya esta en bucle
  local kind
  if self.moving then
    kind = (run and self.run_kind) or self.walk_kind
  else
    kind = self.idle_kind
  end
  local dir = self.facing
  if self.mirror_left then
    set_sprite_flip(entity, dir == "left")
    if dir == "left" then dir = "right" end
  end
  local tag = math2.anim_tag(self.tag_prefix, kind, dir)
  play_animation(entity, tag)

  -- 5. Pasos
  if self.footsteps then
    self:update_footsteps(entity, tag, cur_speed, dt)
  end
  self.prev_tag = tag

  -- 6. Camara
  self:update_camera(entity, dt)
end

-- El motor fija el global `this` antes de cada llamada: se lee al ejecutar el
-- closure, no al crearlo
-- Devuelve el closure y, como segundo valor, el objeto walker (para leer o
-- cambiar el facing desde fuera, p. ej. al teletransportar). Los llamadores que
-- solo asignan `update = make_update(cfg)` ignoran el segundo valor.
function M.make_update(cfg)
  local obj = M.new(cfg)
  return function()
    obj:step(this)
  end, obj
end

return M
