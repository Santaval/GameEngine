-- Rects fijos de la caminata de vuelta a casa (mision volver_casa): sin motor, para poder probarlos.
-- Posiciones: CENTRO DE LOS PIES del jugador (px + 12, py + 32) en px de mundo.
--   BAND  franja de la entrada de los Caliles (x 7680-7744 es la calle `caliles_calle`; se ensancha para
--         cubrir la acera norte y la calle entera, y que no se pueda cruzar sin toparse con el simio)
--   HOME  llegada a la puerta de mama (el mismo rect que la house_arrival del chequelo)
local M = {}

M.BAND = { x = 7648, y = 1776, w = 128, h = 200 }
M.HOME = { x = 8984, y = 2012, w = 64, h = 44 }

local function inside(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

function M.in_band(fx, fy) return inside(fx, fy, M.BAND) end
function M.in_home(fx, fy) return inside(fx, fy, M.HOME) end

return M
