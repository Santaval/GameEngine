local player_movement_module = require("player_movement")
local player_shooting_module = require("player_shooting")
local player_visual_helpers_module = require("player_visual_helpers")
local player_hud_module = require("player_hud")
local player_upgrades_module = require("player_upgrades")
local player_upgrade_menu_module = require("player_upgrade_menu")
local player_gravity_zones_module = require("player_gravity_zones")
local player_mining_module = require("player_mining")

-- Aplica los niveles iniciales de la escena a thrust/dano/vida una sola vez
local stats_applied = false

-- Lo lee game_director.lua; se reinicia cada vez que se carga la escena
game_over = false

-- Script con el que los demas clientes dibujan nuestra nave (prefabs/)
local REMOTE_SCRIPT = "player/remote_player.lua"

-- player_stats recibidos de otras naves, por netId; los consume remote_player.lua
remote_player_stats = {}

-- id con el que la nave esta registrada en la red (cambia al reconectar)
local registered_as = nil
-- la nave local, para responder a peer_joined fuera de update()
local my_ship = nil

local function ship_state(entity)
  return {
    name = net_my_id(),
    hp = get_health(entity),
    max_hp = get_max_health(entity),
    max_speed = get_max_speed(entity),
    engine = get_equipment_level(entity, "engine"),
    gun = get_equipment_level(entity, "gun"),
    shield = get_equipment_level(entity, "shield"),
  }
end

-- Registra la nave local en la red la primera vez que hay sesion (o tras reconectar)
local function ensure_registered(entity)
  if not net_is_online() or registered_as == net_my_id() then return end

  registered_as = net_my_id()
  net_register(entity, REMOTE_SCRIPT, ship_state(entity))
end

-- Manda nuestro spawn directo a un solo jugador que no lo tiene
local function send_spawn_to(player_id)
  if not my_ship or not player_id or registered_as ~= net_my_id() then return end

  local px, py = get_position(my_ship)
  local vx, vy = get_velocity(my_ship)
  local ax, ay = get_acceleration(my_ship)
  local state = ship_state(my_ship)
  state.pos = { x = px, y = py }
  state.vel = { x = vx, y = vy }
  state.acc = { x = ax, y = ay }
  state.rot = get_rotation(my_ship)

  net_send("spawn", {
    netId = get_net_id(my_ship),
    owner = net_my_id(),
    script = REMOTE_SCRIPT,
    state = state,
  }, player_id)
end

-- Un jugador que entra despues no vio nuestro spawn
net_on("peer_joined", function(msg) send_spawn_to(msg.playerId) end)
-- Otro jugador cargo escena (p. ej. salio del menu) y perdio las entidades de
-- los demas: le reenviamos la nave aunque no seamos el host
net_on("snapshot_request", function(msg) send_spawn_to(msg.from) end)

net_on("player_stats", function(data)
  if type(data) == "table" and data.netId then
    remote_player_stats[data.netId] = data
  end
end)

function update()
  -- Global que leen otros scripts (enemy.lua) para perseguir al jugador
  player_entity = this

  if not stats_applied then
    player_upgrades_module.apply_stats(this)
    stats_applied = true
  end

  my_ship = this
  ensure_registered(this)

  player_visual_helpers_module.update(this)

  -- En transito por un portal (#22, map_portal_world.lua) la nave no dispara
  -- ni acelera: el director la mantiene quieta sobre el portal
  if local_portal_transit then
    set_acceleration(this, 0, 0)
  else
    player_shooting_module.update(this)
    player_movement_module.face_mouse(this)
    player_movement_module.update_thrust(this)
  end
  -- Dentro de la gravedad de un planeta se mina solo
  player_mining_module.update(this)

  player_upgrade_menu_module.update(this)

  -- La camara sigue a la nave
  center_camera_on(get_position(this))

  player_hud_module.draw(this)
  player_upgrade_menu_module.draw(this)
  player_gravity_zones_module.draw(this)
  player_mining_module.draw(this)
end

-- Hooks opcionales: el motor los llama solo si el script los define, con la
-- entidad afectada en "this"

function on_damage(amount, source)
  print(string.format("[player] -%d HP (quedan %d)", amount, get_health(this)))
end

-- Chocar contra un planeta quita vida (ver player_gravity_zones.lua)
function on_collision(other)
  player_gravity_zones_module.on_collision(this, other)
end

function on_death()
  print("[player] nave destruida")

  -- Aval Cup (#28): suelta parte de los minerales en orbes. El global solo lo
  -- define map_death_drop.lua; en las demas escenas no hace nada. Se lee antes
  -- de limpiar player_entity y dentro de pcall: un error aqui no debe impedir
  -- el game over
  if death_drop_request ~= nil then
    local ok, err = pcall(function()
      local cx, cy = get_collider_center(this)
      local items = {}
      for i = 1, get_inventory_count(this) do
        local name, quantity = get_inventory_at(this, i)
        if quantity > 0 then items[#items + 1] = { name = name, quantity = quantity } end
      end
      death_drop_request(cx, cy, items)
    end)
    if not ok then print("[player] error al soltar orbes: " .. tostring(err)) end
  end

  -- Sin jugador: los scripts que lo siguen (spawner, iman, enemigos) ya
  -- chequean nil, y asi no leen un id que el registry va a reciclar
  player_entity = nil
  my_ship = nil
  game_over = true
end
