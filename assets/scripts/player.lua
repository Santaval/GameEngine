player_velocity = 150;

function update()
   set_velocity(this, 0, 0)
   vel_y = 0;

  if is_action_activated("accelerate") then
   vel_y = vel_y + -1
  end
  if is_action_activated("brake") then
    vel_y = vel_y + 1
  end
  vel_y = vel_y * player_velocity

   set_velocity(this, 0, vel_y)

end