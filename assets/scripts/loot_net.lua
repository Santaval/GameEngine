-- =====================================================================
--  Reparto del loot en red. El pickup es del host (o de quien lo suelto):
--  solo el duenio decide quien se lo lleva, asi el primero que lo pide gana
--  y el loot se entrega una sola vez.
--
--    pickup_request  (cliente -> duenio)  {lootNetId}
--    loot_taken      (duenio -> todos)    {lootNetId, by, items}
--
--  Solo el cliente "by" suma los items a su inventario. Offline todo corre
--  local (net_my_id() == "" y net_send no hace nada).
--
--  Los handlers de net_on y package.loaded se limpian al cargar la escena,
--  asi que el modulo se vuelve a registrar solo en cada carga (lo requiere
--  pickup.lua).
-- =====================================================================

local loot_net = {}

-- Items (nombre, cantidad) que lleva un pickup
local function read_items(e)
  local items = {}
  for i = 1, get_loot_count(e) do
    local name, quantity = get_loot_at(e, i)
    items[#items + 1] = { name = name, quantity = quantity }
  end
  return items
end

-- Suma items a la nave local y devuelve cuantos NO entraron por falta de
-- bodega (en red esos se pierden, ver docs/lua-api.md)
local function add_to_ship(items)
  local left = {}
  if player_entity == nil or not is_alive(player_entity) then
    for _, item in ipairs(items) do left[#left + 1] = item end
    return left
  end
  for _, item in ipairs(items) do
    local added = add_item(player_entity, item.name, item.quantity)
    if added < item.quantity then
      left[#left + 1] = { name = item.name, quantity = item.quantity - added }
    end
  end
  return left
end

-- El duenio entrega el loot de "e" a "by". Si "by" soy yo (host u offline) lo
-- que no entra en la bodega se queda en el pickup, como siempre; si es otro
-- jugador el pickup se entrega entero y lo que no le quepa se pierde
function loot_net.grant(e, by)
  local items = read_items(e)
  -- kill() es diferido: un segundo choque o peticion en el mismo frame no
  -- debe entregar el loot otra vez
  if #items == 0 then return end

  if by == net_my_id() then
    local left = add_to_ship(items)
    if #left > 0 then
      -- Quedan items: el pickup sigue flotando con lo que sobro
      for _, item in ipairs(items) do set_loot(e, item.name, 0) end
      for _, item in ipairs(left) do set_loot(e, item.name, item.quantity) end
      return
    end
  end

  for _, item in ipairs(items) do set_loot(e, item.name, 0) end
  if net_is_online() then
    net_send("loot_taken", { lootNetId = get_net_id(e), by = by, items = items })
  end
  -- Si era una caja de loot (#27) el director anima la apertura y la anota.
  -- Solo el duenio llega aqui, asi que suena una vez; un pickup normal no esta
  -- en loot_crates y el gancho lo ignora
  if loot_crate_opened ~= nil then pcall(loot_crate_opened, e) end
  net_despawn(e)
end

-- Un cliente pide un pickup mio: el primero que llega se lo lleva
net_on("pickup_request", function(msg, from)
  local e = find_by_net_id(msg.lootNetId)
  if e == nil or not is_local(e) then return end
  loot_net.grant(e, msg.from or from)
end)

-- El duenio informa quien se llevo el loot. Solo "by" suma los items; el
-- pickup lo borra el despawn del duenio
net_on("loot_taken", function(msg, from)
  if msg.by ~= net_my_id() then return end
  from = msg.from or from

  -- Solo vale si lo manda el duenio del pickup (si ya no existe aqui no hay
  -- como comprobarlo y se acepta)
  local e = find_by_net_id(msg.lootNetId)
  if e ~= nil and get_owner(e) ~= from then return end

  local items = {}
  if type(msg.items) == "table" then
    for _, item in ipairs(msg.items) do
      items[#items + 1] = { name = item.name, quantity = item.quantity }
    end
  end
  add_to_ship(items)
end)

return loot_net
