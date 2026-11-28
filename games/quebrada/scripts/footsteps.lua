-- Pasos por superficie (issue #65). Los archivos de pasos son tiras de varios pasos
-- (~5 s), asi que suenan EN BUCLE mientras el jugador anda y se cortan al parar.
-- Uso en el walker:
--   footsteps = { on_state = require("footsteps").on_state }
-- El controlador del mapa llama a set_source(idx) al cargar (surface_logic.build).
local logic = require("surface_logic")
local M = {}
M.BOX = { x = 5, y = 28, w = 14, h = 8 } -- caja de pies del jugador (muneco 24x38)
M.STOP_FADE_MS = 80
local source = nil   -- indice de superficies de esta escena (se pierde al cambiar de escena)

-- Estado GLOBAL (los modulos se recargan al cambiar de escena, los handles mueren igual)
footsteps_state = footsteps_state or { handle = nil, key = nil }
local st = footsteps_state

local function seed_once()
  if not audio_rng_seeded then
    math.randomseed(random_seed())
    audio_rng_seeded = true
  end
end

function M.set_source(idx) source = idx end

local function stop_loop()
  if st.handle then stop_sound(st.handle, M.STOP_FADE_MS) end
  st.handle, st.key = nil, nil
end

-- Se llama cada frame desde el walker: (entity, moving, running)
function M.on_state(entity, moving, running)
  if not moving then
    stop_loop()
    return
  end
  seed_once()
  -- Un handle muerto (cambio de escena detiene todos los sonidos)
  if st.handle and not is_playing(st.handle) then st.handle, st.key = nil, nil end

  local px, py = get_position(entity)
  local fx, fy = logic.foot_center(px, py, M.BOX)
  local surface = logic.surface_at(source, fx, fy)
  local gait = running and "run" or "walk"
  local key = surface .. ":" .. gait
  if st.handle and st.key == key then return end

  -- Cambio de superficie o de paso (andar/correr): corta el bucle anterior y arranca el nuevo
  stop_loop()
  local id, vol = logic.pick_step(surface, running and true or false, nil, math.random)
  if id then
    local h = play_sound(id, { loop = true, volume = vol, bus = "sfx" })
    if h and h ~= 0 then st.handle, st.key = h, key end
  end
end

return M
