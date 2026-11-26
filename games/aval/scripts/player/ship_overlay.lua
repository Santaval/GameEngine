-- Lo que se dibuja encima de cada nave de jugador (la local y las remotas):
-- nombre, niveles de motor/escudo/arma y barra de vida. Todo en coordenadas
-- del mundo, asi que hay que pedirlo cada frame.
local ship_overlay_module = {}

local SHIP_WIDTH = 430 * 0.2
local BAR_HEIGHT = 5
local BAR_GAP = 8
local LINE_HEIGHT = 18
-- La fuente "default" es monoespaciada de 16px: ~10px por caracter
local CHAR_WIDTH = 10

-- Un segmento por herramienta, cada uno con su color
local function draw_levels(x, y, engine, shield, gun)
  local segments = {
    { string.format("E%d", engine), 255, 160, 60 },
    { string.format("S%d", shield), 90, 200, 255 },
    { string.format("G%d", gun),    255, 90, 90 },
  }
  for _, seg in ipairs(segments) do
    draw_text_world(x, y, seg[1], "default", seg[2], seg[3], seg[4])
    x = x + (#seg[1] + 1) * CHAR_WIDTH
  end
end

-- x, y: esquina superior izquierda de la nave (lo que da get_position).
-- La barra se pone roja por debajo de un tercio
function ship_overlay_module.draw(x, y, label, label_r, label_g, label_b, hp, max_hp, engine, shield, gun)
  local ratio = max_hp > 0 and math.max(0, math.min(1, hp / max_hp)) or 0
  local bar_y = y - BAR_GAP - BAR_HEIGHT
  local fill_r, fill_g = 60, 200
  if hp * 3 < max_hp then fill_r, fill_g = 220, 60 end

  draw_rect_world(x, bar_y, SHIP_WIDTH, BAR_HEIGHT, 60, 60, 60, 200, true)
  draw_rect_world(x, bar_y, SHIP_WIDTH * ratio, BAR_HEIGHT, fill_r, fill_g, 80, 255, true)
  draw_levels(x, bar_y - LINE_HEIGHT, engine or 0, shield or 0, gun or 0)
  draw_text_world(x, bar_y - 2 * LINE_HEIGHT, label, "default", label_r, label_g, label_b)
end

return ship_overlay_module
