-- Sprite de cada pickup segun el item que lleva. Lo que no este aqui usa
-- "mineral" (el unico sprite de minerales cargado hoy en la escena)
local PICKUP_SPRITES = {}
local DEFAULT_PICKUP_SPRITE = "mineral"

-- Separacion entre pickups cuando el asteroide suelta varios items distintos
local PICKUP_SPREAD = 20

-- Iman de los pickups (estilo XP de Minecraft): dentro del radio vuelan hacia
-- la nave, mas rapido cuanto mas cerca. MAX tiene que superar la max_speed
-- del jugador o la nave los deja atras.
local MAGNET_RADIUS = 200
local MAGNET_MIN_SPEED = 150
local MAGNET_MAX_SPEED = 600

-- position es la esquina sup-izq, no el centro: sprite de la nave 430x650 a
-- scale 0.2 (ver scene_01.lua) y pickup de 16x16 a scale 1
local PLAYER_CENTER_X, PLAYER_CENTER_Y = 43, 65
local PICKUP_HALF = 8

function update()
end

-- Los hooks llevan nombre propio (asteroid_on_*) ademas de on_damage /
-- on_death: SceneLoader limpia esos dos globals antes de cargar cada script,
-- y los asteroides creados en runtime (asteroid_spawner.lua) los enganchan
-- con set_on_damage / set_on_death usando estos nombres estables.
function asteroid_on_damage(amount, source)
  print(string.format("[asteroid] -%d HP (quedan %d)", amount, get_health(this)))
end

-- Suelta un pickup por cada item del loot del asteroide (definido en la
-- escena o el spawner, ver ASTEROID_TYPES en asteroid_config.lua). Sin loot
-- no suelta nada.
function asteroid_on_death()
  local x, y = get_position(this)
  local count = get_loot_count(this)

  for i = 1, count do
    local name, quantity = get_loot_at(this, i)
    local offset = (i - (count + 1) / 2) * PICKUP_SPREAD

    local pickup = create_entity()
    add_transform(pickup, x + offset, y, 1, 1, 0)
    add_sprite(pickup, PICKUP_SPRITES[name] or DEFAULT_PICKUP_SPRITE, 16, 16, 0, 0)
    add_rigid_body(pickup, 0, 0, 0, 0, 0)
    add_circle_collider(pickup, 8, 16, 16)
    set_loot(pickup, name, quantity)
    -- add_script antes que set_on_collision: add_script recrea el
    -- ScriptComponent y borraria el hook de colision ya puesto
    add_script(pickup, pickup_magnet)
    -- collect_pickup y no on_collision: este mismo archivo es el script de
    -- todos los asteroides, y set_on_collision solo afecta a esta entidad
    -- puntual (el pickup), no a los asteroides que lo cargan
    set_on_collision(pickup, collect_pickup)
  end
end

-- Desaparece sin soltar loot: vacia el loot antes de destruir para que
-- asteroid_on_death no deje pickups. Se copia primero porque set_loot
-- modifica la lista mientras se recorre
function asteroid_vanish(e)
  local names = {}
  for i = 1, get_loot_count(e) do
    names[#names + 1] = get_loot_at(e, i)
  end
  for _, name in ipairs(names) do
    set_loot(e, name, 0)
  end
  destroy_entity(e)
end

-- Un planeta (fuente de gravedad) se traga al asteroide que lo toca
function asteroid_on_collision(other)
  if is_gravity_source(other) then
    asteroid_vanish(this)
  end
end

on_damage = asteroid_on_damage
on_death = asteroid_on_death
on_collision = asteroid_on_collision

-- Update de cada pickup ("this" es el pickup). Fuera del radio se queda
-- quieto; dentro acelera hacia el centro de la nave hasta tocarla, y ahi
-- collect_pickup hace el resto.
function pickup_magnet()
  -- Mismo guard que enemy.lua: el jugador aun no corrio su primer frame
  if player_entity == nil or not is_alive(player_entity) then return end

  -- Con la bodega llena no atrae: el pickup no se podria recoger y se
  -- quedaria pegado a la nave
  local capacity = get_inventory_capacity(player_entity)
  if capacity > 0 and get_inventory_total(player_entity) >= capacity then
    set_velocity(this, 0, 0)
    return
  end

  local x, y = get_position(this)
  local px, py = get_position(player_entity)
  local dx = (px + PLAYER_CENTER_X) - (x + PICKUP_HALF)
  local dy = (py + PLAYER_CENTER_Y) - (y + PICKUP_HALF)
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

-- Pasa el loot del pickup al inventario de quien choco (balas y asteroides
-- no tienen inventario y lo atraviesan). "this" aqui es el pickup, porque el
-- hook lo puso el pickup con set_on_collision.
function collect_pickup(other)
  if not has_inventory(other) then return end

  -- se copia antes porque set_loot modifica la lista mientras se recorre
  local items = {}
  for i = 1, get_loot_count(this) do
    local name, quantity = get_loot_at(this, i)
    items[#items + 1] = { name = name, quantity = quantity }
  end

  for _, item in ipairs(items) do
    local added = add_item(other, item.name, item.quantity)
    set_loot(this, item.name, item.quantity - added)
  end

  -- si la bodega esta llena, lo que no entro se queda flotando
  if get_loot_count(this) == 0 then destroy_entity(this) end
end
