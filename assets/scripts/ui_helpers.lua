-- Utilidades compartidas por las pantallas (menu principal, game over)
local ui = {}

-- DejaVuSansMono: cada caracter mide ~0.6 del tamano de la fuente. No hay
-- binding para medir texto, asi que se centra con esa aproximacion.
local CHAR_WIDTH_RATIO = 0.6

function ui.draw_centered(y, text, fontId, fontSize, r, g, b, a)
  local w = get_window_size()
  local x = (w - #text * fontSize * CHAR_WIDTH_RATIO) / 2
  draw_text(x, y, text, fontId, r, g, b, a)
end

-- Detector de flanco: devuelve una funcion que da true solo el frame en el
-- que la accion pasa de suelta a pulsada. Arranca como "pulsada" para que
-- una tecla que sigue apretada desde la pantalla anterior no dispare nada.
function ui.edge(action)
  local was_down = true
  return function()
    local down = is_action_activated(action)
    local pressed = down and not was_down
    was_down = down
    return pressed
  end
end

return ui
