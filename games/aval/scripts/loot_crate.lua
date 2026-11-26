-- =====================================================================
--  Script de runtime de la caja de loot alto (prefabs/loot_crate_pal.lua).
--  Sin iman ni movimiento: la nave local la abre al tocarla. El reparto lo
--  decide el duenio de la caja (ver loot_net.lua), asi que se entrega una sola
--  vez.
--  Cada frame se anota en el global loot_crates (clave -> {e, x, y, kind,
--  slot}) para que map_supply_world.lua (#27) sepa que cajas hay, donde y de
--  que tipo: "pal" (la de los eventos) o "supply" (contenedor de suministros,
--  con slot "sx:sy"). La clave es el netId, o la entidad sin red.
-- =====================================================================

local loot_net = require("loot_net")

-- Segundos entre un pickup_request y el siguiente de esta caja (ver pickup.lua)
local REQUEST_INTERVAL = 1

-- Datos por entidad (el chunk corre una vez por caja). spawn_state lo fija el
-- motor mientras arma el prefab
local state = spawn_state or {}
local kind = state.kind or "pal"
local slot = state.slot
local clock = 0
local last_request = -math.huge
local entry = { e = nil, x = 0, y = 0, kind = kind, slot = slot }

function update()
  clock = clock + get_delta_time()

  if loot_crates ~= nil then
    entry.e = this
    entry.x, entry.y = get_collider_center(this)
    loot_crates[get_net_id(this) or this] = entry
  end
end

-- Con la bodega llena no se puede abrir
local function hold_has_room()
  local capacity = get_inventory_capacity(player_entity)
  return capacity <= 0 or get_inventory_total(player_entity) < capacity
end

-- Solo abre la nave local. Si la caja es mia se la entrego a mi nave; si no, se
-- la pido al duenio
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
