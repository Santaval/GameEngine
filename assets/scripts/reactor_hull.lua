-- =====================================================================
--  Script de cada circulo de colision del casco o el anillo del reactor y de
--  su nucleo (prefabs/reactor_collider.lua y reactor_core.lua). Masa infinita:
--  no se mueve, hace rebotar lo que lo toca. Corre en todos los clientes con
--  su copia local; el dano por impacto lo pone el DamageSystem (componente
--  damage del prefab), que corre antes y ve las velocidades previas al rebote.
-- =====================================================================

-- Cuanto de la velocidad de choque se devuelve (0 = sin rebote) y el empuje
-- minimo (px/s) con el que sale la nave aunque el golpe sea suave. max_speed no
-- topa este impulso: solo limita lo que suma el motor (ver asteroid.lua)
local RESTITUTION = 0.4
local MIN_KNOCKBACK = 60

-- Refleja la velocidad de `e` contra la normal (nx, ny) que sale del casco. Solo
-- actua si se acerca, asi que los frames siguientes de solape no repiten el
-- impulso. Devuelve la velocidad resultante
local function reflect(e, nx, ny)
  local vx, vy = get_velocity(e)
  local along = vx * nx + vy * ny
  if along < 0 then
    vx = vx - (1 + RESTITUTION) * along * nx
    vy = vy - (1 + RESTITUTION) * along * ny
  end
  return vx, vy
end

-- Normal unitaria del centro del casco al centro de `e`; nil si coinciden
local function normal_to(e)
  local hx, hy = get_collider_center(this)
  local ex, ey = get_collider_center(e)
  local dx, dy = ex - hx, ey - hy
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.001 then return nil end
  return dx / d, dy / d
end

-- Una bala: tiene dano pero ni vida, ni loot, ni inventario y si gravedad. El
-- casco no tiene gravedad, asi que los circulos entre si no se confunden con
-- balas. Un blanco sin vida no la gasta (DamageSystem lo ignora), por eso se
-- borra aqui, en local: nunca net_despawn, como bullet_lifetime.lua
local function is_bullet(e)
  return get_damage(e) > 0 and get_health(e) == 0 and not has_loot(e)
    and not has_inventory(e) and has_gravity(e)
end

function on_collision(other)
  if has_inventory(other) then
    -- Solo la nave local: la de otro jugador la corrige su duenio con su estado
    local nx, ny = normal_to(other)
    if nx == nil then return end
    local vx, vy = reflect(other, nx, ny)
    local outward = vx * nx + vy * ny
    if outward < MIN_KNOCKBACK then
      local push = MIN_KNOCKBACK - outward
      vx = vx + push * nx
      vy = vy + push * ny
    end
    set_velocity(other, vx, vy)
  elseif has_loot(other) then
    local nx, ny = normal_to(other)
    if nx == nil then return end
    local vx, vy = reflect(other, nx, ny)
    set_velocity(other, vx, vy)
  elseif is_bullet(other) then
    destroy_entity(other)
  end
end
