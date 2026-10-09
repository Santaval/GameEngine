-- Prefab de un asteroide (ver docs/lua-api.md, seccion Network). Se arma solo
-- con el estado de spawn, asi que cualquier cliente (incluido uno que entra
-- tarde via snapshot) lo reconstruye igual. pos/vel/rot/hp del estado
-- sobreescriben transform, rigid_body y health.
-- state: kind (indice en ASTEROID_TYPES), scale, world, y opcionalmente
--   despawn_far (el duenio lo borra al salir del mapa),
--   ttl (segundos de vida: el duenio la borra al cumplirse, ver asteroid.lua),
--   wreck (indice en WRECK_TYPES: pecio en vez de roca normal, ver
--   asteroid_config.lua), drift (lleva estela de polvo, ver asteroid.lua) y
--   ring = {x, y, radius, speed} + slot (roca del anillo de Saturno).
local cfg = require("asteroid_config")

return function(state)
  state = state or {}
  local sheet = cfg.ASTEROID_SHEET
  local frameSize = sheet.frameSize
  local asteroidType = cfg.ASTEROID_TYPES[state.kind or 1] or cfg.ASTEROID_TYPES[1]
  local scale = state.scale or 1
  local wreck = state.wreck and cfg.WRECK_TYPES[state.wreck]
  local health = cfg.healthFor(asteroidType, scale)
  if wreck then health = math.max(1, math.floor(health * wreck.healthMul + 0.5)) end

  local components = {
    transform = {
      position = { x = 0, y = 0 },
      scale = { x = scale, y = scale },
      rotation = 0,
    },
    rigid_body = {
      velocity = { x = 0, y = 0 },
    },
    sprite = {
      assetId = wreck and wreck.assetId or sheet.assetId,
      width = frameSize,
      height = frameSize,
      -- El pecio siempre usa el frame 0 (entero)
      src_rect = { x = wreck and 0 or asteroidType.frame * frameSize, y = 0 },
      rotation = 0,
    },
    circle_collider = {
      radius = wreck and cfg.WRECK_SHEET.bodyRadius or sheet.bodyRadius,
      width = frameSize,
      heigth = frameSize,
    },
    health = {
      max = health,
      invulnerability = cfg.ASTEROID_INVULNERABILITY,
    },
    -- El asteroide sobrevive al choque (sin destroy_on_hit): el que tiene
    -- que preocuparse es quien se lo lleve por delante
    damage = {
      amount = cfg.ASTEROID_DAMAGE,
      min_impact_speed = cfg.IMPACT_MIN_SPEED,
      full_impact_speed = cfg.IMPACT_FULL_SPEED,
    },
    loot = asteroidType.loot,
    script = {
      path = "./assets/scripts/asteroid.lua",
    },
    -- Sin animation: el AnimationSystem sobrescribe src_rect.x y se perderia
    -- la variante elegida (ademas los frames 4-8 son la explosion).
  }

  -- Roca de un chunk del mapa: se duerme fuera del area activa (set_active_area)
  if state.cull then
    components.cull = true
  end

  -- Las rocas del anillo no sienten la gravedad: giran de forma cinematica
  if not state.ring then
    components.gravity = {
      mass = scale * cfg.GRAVITY.ASTEROID_MASS_PER_SCALE,
      attracts = false,
      affected = true,
    }
  end

  return { components = components }
end
