-- =====================================================================
--  Director del ranking en vivo y la marca del lider (#29), entidad invisible
--  (solo script). Espera a map_seed (como el resto de directores) y corre su
--  paso dentro de pcall: update() falla en silencio.
--  - Puntaje: el total de minerales del inventario (get_inventory_total; 0 si
--    la nave esta muerta). Cada cliente avisa el suyo con rank_score {total}
--    como mucho cada RANKING.send_interval s si cambio, y cada
--    RANKING.heartbeat s aunque no cambie (asi un mensaje perdido se repara).
--    Un recien llegado recibe el de todos: cada cliente responde a
--    snapshot_request con su rank_score directo.
--  - Estado: ranking_scores (playerId -> {total, t}); el jugador local va
--    bajo net_my_id() ("" sin red). Se quita a quien se va (peer_left) o no
--    se oye en RANKING.stale s.
--  - Orden determinista (igual en todos los clientes): total descendente y, a
--    igualdad, playerId ascendente. Se publican ranking_list ({id, total}, los
--    primeros RANKING.size) y ranking_leader (el primero si su total > 0).
--  - Panel arriba a la derecha (ranking-panel), "TU" para la nave local y, si
--    no esta entre los primeros, su puesto en una fila aparte. La corona
--    (leader-crown) se dibuja sobre la nave del lider; el minimapa
--    (solar_hud.lua) usa ranking_ship_of(id) para su icono.
--  - Gancho de #28: map_ranking_top() devuelve {x, y} de las naves de los
--    primeros SPAWN.top_n (sin la local) para la regla de aparicion.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")

local R = cfg.RANKING

-- position es la esquina sup-izq: la nave mide 430 * 0.2 de ancho, su centro
-- queda a +43 (ver scenes/aval_cup.lua)
local PLAYER_CENTER_X = 43
-- Ancho aproximado de un caracter de DejaVuSansMono 16 (para centrar texto)
local CHAR_WIDTH = 10
-- Separacion entre el borde del cuerpo del panel y la primera fila
local ROW_PAD = 8

local GOLD = { 255, 210, 80 }
local YOU = { 255, 255, 0 }
local WHITE = { 255, 255, 255 }

local clock = 0
local last_error = nil

-- Lo ultimo que se mando por la red
local my_total = 0
local last_sent_total = nil
local last_sent_at = -math.huge

-- Ranking completo (ordenado) del ultimo frame, para ubicar al jugador local
local full_list = {}

-- ---------------------------------------------------------------------
--  Puntajes
-- ---------------------------------------------------------------------

local function compute_my_total()
  if player_entity ~= nil and is_alive(player_entity) then
    return get_inventory_total(player_entity)
  end
  return 0
end

local function send_score(to)
  if not net_is_online() then return end
  if to ~= nil then
    net_send("rank_score", { total = my_total }, to)
  else
    net_send("rank_score", { total = my_total })
  end
end

net_on("rank_score", function(data, from)
  if type(data) ~= "table" or type(data.total) ~= "number" then return end
  if type(from) ~= "string" or from == "" or from == net_my_id() then return end
  ranking_scores[from] = { total = data.total, t = clock }
end)

-- Un recien llegado no conoce los puntajes: cada cliente le manda el suyo
net_on("snapshot_request", function(msg)
  if type(msg) ~= "table" or type(msg.from) ~= "string" or msg.from == "" then return end
  if msg.from == net_my_id() then return end
  send_score(msg.from)
end)

net_on("peer_left", function(msg)
  if type(msg) == "table" and type(msg.playerId) == "string" then
    ranking_scores[msg.playerId] = nil
  end
end)

-- Avisa el puntaje local: al cambiar (con tope de frecuencia) y como latido
local function broadcast_step()
  if not net_is_online() then return end
  local since = clock - last_sent_at
  local changed = my_total ~= last_sent_total
  if (changed and since >= R.send_interval) or since >= R.heartbeat then
    send_score()
    last_sent_total = my_total
    last_sent_at = clock
  end
end

-- ---------------------------------------------------------------------
--  Orden
-- ---------------------------------------------------------------------

-- a va antes que b: mas total, y a igualdad menor playerId
local function before(a, b)
  if a.total ~= b.total then return a.total > b.total end
  return a.id < b.id
end

-- Lista {id, total} de todos los jugadores conocidos, ordenada (insercion)
local function sorted_scores()
  local list = {}
  for id, s in pairs(ranking_scores) do
    local item = { id = id, total = s.total }
    local i = #list
    list[i + 1] = item
    while i >= 1 and before(item, list[i]) do
      list[i + 1] = list[i]
      i = i - 1
    end
    list[i + 1] = item
  end
  return list
end

local function rank_step()
  local me = net_my_id()
  ranking_scores[me] = { total = my_total, t = clock }

  for id, s in pairs(ranking_scores) do
    if id ~= me and clock - s.t > R.stale then ranking_scores[id] = nil end
  end

  full_list = sorted_scores()
  local top = {}
  for i = 1, math.min(R.size, #full_list) do top[i] = full_list[i] end
  ranking_list = top

  local first = top[1]
  if first ~= nil and first.total > 0 then
    ranking_leader = first.id
  else
    ranking_leader = nil
  end
end

-- ---------------------------------------------------------------------
--  Naves
-- ---------------------------------------------------------------------

-- Entidad viva de la nave del jugador `id` (la local o una remota), o nil
function ranking_ship_of(id)
  if id == net_my_id() then
    if player_entity ~= nil and is_alive(player_entity) then return player_entity end
    return nil
  end
  if player_ships == nil then return nil end
  for net_id in pairs(player_ships) do
    local e = find_by_net_id(net_id)
    if e ~= nil and is_alive(e) and get_owner(e) == id then return e end
  end
  return nil
end

-- Gancho de #28: posiciones de las naves de los primeros (sin la local)
function map_ranking_top()
  local list = {}
  local me = net_my_id()
  for i = 1, math.min(cfg.SPAWN.top_n, #ranking_list) do
    local entry = ranking_list[i]
    if entry.total > 0 and entry.id ~= me then
      local e = ranking_ship_of(entry.id)
      if e ~= nil then
        local x, y = get_collider_center(e)
        list[#list + 1] = { x = x, y = y }
      end
    end
  end
  return list
end

-- ---------------------------------------------------------------------
--  Dibujo
-- ---------------------------------------------------------------------

local function row_text(rank, id, total)
  local name = id
  if id == net_my_id() then name = "TU" end
  return string.format("%2d. %-" .. R.name_chars .. "s %6d", rank, string.sub(name, 1, R.name_chars), total)
end

local function row_color(id, rank)
  if id == net_my_id() then return YOU end
  if rank == 1 and ranking_leader == id then return GOLD end
  return WHITE
end

local function draw_panel()
  local P = R.panel
  local sw = get_screen_size()
  local x = sw - P.margin - P.w
  local y = P.top

  draw_image("ranking-panel", x, y, P.w, P.h, P.alpha, "hud")

  local title = "PAL TOP " .. R.size
  local band = P.h * P.header_frac
  draw_text(x + (P.w - #title * CHAR_WIDTH) / 2, y + band * 0.2, title, "default", 255, 255, 255)

  local row_chars = 3 + 1 + R.name_chars + 1 + 6
  local tx = x + (P.w - row_chars * CHAR_WIDTH) / 2
  local ty = y + P.h * P.body_frac + ROW_PAD
  for i, entry in ipairs(ranking_list) do
    local c = row_color(entry.id, i)
    draw_text(tx, ty + (i - 1) * R.row_h, row_text(i, entry.id, entry.total), "default", c[1], c[2], c[3])
  end

  -- El jugador local fuera de los primeros: su puesto en una fila aparte
  local me = net_my_id()
  local in_top = false
  for _, entry in ipairs(ranking_list) do
    if entry.id == me then in_top = true end
  end
  if not in_top then
    for i, entry in ipairs(full_list) do
      if entry.id == me then
        local ry = ty + R.size * R.row_h
        draw_rect(tx, ry - 3, row_chars * CHAR_WIDTH, 1, 255, 255, 255, 120)
        draw_text(tx, ry, row_text(i, me, entry.total), "default", YOU[1], YOU[2], YOU[3])
      end
    end
  end
end

-- Corona sobre la nave del lider (pantalla, capa front)
local function draw_crown(camX, camY, sw, sh)
  if ranking_leader == nil then return end
  local e = ranking_ship_of(ranking_leader)
  if e == nil then return end

  local px, py = get_position(e)
  local size = R.crown_size
  -- El borde de abajo de la corona queda crown_gap px sobre la nave, por
  -- encima del nombre y la barra de vida
  local x = px + PLAYER_CENTER_X - size / 2 - camX
  local y = py - R.crown_gap - size - camY
  if x + size < 0 or x > sw or y + size < 0 or y > sh then return end
  draw_image("leader-crown", x, y, size, size, 255, "front")
end

local function step()
  if map_seed == nil then return end

  clock = clock + get_delta_time()
  my_total = compute_my_total()
  broadcast_step()
  rank_step()

  local camX, camY = get_camera_position()
  local sw, sh = get_screen_size()
  draw_panel()
  draw_crown(camX, camY, sw, sh)
end

-- update() falla en silencio: se atrapa el error y se imprime una vez
function update()
  local ok, err = pcall(step)
  if not ok and err ~= last_error then
    last_error = err
    print("[ranking] error: " .. tostring(err))
  end
end
