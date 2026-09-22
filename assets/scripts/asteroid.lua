function update()
end

function on_damage(amount, source)
  print(string.format("[asteroid] -%d HP (quedan %d)", amount, get_health(this)))
end

function on_death()
  local x, y = get_position(this)
  mineral = create_entity()
  add_transform(mineral, x, y, 1, 1, 0)
  add_sprite(mineral, "mineral", 16, 16, 0, 0)
  add_rigid_body(mineral, 0, 0, 0, 0, 0)
  add_circle_collider(mineral, 8, 16, 16)
end