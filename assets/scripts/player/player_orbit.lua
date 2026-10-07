local player_movement_module = require("player_movement")
local zones = require("player_gravity_zones")

local player_orbit_module = {}

-- Fraccion del range del planeta dentro de la cual se puede entrar en orbita
local CAPTURE_RANGE_FACTOR = 0.6
-- Distancia minima sobre la superficie del planeta para orbitar
local MIN_ALTITUDE = 40
-- La orbita usa como mucho esta fraccion de max_speed: el resto queda para
-- corregir el radio
local ORBIT_SPEED_FRACTION = 0.95
-- Correccion radial: px/s de velocidad por px de error de radio
local RADIAL_GAIN = 2
-- Cuanto dura el aviso de "demasiado cerca" (s)
local REFUSED_MESSAGE_TIME = 2

-- Estado del modulo: persiste entre frames, se reinicia al cargar la escena
local orbit_planet = nil
local orbit_radius = 0
local orbit_dir = 1
local key_was_down = false
local refused_timer = 0

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- Radio mas bajo con orbita circular por debajo del tope de velocidad. Fuera de
-- SOFTENING la velocidad orbital solo decrece con r, asi que alcanza con biseccion
local function min_orbit_radius(planet, max_speed)
  local limit = max_speed * ORBIT_SPEED_FRACTION
  local lo, hi = planet.body_radius + MIN_ALTITUDE, planet.range * CAPTURE_RANGE_FACTOR
  if zones.circular_speed(planet, lo) <= limit then return lo end
  if zones.circular_speed(planet, hi) > limit then return nil end
  for _ = 1, 30 do
    local mid = (lo + hi) / 2
    if zones.circular_speed(planet, mid) > limit then lo = mid else hi = mid end
  end
  return hi
end

-- Planeta en el que se puede entrar en orbita ahora, o nil. Fuera del alcance,
-- sin retorno, o sin radio orbital posible bajo el tope de velocidad: no
local function orbitable_planet(entity)
  local planet = zones.nearest_planet(entity, CAPTURE_RANGE_FACTOR)
  if planet == nil then return nil end
  if zones.zone_at(entity, planet) == "no_return" then return nil end
  if min_orbit_radius(planet, get_max_speed(entity)) == nil then return nil end
  return planet
end

local function enter_orbit(entity, planet)
  local r, dx, dy = zones.distance_to(entity, planet)
  orbit_planet = planet
  -- Desde la zona de aviso el piloto primero sube hasta un radio orbitable
  orbit_radius = math.max(r, min_orbit_radius(planet, get_max_speed(entity)))

  -- Sentido de giro segun la velocidad actual (cross(radial, velocidad)),
  -- para no dar media vuelta al entrar
  local vx, vy = get_velocity(entity)
  orbit_dir = (dx * vy - dy * vx) >= 0 and 1 or -1
end

local function update_orbit(entity)
  local r, dx, dy = zones.distance_to(entity, orbit_planet)
  if r < 0.001 then return end

  -- Una mejora de motor durante la orbita cambia el tope: el radio se ajusta
  local max_speed = get_max_speed(entity)
  local min_r = min_orbit_radius(orbit_planet, max_speed)
  if min_r ~= nil and min_r > orbit_radius then orbit_radius = min_r end

  -- n apunta hacia afuera, t es la tangente en el sentido de giro
  local nx, ny = dx / r, dy / r
  local tx, ty = -ny * orbit_dir, nx * orbit_dir

  -- El radio tiene prioridad: la tangencial se queda con lo que sobre del tope
  local v_r = RADIAL_GAIN * (orbit_radius - r)
  local v_t = zones.circular_speed(orbit_planet, r)
  if max_speed > 0 then
    v_r = clamp(v_r, -max_speed, max_speed)
    v_t = math.min(v_t, math.sqrt(max_speed * max_speed - v_r * v_r))
  end
  local target_x = tx * v_t + nx * v_r
  local target_y = ty * v_t + ny * v_r

  -- El piloto automatico no tiene mas motor que la nave: el cambio de
  -- velocidad por frame se limita al empuje. Por eso en la zona sin retorno
  -- tampoco puede salvarla
  local vx, vy = get_velocity(entity)
  local ddx, ddy = target_x - vx, target_y - vy
  local delta = math.sqrt(ddx * ddx + ddy * ddy)
  local max_delta = player_movement_module.thrust * get_delta_time()
  if delta > max_delta then
    ddx, ddy = ddx / delta * max_delta, ddy / delta * max_delta
  end
  set_velocity(entity, vx + ddx, vy + ddy)

  -- Sin empuje del jugador; la nariz sigue la tangente
  set_acceleration(entity, 0, 0)
  set_sprite(entity, "spaceship-idle")
  set_rotation_absolute(entity, math.atan(ty, tx) + player_movement_module.SPRITE_ROTATION_OFFSET)
end

function player_orbit_module.is_orbiting()
  return orbit_planet ~= nil
end

function player_orbit_module.update(entity)
  refused_timer = math.max(0, refused_timer - get_delta_time())

  local down = is_action_activated("orbit")
  local pressed = down and not key_was_down
  key_was_down = down

  if orbit_planet ~= nil then
    -- Acelerar devuelve el control, igual que volver a apretar la tecla
    if pressed or is_action_activated("accelerate") then
      orbit_planet = nil
    else
      update_orbit(entity)
    end
  elseif pressed then
    local planet = orbitable_planet(entity)
    if planet ~= nil then
      enter_orbit(entity, planet)
      update_orbit(entity)
    elseif zones.nearest_planet(entity, CAPTURE_RANGE_FACTOR) ~= nil then
      refused_timer = REFUSED_MESSAGE_TIME
    end
  end
end

function player_orbit_module.draw(entity)
  local w, h = get_screen_size()
  if orbit_planet ~= nil then
    draw_text(w / 2 - 90, h - 40, "ORBITA - F o W para salir", "default", 120, 220, 255)
  elseif refused_timer > 0 then
    draw_text(w / 2 - 110, h - 40, "Demasiado cerca para orbitar", "default", 255, 60, 60)
  elseif orbitable_planet(entity) ~= nil then
    draw_text(w / 2 - 70, h - 40, "F para orbitar", "default", 200, 200, 120)
  end
end

return player_orbit_module
