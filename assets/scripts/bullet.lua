
function update()
end

function on_damage(amount, source)
  print(string.format("[bullet] -%d HP (quedan %d)", amount, get_health(this)))
end

function on_death()
  print("[bullet] destruida")
end
