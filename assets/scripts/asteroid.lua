-- Sprite de cada pickup segun el item que lleva. Lo que no este aqui usa
-- "mineral" (el unico sprite de minerales cargado hoy en la escena)
local PICKUP_SPRITES = {}
local DEFAULT_PICKUP_SPRITE = "mineral"

-- Separacion entre pickups cuando el asteroide suelta varios items distintos
local PICKUP_SPREAD = 20

function update()
end

function on_damage(amount, source)
  print(string.format("[asteroid] -%d HP (quedan %d)", amount, get_health(this)))
end

-- Suelta un pickup por cada item del loot del asteroide (definido en la
-- escena, ver ASTEROID_TYPES en scene_01.lua). Sin loot no suelta nada.
function on_death()
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
    -- collect_pickup y no on_collision: este mismo archivo es el script de
    -- todos los asteroides, y set_on_collision solo afecta a esta entidad
    -- puntual (el pickup), no a los asteroides que lo cargan
    set_on_collision(pickup, collect_pickup)
  end
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
