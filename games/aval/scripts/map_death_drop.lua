-- =====================================================================
--  Director de los orbes de muerte (#28), entidad invisible (solo script).
--  Cuando muere una nave, player.lua llama a death_drop_request(x, y, items)
--  (global, solo existe en la Aval Cup): cada mineral suelta DEATH_DROP.fraction
--  de lo que llevaba, repartido en orbes de DEATH_DROP.per_orb unidades (tope
--  max_orbs por mineral).
--  - Los orbes los crea siempre el host con net_spawn("death_orb.lua"): asi
--    siguen ahi aunque el jugador que murio recargue la escena. Si el que murio
--    es un cliente, manda death_drop {x, y, items} al host; el host (u offline)
--    los crea directamente.
--  - Los orbes salen al azar dentro de DEATH_DROP.radius del punto de muerte,
--    empujados hacia afuera. Se recogen con el flujo de loot_net.lua.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")

local D = cfg.DEATH_DROP
local W = cfg.WORLD_SIZE

-- Tamano del orbe en px de mundo (position es la esquina sup-izq)
local ORB_W = D.size
local ORB_H = D.size * D.frame_h / D.frame_w

-- Crea un orbe de `quantity` unidades de `item` alrededor de (x, y)
local function spawn_orb(x, y, item, quantity)
  -- Punto al azar dentro del circulo (sqrt para repartir por area)
  local a = math.random() * 2 * math.pi
  local r = math.sqrt(math.random()) * D.radius
  local cx = math.max(0, math.min(W, x + math.cos(a) * r))
  local cy = math.max(0, math.min(W, y + math.sin(a) * r))

  -- Sale hacia afuera del punto de muerte
  local ox, oy = cx - x, cy - y
  local len = math.sqrt(ox * ox + oy * oy)
  local dirx, diry
  if len < 0.001 then dirx, diry = math.cos(a), math.sin(a) else dirx, diry = ox / len, oy / len end
  local speed = D.push.min + math.random() * (D.push.max - D.push.min)

  net_spawn("death_orb.lua", {
    pos = { x = cx - ORB_W / 2, y = cy - ORB_H / 2 },
    vel = { x = dirx * speed, y = diry * speed },
    item = item, quantity = quantity, world = true,
  })
end

-- Solo el host: reparte los minerales de items ({ name, quantity }) en orbes
local function spawn_drop(x, y, items)
  for _, it in ipairs(items) do
    local n = math.floor(it.quantity * D.fraction)
    if n > 0 then
      local orbs = math.min(D.max_orbs, math.ceil(n / D.per_orb))
      local base = math.floor(n / orbs)
      local extra = n - base * orbs
      for i = 1, orbs do
        -- El resto se reparte de uno en uno entre los primeros orbes
        spawn_orb(x, y, it.name, base + (i <= extra and 1 or 0))
      end
    end
  end
end

-- Lo llama player.lua al morir la nave local. items: lista { name, quantity }
function death_drop_request(x, y, items)
  if net_is_host() then
    spawn_drop(x, y, items)
  else
    net_send("death_drop", { x = x, y = y, items = items }, net_host_id())
  end
end

-- Un cliente murio: el host crea sus orbes. Solo vale en el host y con datos
-- bien formados (solo minerales con orbe, cantidades razonables)
net_on("death_drop", function(data)
  if not net_is_host() then return end
  if type(data) ~= "table" or type(data.x) ~= "number" or type(data.y) ~= "number" then return end
  if type(data.items) ~= "table" then return end

  local items = {}
  for _, it in ipairs(data.items) do
    if type(it) == "table" and D.orbs[it.name] ~= nil
        and type(it.quantity) == "number" and it.quantity > 0 and it.quantity <= 100000 then
      items[#items + 1] = { name = it.name, quantity = it.quantity }
    end
  end
  spawn_drop(data.x, data.y, items)
end)

-- Todo el trabajo es por evento (death_drop_request y net_on): no hay nada
-- que correr cada frame
function update()
end
