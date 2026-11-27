-- Ambiente por zona y hora (issue #65). El estado es GLOBAL (los modulos se
-- recargan en cada escena, los globales no). Lo llama el controlador del mapa:
--   set_zone(clave) cada frame (idempotente), tick(dt) cada frame, set_time(t).
local logic = require("ambience_logic")

ambience_state = ambience_state or {
  zone = nil, time = logic.DEFAULT_TIME, layers = {}, oneshot = { timer = nil, last_id = nil },
}
local st = ambience_state
local M = {}

local function seed_once()
  if not audio_rng_seeded then math.randomseed(random_seed()); audio_rng_seeded = true end
end

function M.get_time() return st.time end
function M.set_time(t)
  if t == "day" or t == "night" then st.time = t end
end
function M.get_zone() return st.zone end

-- Clave nil/"" o desconocida: se conserva la anterior. Al cambiar, se reinicia
-- el temporizador de one-shots.
function M.set_zone(key)
  if key == nil or key == "" or not logic.SETS[key] or key == st.zone then return end
  st.zone = key
  st.oneshot.timer = nil
end

function M.tick(dt)
  seed_once()
  dt = math.min(dt, 0.1)
  local set = logic.resolve(st.zone, st.time)
  local target_id = set and set.loop or nil
  local target_vol = set and set.volume or 1

  -- Un handle muerto (load_scene detiene todos los sonidos): la capa objetivo se
  -- reinicia; las que se estaban apagando se descartan sin reiniciar.
  local keep = {}
  for i = 1, #st.layers do
    local l = st.layers[i]
    if l.handle and not is_playing(l.handle) then
      l.handle = nil
      if l.id == target_id then keep[#keep + 1] = l end
    else
      keep[#keep + 1] = l
    end
  end
  for i = 1, #st.layers do st.layers[i] = nil end
  for i = 1, #keep do st.layers[i] = keep[i] end

  local removed = logic.step_layers(st.layers, target_id, target_vol, dt, logic.FADE_TIME)
  for i = 1, #removed do
    if removed[i].handle then stop_sound(removed[i].handle, 0) end
  end
  for i = 1, #st.layers do
    local l = st.layers[i]
    local v = logic.layer_volume(l)
    if not l.handle then
      l.handle = play_sound(l.id, { loop = true, volume = v, bus = "ambience" })
      if l.handle == 0 then l.handle = nil end
    else
      set_sound_volume(l.handle, v)
    end
  end

  -- One-shots alrededor del jugador (nada sin jugador)
  if set and player_entity then
    local pick = logic.oneshot_step(st.oneshot, dt, set.oneshots, math.random)
    if pick then
      local px, py = get_position(player_entity)
      local x, y = logic.place(px + 8, py + 12, math.random)
      play_sound_at(pick.id, x, y, { volume = pick.volume, min_dist = 96, max_dist = 500, bus = "ambience" })
    end
  elseif not set then
    st.oneshot.timer = nil
  end
end

return M
