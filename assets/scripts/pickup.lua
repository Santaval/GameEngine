-- =====================================================================
--  Script de runtime de cada pickup (prefabs/pickup.lua). Cada cliente corre
--  el iman con su copia, hacia su propia nave; el reparto del loot lo decide
--  el duenio del pickup (ver loot_net.lua).
-- =====================================================================

local loot_net = require("loot_net")
local D = require("map_config").DEATH_DROP

-- Iman de los pickups (estilo XP de Minecraft): dentro del radio vuelan hacia
-- la nave, mas rapido cuanto mas cerca. MAX tiene que superar la max_speed
-- del jugador o la nave los deja atras.
local MAGNET_RADIUS = 300
local MAGNET_MIN_SPEED = 150
local MAGNET_MAX_SPEED = 600

-- position es la esquina sup-izq, no el centro: sprite de la nave 430x650 a
-- scale 0.2 (ver scene_01.lua) y orbe de PICKUP_SIZE de ancho (prefabs/pickup.lua)
local PLAYER_CENTER_X, PLAYER_CENTER_Y = 43, 65
local PICKUP_SIZE = 32
local PICKUP_HALF_X = PICKUP_SIZE / 2
local PICKUP_HALF_Y = PICKUP_SIZE * D.frame_h / D.frame_w / 2

-- Segundos entre un pickup_request y el siguiente de este pickup: si el duenio
-- cambio justo en ese momento y la peticion se perdio, se reintenta
local REQUEST_INTERVAL = 1

-- Datos por entidad (el chunk corre una vez por pickup)
local clock = 0
local last_request = -math.huge

-- Con la bodega llena el pickup no se puede recoger
local function hold_has_room()
  local capacity = get_inventory_capacity(player_entity)
  return capacity <= 0 or get_inventory_total(player_entity) < capacity
end

-- Update de cada pickup ("this" es el pickup). Fuera del radio se queda
-- quieto; dentro acelera hacia el centro de la nave hasta tocarla, y ahi
-- on_collision hace el resto.
function update()
  clock = clock + get_delta_time()

  -- Mismo guard que enemy.lua: el jugador aun no corrio su primer frame
  if player_entity == nil or not is_alive(player_entity) then return end

  -- Con la bodega llena no atrae: el pickup no se podria recoger y se
  -- quedaria pegado a la nave
  if not hold_has_room() then
    set_velocity(this, 0, 0)
    return
  end

  local x, y = get_position(this)
  local px, py = get_position(player_entity)
  local dx = (px + PLAYER_CENTER_X) - (x + PICKUP_HALF_X)
  local dy = (py + PLAYER_CENTER_Y) - (y + PICKUP_HALF_Y)
  local d = math.sqrt(dx * dx + dy * dy)

  if d > MAGNET_RADIUS or d < 0.001 then
    set_velocity(this, 0, 0)
    return
  end

  -- t va de 0 (borde del radio) a 1 (encima de la nave); al cuadrado para
  -- que arranque suave y de el "tiron" al final
  local t = 1 - d / MAGNET_RADIUS
  local speed = MAGNET_MIN_SPEED + (MAGNET_MAX_SPEED - MAGNET_MIN_SPEED) * t * t
  set_velocity(this, dx / d * speed, dy / d * speed)
end

-- Solo recoge la nave local (balas y asteroides no tienen inventario y lo
-- atraviesan; las naves remotas recogen en su propio cliente). Si el pickup
-- es mio se lo entrego a mi nave; si no, se lo pido al duenio
function on_collision(other)
  if not has_inventory(other) or not is_local(other) then return end
  if not hold_has_room() then return end

  if is_local(this) then
    loot_net.grant(this, net_my_id())
  elseif clock - last_request >= REQUEST_INTERVAL then
    last_request = clock
    net_send("pickup_request", { lootNetId = get_net_id(this) }, get_owner(this))
  end
end
