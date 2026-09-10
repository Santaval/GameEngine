function update()
  if is_action_activated("accelerate") then
    print("acceleration")
  end
  if is_action_activated("brake") then
    print("braking")
  end
  if is_action_activated("down") then
    print("down")
  end
  if is_action_activated("right") then
    print("right")
  end
end