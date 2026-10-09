-- =====================================================================
--  Director del mundo de la Aval Cup (entidad invisible, solo script).
--  - Semilla: el host (u offline) elige una con random_seed() y la fija en los
--    ajustes de la sala (net_set_match_seed); los demas la leen de
--    net_room_settings().seed (llega por room_settings o por el snapshot).
--  - Mapa: con la semilla se reparten los biomas y los planetas (map_biomes) y
--    se genera TODO el mundo (map_chunks); planetas y rocas se crean LOCALES
--    con spawn_local, sin red: todos los clientes construyen lo mismo. Solo
--    viajan los cambios (rocas destruidas).
--  - Destruccion: el host manda; asteroid.lua llama a map_world_destroyed(id)
--    cuando una roca de chunk muere en el host, y el director avisa a todos
--    (map_rock_destroyed) y a los recien llegados (map_destroyed).
--  - Culling: cada frame fija el area activa alrededor del jugador
--    (set_active_area); las rocas fuera de ella duermen.
--  Ver docs/aval-cup.md.
-- =====================================================================

local chunks = require("map_chunks")
local biomes = require("map_biomes")
local grid = require("map_grid")
local ui = require("ui_helpers")
local asteroid_cfg = require("asteroid_config")

-- Ids por mensaje map_destroyed: debe quedar bajo el limite de ~12 KB del relay
local BATCH_SIZE = 400

local seed = nil
local built = false
-- chunk_id -> entidad viva (para borrarla si el host avisa que murio)
local rocks = {}
-- chunk_id -> radio del cuerpo de la roca en px (no hay getter del collider)
local rock_radius = {}

-- Estado compartido con asteroid.lua (la escena lo reinicia al cargar)
map_destroyed = map_destroyed or {}

-- Borra la copia local de una roca de chunk, si sigue viva
local function destroy_local(id)
  local e = rocks[id]
  rocks[id] = nil
  if e ~= nil and is_alive(e) then destroy_entity(e) end
end

-- Lo llama asteroid.lua cuando la roca muere (en cualquier cliente) o la borra
-- el host: el id de la entidad se recicla, asi que se suelta la referencia
function map_rock_gone(id)
  rocks[id] = nil
end

-- Rocas de chunk vivas cuyo centro esta a menos de r px de (x, y), como lista de
-- entidades. Lo usa el Pulso del Reactor (map_reactor_world.lua): cada cliente
-- empuja su propia copia local
function map_rocks_near(x, y, r)
  local found = {}
  local r2 = r * r
  for _, e in pairs(rocks) do
    if is_alive(e) then
      local cx, cy = get_collider_center(e)
      local dx, dy = cx - x, cy - y
      if dx * dx + dy * dy < r2 then found[#found + 1] = e end
    end
  end
  return found
end

-- Rocas de chunk vivas a menos de r px de (x, y) como lista de
-- { id, x, y, radius, hp }, las `limit` (20 por defecto) mas cercanas primero.
-- Lo usa map_bot_scan.lua para contestar a los bots del servidor
function map_rocks_info_near(x, y, r, limit)
  limit = limit or 20
  local r2 = r * r
  local list = {}
  local keys = {}
  for id, e in pairs(rocks) do
    if is_alive(e) then
      local cx, cy = get_collider_center(e)
      local dx, dy = cx - x, cy - y
      local d2 = dx * dx + dy * dy
      if d2 < r2 then
        local item = {
          id = id,
          x = math.floor(cx + 0.5),
          y = math.floor(cy + 0.5),
          radius = math.floor(rock_radius[id] or asteroid_cfg.ASTEROID_SHEET.bodyRadius),
          hp = get_health(e),
        }
        -- Insercion ordenada por distancia (no hay table.sort en este motor)
        local i = #list
        list[i + 1] = item
        keys[i + 1] = d2
        while i >= 1 and d2 < keys[i] do
          list[i + 1] = list[i]
          keys[i + 1] = keys[i]
          i = i - 1
        end
        list[i + 1] = item
        keys[i + 1] = d2
        -- Solo las `limit` mas cercanas
        if #list > limit then
          list[#list] = nil
          keys[#keys] = nil
        end
      end
    end
  end
  return list
end

-- Lo llama asteroid.lua en el host cuando una roca de chunk muere: la anota y
-- avisa a los demas
function map_world_destroyed(id)
  map_destroyed[id] = true
  net_send("map_rock_destroyed", { id = id })
end

-- Solo se acepta lo que dice el host
net_on("map_rock_destroyed", function(data, from)
  if from ~= net_host_id() then return end
  if type(data) ~= "table" or type(data.id) ~= "string" then return end
  map_destroyed[data.id] = true
  destroy_local(data.id)
end)

-- Lote de ids destruidos (respuesta del host a un recien llegado)
net_on("map_destroyed", function(data, from)
  if from ~= net_host_id() then return end
  if type(data) ~= "table" or type(data.ids) ~= "table" then return end
  for _, id in ipairs(data.ids) do
    if type(id) == "string" then
      map_destroyed[id] = true
      destroy_local(id)
    end
  end
end)

-- Un jugador acaba de entrar: el host le manda las rocas ya destruidas, en
-- lotes. La semilla le llega aparte, en el snapshot
net_on("snapshot_request", function(_, from)
  if not net_is_host() or from == nil or from == "" or from == net_my_id() then return end

  local batch = {}
  for id in pairs(map_destroyed) do
    batch[#batch + 1] = id
    if #batch >= BATCH_SIZE then
      net_send("map_destroyed", { ids = batch }, from)
      batch = {}
    end
  end
  if #batch > 0 then net_send("map_destroyed", { ids = batch }, from) end
end)

-- Semilla de la partida: la de los ajustes de la sala, o una nueva si somos el
-- host (u offline) y todavia no hay
local function acquire_seed()
  local current = net_room_settings().seed
  if current == nil and net_is_host() then
    local fresh = random_seed()
    if fresh <= 0 then fresh = 1 end
    if net_set_match_seed(fresh) then current = net_room_settings().seed end
  end
  return current
end

-- Genera el mundo entero y crea las rocas que no estan destruidas
local function build_world()
  -- Planetas: la tabla se vacia en el sitio (la leen solar_hud y las zonas de
  -- gravedad del jugador) por si la escena se reinicia
  local layout = biomes.layout(seed)
  for k in pairs(scene_planets) do scene_planets[k] = nil end
  for _, p in ipairs(layout.planets) do
    spawn_local("planet.lua", p)
    scene_planets[#scene_planets + 1] = p
  end
  map_biomes = layout.biomes

  local world = chunks.generate_world(seed)
  local count, wrecks, drifting = 0, 0, 0
  for _, list in pairs(world) do
    for _, state in ipairs(list) do
      if not map_destroyed[state.chunk_id] then
        local e = spawn_local("asteroid.lua", state)
        if e ~= nil then
          rocks[state.chunk_id] = e
          local body = state.wreck and asteroid_cfg.WRECK_SHEET.bodyRadius
            or asteroid_cfg.ASTEROID_SHEET.bodyRadius
          rock_radius[state.chunk_id] = body * (state.scale or 1)
          count = count + 1
          if state.wreck then wrecks = wrecks + 1 end
          if state.drift then drifting = drifting + 1 end
        end
      end
    end
  end
  map_seed = seed
  built = true
  print(string.format("[aval_cup] map_seed=%d, %d rocas (%d pecios, %d a la deriva), %d planetas",
    seed, count, wrecks, drifting, #layout.planets))
end

-- Area activa alrededor del jugador; muerto, se conserva la ultima
local function update_active_area()
  if player_entity == nil or not is_alive(player_entity) then return end
  local x, y = get_collider_center(player_entity)
  set_active_area(grid.active_bounds(x, y))
end

function update()
  if not built then
    seed = seed or acquire_seed()
    if seed == nil then
      local _, h = get_window_size()
      ui.draw_centered(h / 2, "Sincronizando mapa..", "debug-big", 28, 255, 255, 255)
      return
    end
    build_world()
  end

  update_active_area()
end
