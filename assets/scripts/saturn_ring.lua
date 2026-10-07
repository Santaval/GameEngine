-- =====================================================================
--  Anillo de Saturno
--  Script de una entidad "director" invisible. En su primer update crea las
--  rocas del anillo en runtime (igual que asteroid_spawner.lua) y cada roca
--  sigue su propio lugar ("slot") en una formacion que gira alrededor de
--  Saturno. Las rocas no sienten la gravedad: el giro es cinematico, por
--  velocidad, asi que tras un rebote contra la nave vuelven a su lugar.
--  Se rompen a tiros y sueltan loot como cualquier asteroide; el hueco se
--  vuelve a llenar despues de un rato, siempre fuera de la pantalla.
-- =====================================================================

local cfg = require("asteroid_config")
local solar = require("solar_system_config")
local zones = require("player_gravity_zones")
local randRange = cfg.randRange
local RING = solar.SATURN_RING

-- Carriles concentricos del anillo y desvio aleatorio dentro de cada uno
local LANES = 3
local LANE_JITTER = 8
-- Desvio angular aleatorio de cada roca respecto de su lugar parejo (rad)
local ANGLE_JITTER = 0.05

-- Correccion hacia el lugar de la roca: px/s de velocidad por px de error
local POSITION_GAIN = 1.5
-- Que tan rapido la velocidad real converge a la deseada (1/s). Bajo, para
-- que el rebote contra la nave se note antes de volver a la formacion
local STEER_RATE = 2

-- Banda punteada que marca el anillo
local BAND_COLOR = { 210, 190, 150 }
local BAND_ALPHA = 70
local BAND_DOT_SPACING = 16

-- Margen de pantalla para no hacer aparecer rocas a la vista
local SCREEN_MARGIN = 150

-- ---------------------------------------------------------------------
--  Estado (locals del archivo: las closures lo mantienen entre frames)
-- ---------------------------------------------------------------------

local planet = nil
local inner_r, outer_r = 0, 0
local slots = nil
local clock = 0

local function isOnScreen(x, y)
  local camX, camY = get_camera_position()
  local w, h = get_screen_size()
  return x > camX - SCREEN_MARGIN and x < camX + w + SCREEN_MARGIN
     and y > camY - SCREEN_MARGIN and y < camY + h + SCREEN_MARGIN
end

-- Posicion del lugar de la roca en este momento
local function slotPoint(slot)
  local a = slot.angle + RING.angular_speed * clock
  return planet.x + slot.radius * math.cos(a), planet.y + slot.radius * math.sin(a), a
end

local function buildSlots()
  local list = {}
  local per_lane = math.floor(RING.rocks / LANES + 0.5)
  local lane_width = (outer_r - inner_r) / LANES

  for lane = 1, LANES do
    local base_r = inner_r + lane_width * (lane - 0.5)
    -- Cada carril arranca corrido para que las rocas no queden alineadas
    local lane_offset = lane * 0.37
    for i = 1, per_lane do
      list[#list + 1] = {
        radius = base_r + randRange(-LANE_JITTER, LANE_JITTER),
        angle = lane_offset + (i - 1) * 2 * math.pi / per_lane + randRange(-ANGLE_JITTER, ANGLE_JITTER),
        alive = false,
        dead_at = -math.huge,
      }
    end
  end

  return list
end

local function spawnRock(slot)
  local sheet = cfg.ASTEROID_SHEET
  local frameSize = sheet.frameSize
  local scale = randRange(RING.scale.min, RING.scale.max)
  local half = frameSize * scale / 2
  local asteroidType = cfg.pickAsteroidType()
  local cx, cy = slotPoint(slot)

  local e = create_entity()
  -- position es la esquina sup-izq: se descuenta medio frame para centrar
  add_transform(e, cx - half, cy - half, scale, scale, randRange(0, 2 * math.pi))
  add_rigid_body(e, 0, 0, 0, 0)
  add_sprite(e, sheet.assetId, frameSize, frameSize, asteroidType.frame * frameSize, 0)
  add_circle_collider(e, sheet.bodyRadius, frameSize, frameSize)
  add_health(e, cfg.healthFor(asteroidType, scale), cfg.ASTEROID_INVULNERABILITY)
  add_damage(e, cfg.ASTEROID_DAMAGE)
  for name, quantity in pairs(asteroidType.loot) do
    set_loot(e, name, quantity)
  end

  -- on_death puede llegar dos veces (kill() es diferido), igual que en
  -- asteroid_spawner.lua: la bandera evita liberar el lugar dos veces
  local dead = false

  -- add_script primero: recrea el ScriptComponent y borraria los hooks
  add_script(e, function()
    if dead then return end
    local tx, ty, a = slotPoint(slot)
    local x, y = get_collider_center(this)

    -- Velocidad de la formacion (tangente) + correccion hacia el lugar
    local v_t = RING.angular_speed * slot.radius
    local want_x = -math.sin(a) * v_t + (tx - x) * POSITION_GAIN
    local want_y = math.cos(a) * v_t + (ty - y) * POSITION_GAIN

    local vx, vy = get_velocity(this)
    local k = math.min(1, STEER_RATE * get_delta_time())
    set_velocity(this, vx + (want_x - vx) * k, vy + (want_y - vy) * k)
  end)
  set_on_damage(e, asteroid_on_damage)
  set_on_collision(e, asteroid_on_collision)
  set_on_death(e, function()
    if dead then return end
    dead = true
    slot.alive = false
    slot.dead_at = clock
    asteroid_on_death()
  end)

  slot.alive = true
end

local function drawBand()
  local camX, camY = get_camera_position()
  local w, h = get_screen_size()
  local dx, dy = camX + w / 2 - planet.x, camY + h / 2 - planet.y
  local reach = outer_r + math.sqrt(w * w + h * h) / 2
  if dx * dx + dy * dy > reach * reach then return end

  local offset = RING.angular_speed * clock
  zones.draw_ring(planet, inner_r, BAND_COLOR, BAND_ALPHA, BAND_DOT_SPACING, offset)
  zones.draw_ring(planet, (inner_r + outer_r) / 2, BAND_COLOR, BAND_ALPHA / 2, BAND_DOT_SPACING * 2, offset)
  zones.draw_ring(planet, outer_r, BAND_COLOR, BAND_ALPHA, BAND_DOT_SPACING, offset)
end

function update()
  if slots == nil then
    planet = solar.find_planet(scene_planets or {}, RING.planet)
    if planet == nil then
      print("[saturn_ring] no hay planeta " .. RING.planet .. " en scene_planets")
      slots = {}
      return
    end
    -- Los hooks asteroid_on_* viven en asteroid.lua; normalmente ya lo cargo
    -- la escena con los asteroides de los cinturones
    if asteroid_on_death == nil then require("asteroid") end

    inner_r = planet.body_radius * RING.inner
    outer_r = planet.body_radius * RING.outer
    slots = buildSlots()
    for _, slot in ipairs(slots) do spawnRock(slot) end
  end

  if planet == nil then return end
  clock = clock + get_delta_time()

  for _, slot in ipairs(slots) do
    if not slot.alive and clock - slot.dead_at >= RING.respawn_time then
      local x, y = slotPoint(slot)
      if not isOnScreen(x, y) then spawnRock(slot) end
    end
  end

  drawBand()
end
