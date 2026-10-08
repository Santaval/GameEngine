local player_movement_module = require("player_movement")

local player_gravity_zones_module = {}

-- Copia de las constantes de GravitySystem.hpp: si cambian alla, cambiarlas aca
local G = 1000
local SOFTENING = 40

-- Gravedad / empuje a partir de la cual se avisa: con 1 ya no hay retorno
local WARNING_RATIO = 0.6

-- Dano por tocar la superficie de un planeta, como mucho una vez por intervalo
local PLANET_DAMAGE_INTERVAL = 0.5

-- Anillos punteados: no hay primitiva de circulo, se dibujan con cuadraditos
-- con al menos RING_MIN_DOTS puntos y uno cada RING_DOT_SPACING px, para que
-- el anillo del range (mucho mas grande) no quede ralo
local RING_MIN_DOTS = 64
local RING_DOT_SPACING = 30
local RING_DOT_SIZE = 4
-- El anillo del range se ve desde antes de entrar: hasta este factor del range
local OUTER_RING_VISIBLE_FACTOR = 1.5

player_gravity_zones_module.COLORS = {
  safe = { 120, 255, 120 },
  warning = { 255, 220, 60 },
  no_return = { 255, 60, 60 },
}

local LABELS = {
  safe = "Gravedad: segura",
  warning = "Gravedad: PELIGRO",
  no_return = "SIN RETORNO",
}

-- Reloj del modulo (avanza en draw, que corre cada frame) para el dano
local clock = 0
local last_planet_hit = -math.huge

-- Aceleracion de la gravedad del planeta a distancia r, igual que GravitySystem:
-- a = G*M*r / (r^2 + s^2)^(3/2), y nada fuera del range
function player_gravity_zones_module.gravity_accel(planet, r)
  if planet.range > 0 and r > planet.range then return 0 end
  local denom = r * r + SOFTENING * SOFTENING
  return G * planet.mass * r / (denom * math.sqrt(denom))
end

-- Mayor radio en el que la gravedad llega a `accel`, o 0 si nunca tira tanto.
-- Desde SOFTENING hacia afuera a(r) solo decrece, asi que alcanza con biseccion
function player_gravity_zones_module.radius_for_accel(planet, accel)
  local accel_at = player_gravity_zones_module.gravity_accel
  local lo, hi = SOFTENING, planet.range
  if accel_at(planet, lo) < accel then return 0 end
  if accel_at(planet, hi) >= accel then return hi end
  for _ = 1, 30 do
    local mid = (lo + hi) / 2
    if accel_at(planet, mid) >= accel then lo = mid else hi = mid end
  end
  return lo
end

-- Radio donde empieza cada zona con el empuje actual de la nave
function player_gravity_zones_module.zone_radii(planet)
  local thrust = player_movement_module.thrust
  local radius_for = player_gravity_zones_module.radius_for_accel
  return radius_for(planet, thrust * WARNING_RATIO), radius_for(planet, thrust)
end

function player_gravity_zones_module.distance_to(entity, planet)
  local cx, cy = get_collider_center(entity)
  local dx, dy = cx - planet.x, cy - planet.y
  return math.sqrt(dx * dx + dy * dy), dx, dy
end

-- "safe", "warning" o "no_return" segun cuanto del empuje se come la gravedad
function player_gravity_zones_module.zone_at(entity, planet)
  local r = player_gravity_zones_module.distance_to(entity, planet)
  local ratio = player_gravity_zones_module.gravity_accel(planet, r) / player_movement_module.thrust
  if ratio >= 1 then return "no_return", r end
  if ratio >= WARNING_RATIO then return "warning", r end
  return "safe", r
end

-- El planeta mas cercano dentro de range_factor * range, o nil
function player_gravity_zones_module.nearest_planet(entity, range_factor)
  if scene_planets == nil then return nil end

  local best, best_dist = nil, math.huge
  for _, p in ipairs(scene_planets) do
    local dist = player_gravity_zones_module.distance_to(entity, p)
    if dist < p.range * range_factor and dist < best_dist then
      best, best_dist = p, dist
    end
  end
  return best
end

-- Anillo punteado de radio `radius` alrededor de center = {x, y}. alpha,
-- spacing y offset (rad, para animarlo) son opcionales. Lo reusa saturn_ring.lua
function player_gravity_zones_module.draw_ring(center, radius, color, alpha, spacing, offset)
  if radius <= 0 then return end
  local half = RING_DOT_SIZE / 2
  local dots = math.max(RING_MIN_DOTS, math.floor(2 * math.pi * radius / (spacing or RING_DOT_SPACING)))
  offset = offset or 0
  for i = 0, dots - 1 do
    local angle = offset + i * 2 * math.pi / dots
    draw_rect_world(center.x + radius * math.cos(angle) - half, center.y + radius * math.sin(angle) - half,
      RING_DOT_SIZE, RING_DOT_SIZE, color[1], color[2], color[3], alpha or 160)
  end
end
local draw_ring = player_gravity_zones_module.draw_ring

-- Anillo verde en el borde de la gravedad (range) de los planetas cercanos;
-- anillos de aviso y sin retorno del planeta cuya gravedad alcanza a la nave,
-- y la zona actual en el HUD
function player_gravity_zones_module.draw(entity)
  clock = clock + get_delta_time()

  local colors = player_gravity_zones_module.COLORS
  for _, p in ipairs(scene_planets or {}) do
    if p.range > 0 and player_gravity_zones_module.distance_to(entity, p) < p.range * OUTER_RING_VISIBLE_FACTOR then
      draw_ring(p, p.range, colors.safe)
    end
  end

  local planet = player_gravity_zones_module.nearest_planet(entity, 1)
  if planet == nil then return end

  local warning_r, no_return_r = player_gravity_zones_module.zone_radii(planet)
  draw_ring(planet, warning_r, colors.warning)
  draw_ring(planet, no_return_r, colors.no_return)

  local zone = player_gravity_zones_module.zone_at(entity, planet)
  local color = colors[zone]
  local w, h = get_screen_size()
  draw_text(w / 2 - 80, h - 70, LABELS[zone], "default", color[1], color[2], color[3])
end

-- Tocar un planeta quita vida. on_collision llega cada frame mientras se
-- solapan, asi que se limita a un golpe por intervalo
function player_gravity_zones_module.on_collision(entity, other)
  if not is_gravity_source(other) then return end
  if clock - last_planet_hit < PLANET_DAMAGE_INTERVAL then return end

  -- La entidad no dice que planeta es: el mas cercano es el que se toca
  local planet = player_gravity_zones_module.nearest_planet(entity, 1)
  if planet == nil or (planet.damage or 0) <= 0 then return end

  last_planet_hit = clock
  -- En multijugador set_health solo funciona en el dueño de la nave (aqui lo es)
  set_health(entity, get_health(entity) - planet.damage)
  print(string.format("[player] -%d HP por chocar contra un planeta (quedan %d)", planet.damage, get_health(entity)))
end

return player_gravity_zones_module
