-- =====================================================================
--  Anillo de Saturno
--  Script de una entidad "director" invisible. Dibuja la banda en todos los
--  clientes; solo el host crea las rocas (net_spawn de asteroid.lua con
--  world = true y ring = {x, y, radius, speed}) y rellena los huecos. Cada
--  roca sigue su carril alrededor de Saturno (ver steer_in_lane en
--  asteroid.lua): el giro es cinematico, por velocidad, asi que tras un
--  rebote contra la nave vuelven a su carril. Las rocas no sienten la
--  gravedad. Se rompen a tiros y sueltan loot como cualquier asteroide; el
--  hueco se vuelve a llenar despues de un rato, siempre fuera de la pantalla.
--  Si el host se va, el nuevo host reconstruye sus lugares y rellena solo los
--  que de verdad estan vacios (ring_slots, que llena cada roca).
-- =====================================================================

local cfg = require("asteroid_config")
local field = require("asteroid_field")
local solar = require("solar_system_config")
local zones = require("player_gravity_zones")
local randRange = cfg.randRange
local RING = solar.SATURN_RING

-- Carriles concentricos del anillo y desvio aleatorio dentro de cada uno
local LANES = 3
local LANE_JITTER = 8
-- Desvio angular aleatorio de cada roca respecto de su lugar parejo (rad)
local ANGLE_JITTER = 0.05

-- Siembra de las rocas en red: rocas por segundo, para no pasar el limite
-- del relay (120 msg/s). Offline se crean todas de golpe
local SPAWN_RATE = 30

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
local spawn_budget = 0

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
        was_alive = false,
        dead_at = -math.huge,
      }
    end
  end

  return list
end

-- Un lugar esta ocupado si la roca que lo anoto en ring_slots sigue viva
local function slotOccupied(index)
  local id = ring_slots[index]
  if id == nil then return false end
  local e = find_by_net_id(id)
  return e ~= nil and is_alive(e)
end

local function spawnRock(index, slot)
  local scale = randRange(RING.scale.min, RING.scale.max)
  local cx, cy, a = slotPoint(slot)
  local v_t = RING.angular_speed * slot.radius

  local state = field.asteroid_state(cx, cy, scale, function()
    return -math.sin(a) * v_t, math.cos(a) * v_t
  end)
  state.ring = { x = planet.x, y = planet.y, radius = slot.radius, speed = RING.angular_speed }
  state.slot = index

  local e = net_spawn("asteroid.lua", state)
  -- Se anota ya y no en el primer update de la roca, para no duplicarla
  local id = e and get_net_id(e)
  if id then ring_slots[index] = id end
  slot.dead_at = -math.huge
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
  ring_slots = ring_slots or {}

  if planet == nil then
    if slots ~= nil then return end
    planet = solar.find_planet(scene_planets or {}, RING.planet)
    if planet == nil then
      print("[saturn_ring] no hay planeta " .. RING.planet .. " en scene_planets")
      slots = {}
      return
    end
    inner_r = planet.body_radius * RING.inner
    outer_r = planet.body_radius * RING.outer
  end

  clock = clock + get_delta_time()

  -- Solo el host crea y rellena. Los lugares se arman al primer frame como
  -- host (tambien tras migrar) y se rellenan solo los que estan vacios
  if net_is_host() then
    if slots == nil then slots = buildSlots() end

    local online = net_is_online()
    if online then spawn_budget = math.min(spawn_budget + get_delta_time() * SPAWN_RATE, SPAWN_RATE) end

    for index, slot in ipairs(slots) do
      if slotOccupied(index) then
        slot.was_alive = true
      else
        -- El hueco empieza a contar cuando se nota por primera vez vacio
        if slot.was_alive then
          slot.was_alive = false
          slot.dead_at = clock
        end
        local first = slot.dead_at == -math.huge
        local x, y = slotPoint(slot)
        if (first or clock - slot.dead_at >= RING.respawn_time)
            and (first or not isOnScreen(x, y))
            and (not online or spawn_budget >= 1) then
          if online then spawn_budget = spawn_budget - 1 end
          spawnRock(index, slot)
        end
      end
    end
  end

  drawBand()
end
