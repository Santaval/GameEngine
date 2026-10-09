-- =====================================================================
--  Director de la tormenta del borde (entidad invisible, solo script):
--  dibuja la banda de tormenta y su borde irregular, y aplica el dano por
--  tiempo a la nave local mientras esta dentro. Espera a map_seed (como el
--  resto de directores). Publica el global local_in_storm.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")
local storm = require("map_storm")
local ui = require("ui_helpers")

local S = cfg.STORM
local B = cfg.STORM_BAND
local W = cfg.WORLD_SIZE

local clock = 0
local dmg = storm.new_damage()
local last_error = nil

local function step()
  if map_seed == nil then return end

  local dt = get_delta_time()
  clock = clock + dt
  local camX, camY = get_camera_position()
  local sw, sh = get_screen_size()
  local frame = storm.frame(clock)

  storm.draw_fill(camX, camY, sw, sh, frame, storm.in_border)

  -- Borde irregular sobre el rectangulo interior [B, W-B]^2, lado irregular hacia dentro
  storm.draw_edge_segment(B, W - B, W - B, W - B, 0, camX, camY, sw, sh, frame)
  storm.draw_edge_segment(B, B, W - B, B, 180, camX, camY, sw, sh, frame)
  storm.draw_edge_segment(B, B, B, W - B, 90, camX, camY, sw, sh, frame)
  storm.draw_edge_segment(W - B, B, W - B, W - B, 270, camX, camY, sw, sh, frame)

  local inside = false
  if player_entity ~= nil and is_alive(player_entity) then
    local x, y = get_collider_center(player_entity)
    inside = storm.in_border(x, y)
    storm.tick_damage(dmg, player_entity, inside, dt)
  else
    dmg.acc = 0
  end
  local_in_storm = inside

  if inside then
    local ww, wh = get_window_size()
    storm.draw_tint(ww, wh, S.tint_alpha)
    ui.draw_centered(wh * 0.2, "TORMENTA", "debug-big", 28, 157, 2, 8, 255)
  end
end

-- update() falla en silencio: se atrapa el error y se imprime una vez
function update()
  local ok, err = pcall(step)
  if not ok and err ~= last_error then
    last_error = err
    print("[storm] error: " .. tostring(err))
  end
end
