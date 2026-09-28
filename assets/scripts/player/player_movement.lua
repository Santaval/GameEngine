local player_movement_module = {}

function player_movement_module.accelerate()
    accel_y = 0

    if is_action_activated("accelerate") then
      accel_y = accel_y + -1
      set_sprite(this, "spaceship-movement")