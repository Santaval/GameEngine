-- =====================================================================
--  Director de los eventos #26 (entidad invisible, solo script): carga los
--  modulos de la Senal de Pal, la Lluvia de escombros y el Planeta sobrecargado
--  (al cargarlos registran su tipo en map_event_types, que lee el director de
--  eventos, #24) y les da el paso de cada frame: tiempo, camara y pantalla.
--  Espera a map_seed (como el resto de directores).
--  Ver docs/aval-cup.md.
-- =====================================================================

local signal = require("map_pal_signal")
local rain = require("map_debris_rain")
local overcharged = require("map_overcharged")

local last_error = nil

local function step()
  if map_seed == nil then return end

  local dt = get_delta_time()
  local camX, camY = get_camera_position()
  local sw, sh = get_screen_size()

  signal.step(dt, camX, camY, sw, sh)
  rain.step(dt, camX, camY, sw, sh)
  overcharged.step(dt, camX, camY, sw, sh)
end

-- update() falla en silencio: se atrapa el error y se imprime una vez
function update()
  local ok, err = pcall(step)
  if not ok and err ~= last_error then
    last_error = err
    print("[event26] error: " .. tostring(err))
  end
end
