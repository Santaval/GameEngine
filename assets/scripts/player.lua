player_velocity = 300;
player_rotation_delta = 5;

function update()
   set_velocity(this, 0, 0)
   vel_y = 0;
   rotation_delta = 0

  if is_action_activated("accelerate") then
   vel_y = vel_y + -1
   set_sprite(this, "spaceship-attack")
  end
  if is_action_activated("brake") then
    vel_y = vel_y + 1
    set_sprite(this, "spaceship-idle")
    
  end
  if is_action_activated("rotate_left") then
    rotation_delta = -1 * player_rotation_delta
  end

  if is_action_activated("rotate_right") then
    rotation_delta = player_rotation_delta
  end

  vel_y = vel_y * player_velocity

   set_velocity(this, 0, vel_y)
   set_rotation(this, rotation_delta)

end