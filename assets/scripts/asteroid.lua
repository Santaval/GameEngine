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
  -- collect_mineral y no on_collision: este mismo archivo es el script de
  -- todos los asteroides, y set_on_collision solo afecta a esta entidad
  -- puntual (el mineral), no a los asteroides que lo cargan
  set_on_collision(mineral, collect_mineral)
end

-- Recoge el mineral si quien choco tiene inventario (balas y otros
-- asteroides no lo tienen y lo atraviesan). "this" aqui es el mineral,
-- porque el hook lo puso el mineral con set_on_collision.
function collect_mineral(other)
  if not has_inventory(other) then return end
  if add_item(other, "mineral", 1) > 0 then destroy_entity(this) end  -- si esta lleno, se queda flotando
end