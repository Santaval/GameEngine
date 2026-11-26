-- =====================================================================
--  Director de los contenedores de suministros y la apertura de cajas (#27)
--  (entidad invisible, solo script). Espera a map_seed (como el resto de
--  directores) y corre su paso dentro de pcall: update() falla en silencio.
--  - Reaparicion (host): cada frame compara los sitios de map_supply.slots con
--    las cajas vivas (global loot_crates, lo llena loot_crate.lua) y crea con
--    net_spawn("supply_crate.lua") la que falte: si nunca se abrio, o si pasaron
--    SUPPLY_CRATE.respawn s desde que se abrio. Espera 1 s tras la semilla para
--    que las cajas del snapshot o adoptadas se registren y no se dupliquen.
--  - Apertura: loot_net.grant (solo el duenio) llama a loot_crate_opened(e). El
--    duenio anima la apertura, anota supply_opened[slot] y avisa con
--    crate_opened {x, y, kind, slot}; los demas solo aceptan el aviso del host.
--    Todos guardan supply_opened, asi un host nuevo tras migrar conserva los
--    tiempos de reaparicion.
--  - Animacion: lista local de aperturas; dibuja los frames 1..N-1 de la hoja
--    de la caja (supply-crate o loot-crate-pal) y aguanta el ultimo con alfa
--    decreciente (coordenadas de pantalla, como draw_beam de map_pal_signal.lua).
--  - Un recien llegado recibe supply_state {opened = slot -> segundos desde que
--    se abrio} en respuesta a snapshot_request.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local supply = require("map_supply")

local S = cfg.SUPPLY_CRATE
local PAL = cfg.LOOT_CRATE_PAL

-- Segundos de espera tras recibir la semilla antes del primer paso del host
local GRACE = 1
-- Segundos que se aguanta el ultimo frame abierto mientras se desvanece
local HOLD = 0.4

local clock = 0
local ready_at = nil
local last_error = nil

-- Aperturas en curso (solo dibujo, locales): { x, y, kind, t }
local anims = {}
-- slot -> entidad recien creada por el host, hasta que loot_crate.lua la
-- registre en loot_crates (evita crearla dos veces en ese frame)
local pending = {}

-- Valores de dibujo segun el tipo de caja
local function crate_cfg(kind)
  if kind == "supply" then return S, "supply-crate" end
  return PAL, "loot-crate-pal"
end

local function add_anim(x, y, kind)
  anims[#anims + 1] = { x = x, y = y, kind = kind, t = 0 }
end

-- Lo llama loot_net.grant en el duenio al entregar el loot de "e" (no hace
-- nada si no es una caja de loot): anima, anota la apertura y avisa a todos
function loot_crate_opened(e)
  if loot_crates == nil then return end
  local key = get_net_id(e) or e
  local c = loot_crates[key]
  if c == nil then return end
  loot_crates[key] = nil

  add_anim(c.x, c.y, c.kind)
  if c.slot ~= nil then
    pending[c.slot] = nil
    if supply_opened ~= nil then supply_opened[c.slot] = clock end
  end
  net_send("crate_opened", { x = c.x, y = c.y, kind = c.kind, slot = c.slot })
end

-- Un duenio abrio una caja: solo vale si lo manda el host
net_on("crate_opened", function(data, from)
  if from ~= net_host_id() then return end
  if type(data) ~= "table" or type(data.x) ~= "number" or type(data.y) ~= "number" then return end
  local kind = data.kind == "supply" and "supply" or "pal"
  add_anim(data.x, data.y, kind)
  if type(data.slot) == "string" and supply_opened ~= nil then
    supply_opened[data.slot] = clock
  end
end)

-- Un jugador acaba de entrar: el host le manda cuanto hace que se abrio cada
-- contenedor, para que los reponga a su hora si despues es host
net_on("snapshot_request", function(_, from)
  if not net_is_host() or from == nil or from == "" or from == net_my_id() then return end
  if supply_opened == nil then return end
  local opened = {}
  for slot, t in pairs(supply_opened) do opened[slot] = clock - t end
  net_send("supply_state", { opened = opened }, from)
end)

net_on("supply_state", function(data, from)
  if from ~= net_host_id() then return end
  if type(data) ~= "table" or type(data.opened) ~= "table" or supply_opened == nil then return end
  for slot, elapsed in pairs(data.opened) do
    if type(slot) == "string" and type(elapsed) == "number" then
      supply_opened[slot] = clock - elapsed
    end
  end
end)

-- Slots con una caja de suministros viva (registrada o recien creada)
local function live_slots()
  local live = {}
  if loot_crates ~= nil then
    for key, c in pairs(loot_crates) do
      if c.e ~= nil and is_alive(c.e) then
        if c.kind == "supply" and c.slot ~= nil then live[c.slot] = true end
      else
        loot_crates[key] = nil
      end
    end
  end
  for slot, e in pairs(pending) do
    if is_alive(e) then live[slot] = true else pending[slot] = nil end
  end
  return live
end

-- Crea la caja de un sitio (x, y es su centro; pos es la esquina sup-izq)
local function spawn_crate(s)
  local w = S.size
  local h = w * S.sheet.src_h / S.sheet.frame_w
  local item = S.items[math.random(#S.items)]
  local quantity = math.random(S.quantity.min, S.quantity.max)
  local e = net_spawn("supply_crate.lua", {
    pos = { s.x - w / 2, s.y - h / 2 }, world = true,
    kind = "supply", slot = s.slot, item = item, quantity = quantity,
  })
  if e ~= nil then pending[s.slot] = e end
end

-- Solo el host: repone los contenedores que faltan
local function host_step()
  if not net_is_host() or clock < ready_at then return end
  local live = live_slots()
  for _, s in ipairs(supply.slots(map_seed)) do
    if not live[s.slot] then
      local opened = supply_opened ~= nil and supply_opened[s.slot] or nil
      if opened == nil or clock - opened >= S.respawn then spawn_crate(s) end
    end
  end
end

-- Dibuja y avanza las aperturas (pantalla, como draw_beam de map_pal_signal.lua)
local function draw_anims(dt, camX, camY, sw, sh)
  local i = 1
  while i <= #anims do
    local a = anims[i]
    a.t = a.t + dt
    local c, asset = crate_cfg(a.kind)
    local sheet = c.sheet
    local last = sheet.count - 1
    local open_time = last / S.open_fps

    if a.t >= open_time + HOLD then
      anims[i] = anims[#anims]
      anims[#anims] = nil
    else
      local frame, alpha = last, 255
      if a.t < open_time then
        frame = math.min(last, 1 + math.floor(a.t * S.open_fps))
      else
        alpha = math.floor(255 * (1 - (a.t - open_time) / HOLD))
      end
      local w = c.size
      local h = w * sheet.src_h / sheet.frame_w
      local x = a.x - w / 2 - camX
      local y = a.y - h / 2 - camY
      if not (x + w < 0 or x > sw or y + h < 0 or y > sh) then
        draw_image(asset, x, y, w, h, alpha, "front",
          { src = { x = frame * sheet.frame_w, y = sheet.src_y, w = sheet.frame_w, h = sheet.src_h } })
      end
      i = i + 1
    end
  end
end

local function step()
  if map_seed == nil then return end

  local dt = get_delta_time()
  clock = clock + dt
  if ready_at == nil then ready_at = clock + GRACE end

  local camX, camY = get_camera_position()
  local sw, sh = get_screen_size()

  host_step()
  draw_anims(dt, camX, camY, sw, sh)
end

-- update() falla en silencio: se atrapa el error y se imprime una vez
function update()
  local ok, err = pcall(step)
  if not ok and err ~= last_error then
    last_error = err
    print("[supply] error: " .. tostring(err))
  end
end
