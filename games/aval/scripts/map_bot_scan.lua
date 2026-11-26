-- =====================================================================
--  Escaneo para los bots del servidor (server/src/bots). El servidor no
--  conoce el mapa (rocas y planetas salen de la semilla en cada cliente), asi
--  que el host contesta a cada bot "que hay a mi alrededor?".
--  - bot_scan {x, y, r, planets?}: solo lo contesta el host. r se recorta a
--    SCAN_MAX_R. Con planets == true tambien manda los planetas minables.
--  - bot_scan_result {rocks, planets?}: directo al bot que pregunto.
--      rocks   = lista de { id, x, y, radius, hp } (las MAX_ROCKS mas cercanas)
--      planets = lista de { x, y, range, body_radius, mineral, mine_interval }
--  Los handlers van dentro de pcall: un error aqui seria silencioso.
--  Ver docs/aval-cup.md (Server bots).
-- =====================================================================

local SCAN_MAX_R = 2500
local MAX_ROCKS = 20

local last_error = nil

local function planets_list()
  local out = {}
  for _, p in ipairs(scene_planets) do
    if p.mineral ~= nil then
      out[#out + 1] = {
        x = math.floor(p.x + 0.5),
        y = math.floor(p.y + 0.5),
        range = p.range,
        body_radius = p.body_radius,
        mineral = p.mineral,
        mine_interval = p.mine_interval,
      }
    end
  end
  return out
end

local function answer(data, from)
  if not net_is_host() then return end
  if type(from) ~= "string" or from == "" or from == net_my_id() then return end
  if type(data) ~= "table" or type(data.x) ~= "number" or type(data.y) ~= "number" then return end

  local r = SCAN_MAX_R
  if type(data.r) == "number" and data.r > 0 and data.r < SCAN_MAX_R then r = data.r end

  local rocks = {}
  if map_rocks_info_near ~= nil then rocks = map_rocks_info_near(data.x, data.y, r, MAX_ROCKS) end
  local reply = { rocks = rocks }
  if data.planets == true then reply.planets = planets_list() end
  net_send("bot_scan_result", reply, from)
end

net_on("bot_scan", function(data, from)
  local ok, err = pcall(answer, data, from)
  if not ok and err ~= last_error then
    last_error = err
    print("[bot_scan] error: " .. tostring(err))
  end
end)

-- Director sin trabajo por frame: el script solo registra el handler
function update() end
