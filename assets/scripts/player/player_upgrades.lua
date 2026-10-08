local player_movement_module = require("player_movement")
local player_shooting_module = require("player_shooting")

local player_upgrades_module = {}

player_upgrades_module.MAX_LEVEL = 10

-- Orden fijo para que la UI sea estable: pairs() en la tabla cost de cada
-- mejora no garantiza orden
local RESOURCE_ORDER = { "iron", "gunpowder", "plasma" }

-- Tabla de datos: el usuario la ajusta a mano. cost es "cantidad x nivel
-- siguiente" (ver get_cost).
player_upgrades_module.UPGRADES = {
  { equipment = "engine", label = "Engine", cost = { iron = 3 } },
  { equipment = "gun",    label = "Gun",    cost = { gunpowder = 2, iron = 1 } },
  { equipment = "shield", label = "Shield", cost = { plasma = 1, iron = 2 } },
}

-- Devuelve una lista { {name, qty}, ... } en el orden fijo iron/gunpowder/
-- plasma. qty = costo base x (nivel actual + 1), o sea el costo del proximo
-- nivel.
function player_upgrades_module.get_cost(entity, index)
  local upgrade = player_upgrades_module.UPGRADES[index]
  local level = get_equipment_level(entity, upgrade.equipment)
  local next_level = level + 1

  local costs = {}
  for _, name in ipairs(RESOURCE_ORDER) do
    local base = upgrade.cost[name]
    if base then
      costs[#costs + 1] = { name = name, qty = base * next_level }
    end
  end

  return costs
end

function player_upgrades_module.can_afford(entity, index)
  local upgrade = player_upgrades_module.UPGRADES[index]
  local level = get_equipment_level(entity, upgrade.equipment)
  if level >= player_upgrades_module.MAX_LEVEL then return false end

  for _, cost in ipairs(player_upgrades_module.get_cost(entity, index)) do
    if not has_item(entity, cost.name, cost.qty) then return false end
  end

  return true
end

-- Aplica el nivel de cada herramienta a las stats reales del jugador. Se usa
-- tanto despues de comprar como una vez al arrancar, para que los niveles
-- iniciales de la escena tambien manden (ver player.lua).
function player_upgrades_module.apply_stats(entity)
  local engine_level = get_equipment_level(entity, "engine")
  player_movement_module.thrust = 60 + 40 * engine_level
  set_max_speed(entity, 60 + 40 * engine_level)

  local gun_level = get_equipment_level(entity, "gun")
  player_shooting_module.bullet_damage = 5 + 5 * gun_level
  player_shooting_module.fire_rate = 0.5 + 0.5 * gun_level

  -- El escudo sube el tope de vida: primero se lee el tope viejo, se fija el
  -- nuevo, y solo despues se cura la diferencia si el tope subio
  local shield_level = get_equipment_level(entity, "shield")
  local old_max = get_max_health(entity)
  local new_max = 60 + 10 * shield_level
  set_max_health(entity, new_max)
  if new_max > old_max then
    heal(entity, new_max - old_max)
  end

  -- Los demas clientes ajustan la barra de vida y la velocidad de nuestra nave.
  -- Antes del registro no hay netId: el spawn ya lleva estas stats
  local net_id = get_net_id(entity)
  if net_is_online() and net_id then
    net_send("player_stats", {
      netId = net_id,
      max_hp = new_max,
      max_speed = 60 + 40 * engine_level,
      engine = engine_level,
      gun = gun_level,
      shield = shield_level,
    })
  end
end

-- Cobra el costo, sube el nivel y reaplica las stats. Devuelve si se pudo.
function player_upgrades_module.purchase(entity, index)
  if not player_upgrades_module.can_afford(entity, index) then return false end

  local upgrade = player_upgrades_module.UPGRADES[index]
  for _, cost in ipairs(player_upgrades_module.get_cost(entity, index)) do
    remove_item(entity, cost.name, cost.qty)
  end

  upgrade_equipment(entity, upgrade.equipment)
  player_upgrades_module.apply_stats(entity)

  return true
end

return player_upgrades_module
