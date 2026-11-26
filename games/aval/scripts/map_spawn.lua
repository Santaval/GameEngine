-- =====================================================================
--  Director de la aparicion y el escudo de la nave local (#28), entidad
--  invisible (solo script). Espera a map_seed, map_biomes y portal_sites (como
--  el resto de directores) y corre su paso dentro de pcall: update() falla en
--  silencio.
--  - Aparicion: pasados SPAWN.wait s (para que lleguen las naves del snapshot)
--    mueve la nave local, una sola vez por carga de escena, a un punto al azar
--    a SPAWN.portal_min..portal_max px de un portal estable (asi se ve), en un
--    sector de SPAWN.biomes, valido para portals.valid_point, fuera de la
--    tormenta, lejos de otras naves (player_clear) y de los primeros del
--    ranking (top_clear). El ranking lo da el gancho opcional map_ranking_top()
--    (lo define #29): devuelve una lista de {x, y}; mientras no exista esa regla
--    se salta. Tras SPAWN.tries intentos relaja las reglas: primero el top,
--    luego las naves y al final usa PLAYER_SPAWN.
--  - Escudo: al aparecer la nave no recibe dano SPAWN_SHIELD.time s (set_shield
--    del motor) o hasta que dispara (player_shooting.lua llama a
--    spawn_shield_cancelled). El duenio avisa con spawn_shield {netId, t} y
--    todos dibujan la hoja spawn-shield sobre la nave (coordenadas de pantalla,
--    como draw_anims de map_supply_world.lua). t = 0 lo quita.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local grid = require("map_grid")
local portals = require("map_portals")
local storm = require("map_storm")

local SP = cfg.SPAWN
local SS = cfg.SPAWN_SHIELD
local W = cfg.WORLD_SIZE

-- position es la esquina sup-izq: nave de 430x650 a scale 0.2 (ver
-- scenes/aval_cup.lua), su centro queda a +43, +65
local PLAYER_CENTER_X, PLAYER_CENTER_Y = 43, 65
-- Segundos finales del escudo en los que el dibujo se desvanece
local FADE = 0.5

local clock = 0
local ready_at = nil
local placed = false
local last_error = nil

-- El escudo local aun no se ha avisado a la red (la nave puede no tener netId
-- todavia, se reintenta cada frame)
local announce_pending = false
-- netId -> { t = segundos que quedan, from = quien lo aviso } de las naves
-- remotas con escudo
local remote_shields = {}

-- Global que lee quien quiera saber si la nave local esta protegida
local_spawn_shield = false

-- ---------------------------------------------------------------------
--  Aparicion
-- ---------------------------------------------------------------------

local function rand_range(a, b)
  return a + math.random() * (b - a)
end

-- Extremos de portal estable usables: sin colapsar y sin una errante encima
local function stable_ends()
  local list = {}
  if portal_sites == nil or portal_sites.ends == nil then return list end
  for _, e in ipairs(portal_sites.ends) do
    local collapsing = portal_sites.collapsing ~= nil and portal_sites.collapsing[e.pair] ~= nil
    if not collapsing and not storm.in_wandering(e.x, e.y) then list[#list + 1] = e end
  end
  return list
end

-- Centros de las demas naves vivas (player_ships: netId -> true)
local function other_ships()
  local list = {}
  if player_ships == nil then return list end
  for id in pairs(player_ships) do
    local e = find_by_net_id(id)
    if e ~= nil and is_alive(e) and e ~= player_entity then
      local cx, cy = get_collider_center(e)
      list[#list + 1] = { x = cx, y = cy }
    end
  end
  return list
end

-- Posiciones de los primeros del ranking; vacio si el gancho de #29 no existe
local function ranking_top()
  if map_ranking_top == nil then return {} end
  local ok, list = pcall(map_ranking_top)
  if ok and type(list) == "table" then return list end
  return {}
end

-- true si (x, y) esta a menos de `dist` de algun punto de la lista
local function near_any(list, x, y, dist)
  for _, p in ipairs(list) do
    local dx, dy = x - p.x, y - p.y
    if dx * dx + dy * dy < dist * dist then return true end
  end
  return false
end

-- Reglas de un punto candidato (el sector, el mapa y la tormenta siempre
-- valen; ships / top son las listas de las reglas que quedan activas)
local function valid(x, y, ships, top)
  if x < 0 or y < 0 or x > W or y > W then return false end
  if storm.in_border(x, y) or storm.in_wandering(x, y) then return false end

  local sx, sy = grid.world_to_sector(x, y)
  local row = map_biomes[sx]
  local biome = row and row[sy]
  local ok_biome = false
  for _, id in ipairs(SP.biomes) do
    if biome == id then ok_biome = true end
  end
  if not ok_biome then return false end

  if not portals.valid_point(map_seed, x, y) then return false end
  if ships ~= nil and near_any(ships, x, y, SP.player_clear) then return false end
  if top ~= nil and near_any(top, x, y, SP.top_clear) then return false end
  return true
end

-- Punto al azar a portal_min..portal_max px de un extremo estable (o de
-- cualquier parte del mundo si no hay ninguno)
local function candidate(ends)
  if #ends == 0 then return rand_range(0, W), rand_range(0, W) end
  local e = ends[math.random(#ends)]
  local a = math.random() * 2 * math.pi
  local d = rand_range(SP.portal_min, SP.portal_max)
  return e.x + math.cos(a) * d, e.y + math.sin(a) * d
end

-- Busca el punto de aparicion y relaja las reglas si hace falta
local function pick_spawn()
  local ends = stable_ends()
  local ships = other_ships()
  local top = ranking_top()
  local levels = {
    { name = nil, ships = ships, top = top },
    { name = "sin la regla del top", ships = ships, top = nil },
    { name = "sin la regla de las naves", ships = nil, top = nil },
  }
  for _, level in ipairs(levels) do
    for _ = 1, SP.tries do
      local x, y = candidate(ends)
      if valid(x, y, level.ships, level.top) then
        if level.name ~= nil then print("[spawn] aparicion " .. level.name) end
        return x, y
      end
    end
  end
  print("[spawn] sin punto valido: se usa PLAYER_SPAWN")
  return cfg.PLAYER_SPAWN.x, cfg.PLAYER_SPAWN.y
end

-- Mueve la nave local al punto elegido y le pone el escudo
local function place()
  local x, y = pick_spawn()
  set_position(player_entity, x - PLAYER_CENTER_X, y - PLAYER_CENTER_Y)
  set_velocity(player_entity, 0, 0)
  center_camera_on(get_position(player_entity))

  set_shield(player_entity, SS.time)
  local_spawn_shield = true
  announce_pending = true
  placed = true
end

-- ---------------------------------------------------------------------
--  Escudo
-- ---------------------------------------------------------------------

-- Lo llama player_shooting.lua tras quitar el escudo al disparar: avisa a los
-- demas y limpia el estado local
function spawn_shield_cancelled()
  local_spawn_shield = false
  announce_pending = false
  if player_entity ~= nil then
    local id = get_net_id(player_entity)
    if id ~= nil then net_send("spawn_shield", { netId = id, t = 0 }) end
  end
end

-- Una nave remota aparecio con escudo (t segundos) o lo perdio (t = 0)
net_on("spawn_shield", function(data, from)
  if type(data) ~= "table" or type(data.netId) ~= "string" or type(data.t) ~= "number" then return end
  if data.t <= 0 then
    -- Solo el duenio de la nave puede quitarle el escudo
    local e = find_by_net_id(data.netId)
    local entry = remote_shields[data.netId]
    if entry ~= nil and (entry.from == from or (e ~= nil and get_owner(e) == from)) then
      remote_shields[data.netId] = nil
    end
    return
  end
  remote_shields[data.netId] = { t = math.min(data.t, SS.time), from = from }
end)

-- Dibuja la hoja del escudo centrada en (cx, cy); t = segundos que quedan
local function draw_shield(cx, cy, t, camX, camY, sw, sh)
  local size = SS.size
  local x = cx - size / 2 - camX
  local y = cy - size / 2 - camY
  if x + size < 0 or x > sw or y + size < 0 or y > sh then return end

  local sheet = SS.sheet
  local frame = math.floor(clock * SS.fps) % sheet.count
  local alpha = SS.alpha
  if t < FADE then alpha = math.floor(alpha * t / FADE) end
  draw_image("spawn-shield", x, y, size, size, alpha, "front",
    { src = { x = frame * sheet.frame_w, y = sheet.src_y, w = sheet.frame_w, h = sheet.src_h } })
end

-- Avisa del escudo local en cuanto la nave tiene netId y lo dibuja
local function local_shield_step(camX, camY, sw, sh)
  if not local_spawn_shield then return end

  local left = 0
  if player_entity ~= nil and is_alive(player_entity) then left = get_shield(player_entity) end
  if left <= 0 then
    local_spawn_shield = false
    announce_pending = false
    return
  end

  if announce_pending then
    local id = get_net_id(player_entity)
    if id ~= nil then
      net_send("spawn_shield", { netId = id, t = left })
      announce_pending = false
    end
  end

  local cx, cy = get_collider_center(player_entity)
  draw_shield(cx, cy, left, camX, camY, sw, sh)
end

-- Cuenta atras y dibujo de los escudos de las naves remotas
local function remote_shield_step(dt, camX, camY, sw, sh)
  for id, entry in pairs(remote_shields) do
    entry.t = entry.t - dt
    local e = find_by_net_id(id)
    if entry.t <= 0 then
      remote_shields[id] = nil
    elseif e ~= nil then
      if not is_alive(e) or get_owner(e) ~= entry.from then
        remote_shields[id] = nil
      else
        local cx, cy = get_collider_center(e)
        draw_shield(cx, cy, entry.t, camX, camY, sw, sh)
      end
    end
  end
end

local function step()
  if map_seed == nil or map_biomes == nil or portal_sites == nil then return end

  local dt = get_delta_time()
  clock = clock + dt

  if not placed and player_entity ~= nil and is_alive(player_entity) then
    if ready_at == nil then ready_at = clock + SP.wait end
    if clock >= ready_at then place() end
  end

  local camX, camY = get_camera_position()
  local sw, sh = get_screen_size()
  local_shield_step(camX, camY, sw, sh)
  remote_shield_step(dt, camX, camY, sw, sh)
end

-- update() falla en silencio: se atrapa el error y se imprime una vez
function update()
  local ok, err = pcall(step)
  if not ok and err ~= last_error then
    last_error = err
    print("[spawn] error: " .. tostring(err))
  end
end
