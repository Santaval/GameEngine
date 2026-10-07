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

function update()
  -- Global que leen otros scripts (enemy.lua) para perseguir al jugador
  player_entity = this

  if not stats_applied then
    player_upgrades_module.apply_stats(this)
    stats_applied = true
  end

  player_shooting_module.update(this)
  player_visual_helpers_module.update(this)

  player_movement_module.face_mouse(this)
  player_movement_module.update_thrust(this)
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

  -- Sin jugador: los scripts que lo siguen (spawner, iman, enemigos) ya
  -- chequean nil, y asi no leen un id que el registry va a reciclar
  player_entity = nil
  game_over = true
end
