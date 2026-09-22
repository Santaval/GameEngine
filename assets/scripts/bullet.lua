-- Ejemplo de los hooks de daño. Una entidad puede definir cualquiera de las
-- tres funciones que el motor conoce; las que falten simplemente no se llaman.
--
--   update()                  -> cada frame
--   on_damage(amount, source) -> al recibir daño, source es quien lo causo
--   on_death()                -> justo antes de morir
--
-- En las tres, "this" es la entidad afectada.

function update()
end

function on_damage(amount, source)
  print(string.format("[bullet] -%d HP (quedan %d)", amount, get_health(this)))
end

function on_death()
  print("[bullet] destruida")
end
