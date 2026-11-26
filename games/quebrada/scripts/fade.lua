-- Fundido a negro (issue #62): pegamento sobre door_logic.new_fade. El motor no
-- tiene primitiva de fundido, asi que se dibuja un rect negro a pantalla completa
-- con alpha; hay que llamar a draw() el ultimo para que quede por encima.
--
-- Como load_scene es diferido, el negro debe mantenerse (estado "black") en el
-- frame que pide la carga; la escena nueva empieza con set_black() y luego
-- start_in() para que el primer frame ya sea alpha 255 (sin destello).
local logic = require("door_logic")

local M = {}

local f = logic.new_fade({ out_time = 0.3, in_time = 0.3, hold = 0.05 })
local on_done = nil
local on_in_done = nil

-- Funde a negro; on_done se llama una vez, ya con la pantalla negra
function M.start_out(cb)
  on_done = cb
  logic.fade_start_out(f)
end

-- Empieza a aclarar desde alpha 255; cb (opcional) se llama al terminar
function M.start_in(cb)
  on_in_done = cb
  logic.fade_start_in(f)
end

-- Pantalla negra de inmediato (primer frame de una escena que llega con fundido)
function M.set_black()
  logic.fade_set_black(f)
end

function M.is_active()
  return f.state ~= "idle"
end

function M.alpha()
  return logic.fade_alpha(f)
end

function M.update(dt)
  local _, event = logic.fade_step(f, dt)
  if event == "out_done" and on_done then
    local cb = on_done
    on_done = nil
    cb()
  elseif event == "in_done" and on_in_done then
    local cb = on_in_done
    on_in_done = nil
    cb()
  end
end

function M.draw()
  local a = logic.fade_alpha(f)
  if a <= 0 then return end
  local w, h = get_screen_size()
  draw_rect(0, 0, w, h, 0, 0, 0, a, true)
end

return M
