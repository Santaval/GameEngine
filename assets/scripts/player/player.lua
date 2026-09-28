local player_movement_module = require("player_movement")
local player_shooting_module = require("player_shooting")
local player_visual_helpers_module = require("player_visual_helpers")
local player_hud_module = require("player_hud")

function update()
  -- Global que leen otros scripts (enemy.lua) para perseguir al jugador
  player_entity = this

  player_movement_module.face_mouse(this)
  player_movement_module.update_thrust(this)
  player_shooting_module.update(this)
  player_visual_helpers_module.update(this)

  -- La camara sigue a la nave
  center_camera_on(get_position(this))

  player_hud_module.draw(this)
end

-- Hooks opcionales: el motor los llama solo si el script los define, con la
-- entidad afectada en "this"

function on_damage(amount, source)
  print(string.format("[player] -%d HP (quedan %d)", amount, get_health(this)))
end

function on_death()
  print("[player] nave destruida")
end
