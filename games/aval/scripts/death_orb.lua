-- =====================================================================
--  Script de runtime de cada orbe de muerte (prefabs/death_orb.lua). Mismo
--  flujo que pickup.lua (iman hacia la nave local, reparto por loot_net.lua),
--  con dos diferencias: al nacer sale empujado hacia afuera y se frena en
--  push_time s, y su duenio lo borra al cumplirse ttl.
-- =====================================================================

local cfg = require("map_config")
local loot_net = require("loot_net")

local D = cfg.DEATH_DROP

-- Iman: dentro del radio vuelan hacia la nave, mas rapido cuanto mas cerca.
-- MAX tiene que superar la max_speed del jugador o la nave los deja atras.
local MAGNET_RADIUS = D.magnet_radius
local MAGNET_MIN_SPEED = 150
local MAGNET_MAX_SPEED = 600

-- position es la esquina sup-izq, no el centro: nave de 430x650 a scale 0.2
-- (ver scenes/aval_cup.lua) y orbe de D.size de ancho
local PLAYER_CENTER_X, PLAYER_CENTER_Y = 43, 65
local ORB_HALF_X = D.size / 2
local ORB_HALF_Y = D.size * D.frame_h / D.frame_w / 2

-- Segundos entre un pickup_request y el siguiente de este orbe: si el duenio
-- cambio justo en ese momento y la peticion se perdio, se reintenta
local REQUEST_INTERVAL = 1

-- Datos por entidad (el chunk corre una vez por orbe)
local clock = 0
local last_request = -math.huge
-- Velocidad de salida (la que trae el estado de spawn), se lee en el primer frame
local push_vx, push_vy = nil, nil

-- Con la bodega llena el orbe no se puede recoger
local function hold_has_room()
  local capacity = get_inventory_capacity(player_entity)
  return capacity <= 0 or get_inventory_total(player_entity) < capacity
end

-- Empuje de salida: baja linealmente de la velocidad inicial a 0 en push_time
local function drift()
  if push_vx == nil then push_vx, push_vy = get_velocity(this) end
  local k = 1 - clock / D.push_time
  if k <= 0 then
    set_velocity(this, 0, 0)
  else
    set_velocity(this, push_vx * k, push_vy * k)
  end
end

-- Update de cada orbe ("this" es el orbe)
function update()
  clock = clock + get_delta_time()

  -- Solo el duenio lo borra, en cuanto se cumple el ttl
  if clock >= D.ttl and is_local(this) then
    net_despawn(this)
    return
  end

  -- Mismo guard que pickup.lua: el jugador aun no corrio su primer frame
  if player_entity == nil or not is_alive(player_entity) then
    drift()
    return
  end

  -- Con la bodega llena no atrae: sigue su empuje y se queda quieto
  if not hold_has_room() then
    drift()
    return
  end

  local x, y = get_position(this)
  local px, py = get_position(player_entity)
  local dx = (px + PLAYER_CENTER_X) - (x + ORB_HALF_X)
  local dy = (py + PLAYER_CENTER_Y) - (y + ORB_HALF_Y)
  local d = math.sqrt(dx * dx + dy * dy)

  if d > MAGNET_RADIUS or d < 0.001 then
    drift()
    return
  end

  -- t va de 0 (borde del radio) a 1 (encima de la nave); al cuadrado para
  -- que arranque suave y de el "tiron" al final
  local t = 1 - d / MAGNET_RADIUS
  local speed = MAGNET_MIN_SPEED + (MAGNET_MAX_SPEED - MAGNET_MIN_SPEED) * t * t
  set_velocity(this, dx / d * speed, dy / d * speed)
end

-- Solo recoge la nave local (balas y asteroides no tienen inventario y lo
-- atraviesan; las naves remotas recogen en su propio cliente). Si el orbe es
-- mio se lo entrego a mi nave; si no, se lo pido al duenio
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
