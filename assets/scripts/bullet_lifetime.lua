-- Vida local de una bala. Cada cliente la corre por su cuenta, asi que al
-- expirar no hay despawn en red (ver docs/health-and-damage.md).
local bullet_lifetime = {}

bullet_lifetime.LIFETIME = 2  -- segundos

-- Devuelve un update() con su propio contador: cada bala tiene el suyo
function bullet_lifetime.make_update()
  local age = 0
  return function()
    age = age + get_delta_time()
    if age >= bullet_lifetime.LIFETIME then
      -- Kill local: nunca net_despawn, las demas copias expiran solas
      destroy_entity(this)
    end
  end
end

return bullet_lifetime
