-- Foco del jugador (issue #67): un haz de 3 circulos delante del jugador, con bateria.
-- La logica pura (bateria, fuerza, geometria) vive en foco_logic.lua. El estado es global
-- (foco_state) para sobrevivir a los cambios de escena; las luces del motor se borran en
-- cada carga, asi que `ids` se reinicia en init() y se recrean al vuelo en tick().
local logic = require("foco_logic")

foco_state = foco_state or logic.new()
local st = foco_state

local M = {}

local ids = nil -- ids de las 3 luces del haz (nil = no creadas en esta escena)

-- Al cargar la escena: las luces del motor ya no existen
function M.init()
  ids = nil
end

-- Enciende o apaga el foco. Sin bateria no enciende: devuelve false y el motivo
function M.toggle()
  logic.toggle(st)
  if st.battery <= 0 then return false, "Sin bateria" end
  return true
end

function M.recharge()
  logic.recharge(st)
end

function M.is_on()
  return st.on
end

function M.level()
  return logic.level(st)
end

-- Cada frame: gasta bateria y coloca el haz delante del jugador
function M.tick(dt)
  logic.drain(st, dt)
  if st.on and player_entity and player_walker then
    if ids == nil then
      ids = {}
      for i = 1, 3 do
        ids[i] = add_light(0, 0, 10, 255, 240, 200, 0)
      end
    end
    -- Centro de los pies (muneco 24x38, caja de pies en 5,28 de 14x8)
    local px, py = get_position(player_entity)
    local fx, fy = px + 12, py + 32
    local beam = logic.beam(player_walker:get_facing())
    local s = logic.strength(st)
    for i, b in ipairs(beam) do
      set_light(ids[i], { x = fx + b.dx, y = fy + b.dy, radius = b.r, intensity = 0.9 * b.k * s })
    end
  end
  if not st.on and ids then
    for _, id in ipairs(ids) do remove_light(id) end
    ids = nil
  end
end

-- Barra de bateria abajo a la izquierda. Oculta cuando esta llena y apagada
function M.draw_hud()
  local level = logic.level(st)
  if not st.on and level >= 1 then return end
  local _, sh = get_screen_size()
  draw_text(6, sh - 18, "FOCO", "default", 255, 255, 255, 255)
  draw_rect(6, sh - 10, 40, 5, 0, 0, 0, 170, true)
  local w = logic.bar(st, 38)
  if w > 0 then
    local r, g, b = 210, 60, 60
    if level >= 0.5 then
      r, g, b = 80, 200, 90
    elseif level >= logic.LOW then
      r, g, b = 230, 200, 60
    end
    draw_rect(7, sh - 9, w, 3, r, g, b, 255, true)
  end
end

return M
