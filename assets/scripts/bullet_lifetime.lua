-- Vida local de una bala. Cada cliente la corre por su cuenta, asi que al
-- expirar no hay despawn en red (ver docs/health-and-damage.md).
local bullet_lifetime = {}

bullet_lifetime.LIFETIME = 2  -- segundos

-- Devuelve un update() con su propio contador: cada bala tiene el suyo
function bullet_lifetime.make_update()
  local age = 0
  -- Un solo salto por portal (#22): sin esto la bala iria y vendria entre extremos
  local ported = false
  return function()
    age = age + get_delta_time()
    if not ported and portal_bullet_step ~= nil then
      ported = portal_bullet_step(this)
    end
    if age >= bullet_lifetime.LIFETIME then
      -- Kill local: nunca net_despawn, las demas copias expiran solas
      destroy_entity(this)
    end
  end
end

return bullet_lifetime
