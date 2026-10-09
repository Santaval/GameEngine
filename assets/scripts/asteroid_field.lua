-- =====================================================================
--  Constructores para las escenas: el estado de spawn de los asteroides
--  (se crean con net_spawn, ver prefabs/asteroid.lua), los planetas (tablas
--  del SceneLoader) y el reparto de un campo sin solapamientos.
--  Lo usan scenes/scene_01.lua (campo rectangular) y
--  scenes/solar_system.lua (cinturones en anillo).
-- =====================================================================

local cfg = require("asteroid_config")
local ASTEROID_SHEET = cfg.ASTEROID_SHEET
local randRange = cfg.randRange

local field = {}

function field.distance(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

-- Samplers: devuelven un centro al azar para una roca de radio `radius`
function field.rect_sampler(rect)
  return function(radius)
    return randRange(rect.x + radius, rect.x + rect.width - radius),
           randRange(rect.y + radius, rect.y + rect.height - radius)
  end
end

-- Anillo alrededor de (cx, cy). El radio se elige con sqrt para que la
-- densidad sea pareja: sin eso el borde interno quedaria mas poblado
function field.annulus_sampler(cx, cy, inner, outer)
  return function(radius)
    local lo, hi = inner + radius, outer - radius
    local r = math.sqrt(randRange(lo * lo, hi * hi))
    local a = randRange(0, 2 * math.pi)
    return cx + r * math.cos(a), cy + r * math.sin(a)
  end
end

-- Devuelve cx, cy, scale, radius de un hueco libre, o nil si no lo encuentra.
-- opts: sampler, scale = {min, max}, packing = {minGap, tries}, safe_zone
function field.find_spot(placed, opts)
  for _ = 1, opts.packing.tries do
    local scale = randRange(opts.scale.min, opts.scale.max)
    local radius = ASTEROID_SHEET.bodyRadius * scale
    local cx, cy = opts.sampler(radius)

    local safe = opts.safe_zone
    local free = not (safe and field.distance(cx, cy, safe.x, safe.y) < safe.radius + radius)

    if free then
      for _, other in ipairs(placed) do
        if field.distance(cx, cy, other.x, other.y) < other.radius + radius + opts.packing.minGap then
          free = false
          break
        end
      end
    end

    if free then
      return cx, cy, scale, radius
    end
  end

  return nil
end

-- Estado de spawn de un asteroide centrado en (cx, cy), para
-- net_spawn("asteroid.lua", estado) (ver prefabs/asteroid.lua). velocity(cx, cy)
-- devuelve vx, vy; se llama despues de elegir el tipo para no alterar la
-- secuencia del random (mismo campo con la misma semilla). pos es la esquina
-- superior izquierda del sprite, asi que se descuenta medio frame para centrar
-- la roca. kind (opcional) fuerza el tipo (indice en ASTEROID_TYPES) en vez de
-- sortearlo, como hacen los fragmentos de una roca partida; sin kind el
-- orden de los random es el de siempre. world = true: lo posee el host y lo
-- simulan todos
function field.asteroid_state(cx, cy, scale, velocity, kind)
  local drawSize = ASTEROID_SHEET.frameSize * scale
  if kind == nil then
    local _, picked = cfg.pickAsteroidType()
    kind = picked
  end
  local vx, vy = velocity(cx, cy)

  return {
    pos = { x = cx - drawSize / 2, y = cy - drawSize / 2 },
    vel = { x = vx, y = vy },
    rot = randRange(0, 2 * math.pi),
    kind = kind,
    scale = scale,
    world = true,
  }
end

-- Crea en runtime (net_spawn) un asteroide a la deriva en (cx, cy) con
-- velocidad (vx, vy). Sin scale lo sortea en ASTEROID_SCALE; sin kind sortea
-- el tipo. Lo usan los generadores y la division de rocas grandes. Devuelve
-- la entidad. El duenio (host) lo borra al salir del mapa, ver asteroid.lua
function field.spawn_drifting(cx, cy, vx, vy, scale, kind)
  scale = scale or randRange(cfg.ASTEROID_SCALE.min, cfg.ASTEROID_SCALE.max)
  local state = field.asteroid_state(cx, cy, scale, function() return vx, vy end, kind)
  state.despawn_far = true

  local e = net_spawn("asteroid.lua", state)
  -- Se anota ya y no en su primer update, para que el tope MAX_ALIVE valga
  -- aunque varios generadores disparen en el mismo frame
  local id = e and get_net_id(e)
  if id and drifting_asteroids ~= nil then drifting_asteroids[id] = true end
  return e
end

-- Planeta: se ve, atrae y traga asteroides (collider). Sin rigid_body,
-- health ni script. p = {assetId, x, y, scale, mass, range} con (x, y) el centro
function field.make_planet(p, frame, body_radius)
  local size = frame * p.scale

  return {
    components = {
      -- transform.position es la esquina superior izquierda del sprite,
      -- asi que se descuenta medio tamano para centrar el planeta en (x, y)
      transform = {
        position = { x = p.x - size / 2, y = p.y - size / 2 },
        scale = { x = p.scale, y = p.scale },
        rotation = 0,
      },
      sprite = {
        assetId = p.assetId,
        width = frame,
        height = frame,
        src_rect = { x = 0, y = 0 },
        rotation = 0,
      },
      circle_collider = {
        radius = body_radius,
        width = frame,
        heigth = frame,
      },
      -- Fuente de gravedad fija: no es afectada (ni tiene rigid_body)
      gravity = {
        mass = p.mass,
        attracts = true,
        affected = false,
        range = p.range,
      },
    },
  }
end

return field
