-- =====================================================================
--  Script de runtime de cada portal inestable (prefabs/unstable_portal.lua).
--  Lo corre cada cliente con su copia: todos cuentan la vida y la anotan en el
--  global unstable_portals (netId -> {x, y, life, age}; lo leen
--  map_portal_world.lua y el minimapa). Solo el duenio (el host, o el nuevo
--  host tras migrar) lo borra al terminar su animacion de cierre. Un recien
--  llegado corrige su vida con unstable_portal_life_fix. Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")

local UP = cfg.UNSTABLE_PORTAL

-- Datos de este portal (spawn_state lo fija el motor mientras arma el prefab)
local state = spawn_state or {}
local life = state.life or cfg.UNSTABLE_PORTAL_LIFE.min
local age = 0
local entry = { x = 0, y = 0, life = life, age = 0 }

function update()
  local dt = get_delta_time()
  local id = get_net_id(this)

  -- Vida que manda el host a un recien llegado: se aplica una sola vez, y el
  -- portal ya esta abierto
  if id ~= nil and unstable_portal_life_fix ~= nil and unstable_portal_life_fix[id] ~= nil then
    life = unstable_portal_life_fix[id]
    unstable_portal_life_fix[id] = nil
    age = UP.open_time
  end

  life = life - dt
  age = age + dt

  if id ~= nil and unstable_portals ~= nil then
    entry.x, entry.y = get_position(this)
    entry.life = life
    entry.age = age
    unstable_portals[id] = entry
  end

  -- Terminada la animacion de cierre: se borra (el host repone)
  if is_local(this) and life <= -UP.collapse_time then net_despawn(this) end
end
