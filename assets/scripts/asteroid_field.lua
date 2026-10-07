-- =====================================================================
--  Constructores de entidades para las escenas (tablas del SceneLoader):
--  asteroides, planetas y el reparto de un campo sin solapamientos.
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

-- Asteroide centrado en (cx, cy). velocity(cx, cy) devuelve vx, vy; se llama
-- despues de elegir el tipo para no alterar la secuencia del random (mismo
-- campo con la misma semilla)
function field.make_asteroid(cx, cy, scale, velocity)
  local frameSize = ASTEROID_SHEET.frameSize
  local drawSize = frameSize * scale
  local asteroidType = cfg.pickAsteroidType()
  local frame = asteroidType.frame
  local vx, vy = velocity(cx, cy)

  return {
    components = {
      -- transform.position es la esquina superior izquierda del sprite,
      -- asi que se descuenta medio frame para centrar la roca en (cx, cy)
      transform = {
        position = { x = cx - drawSize / 2, y = cy - drawSize / 2 },
        scale = { x = scale, y = scale },
        rotation = randRange(0, 2 * math.pi),
      },
      rigid_body = {
        velocity = { x = vx, y = vy },
      },
      sprite = {
        assetId = ASTEROID_SHEET.assetId,
        width = frameSize,
        height = frameSize,
        src_rect = { x = frame * frameSize, y = 0 },
        rotation = 0,
      },
      circle_collider = {
        radius = ASTEROID_SHEET.bodyRadius,
        width = frameSize,
        heigth = frameSize,
      },
      health = {
        max = cfg.healthFor(asteroidType, scale),
        invulnerability = cfg.ASTEROID_INVULNERABILITY,
      },
      -- El asteroide sobrevive al choque (sin destroy_on_hit): el que tiene
      -- que preocuparse es quien se lo lleve por delante
      damage = {
        amount = cfg.ASTEROID_DAMAGE,
      },
      gravity = {
        mass = scale * cfg.GRAVITY.ASTEROID_MASS_PER_SCALE,
        attracts = false,
        affected = true,
      },
      loot = asteroidType.loot,
      script = {
        path = "./assets/scripts/asteroid.lua"
      }
      -- Sin animation: el AnimationSystem sobrescribe src_rect.x y se perderia
      -- la variante elegida (ademas los frames 4-8 son la explosion).
    },
  }
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
