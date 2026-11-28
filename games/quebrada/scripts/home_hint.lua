-- Guia de regreso a casa de la noche del chequelo: mensaje al empezar la noche y flecha que
-- apunta a la puerta de mama (door_mama) mientras la mision sigue en curso (night_active, sin llegar).
-- tick(dt, idx) lo llama el controlador (cfg.on_tick) con el indice del mapa; no usa estado propio del save.
local ws = require("world_state")
local missions = require("missions")
local tod = require("time_of_day")

local M = {}
M.MESSAGE = "Volvé a casa, mijo. Seguí la luz."
M.MESSAGE_VOLVER = "Volvé a casa por la calle principal."
M.MESSAGE_TIME = 8    -- s que se muestra el mensaje (desde que termina la tarjeta de hora)
M.NEAR = 90           -- px a la puerta: ya no hace falta la flecha lateral
M.ORBIT = 34          -- px del jugador a la flecha
M.FEET = { x = 12, y = 19 } -- centro del muneco 24x38 respecto de su origen

local shown = 0
local clock = 0

-- Noche del chequelo (church -> casa de mama)
local function chequelo_active()
  return missions.state("chequelo") == "night_active" and not ws.has("chequelo.arrived")
end

-- Volver a casa tras pagar a Doña Maria (walkback.lua); no durante la pelea con el simio
local function volver_active()
  if missions.state("volver_casa") ~= "accepted" then return false end
  local ok, simio = pcall(require, "simio")
  return not (ok and simio.is_fighting())
end

function M.active() return chequelo_active() or volver_active() end

local function current_message()
  if chequelo_active() then return M.MESSAGE end
  return M.MESSAGE_VOLVER
end

local function door_target(idx)
  for _, d in ipairs((idx and idx.doors) or {}) do
    if d.name == "door_mama" then return d.rect.x + d.rect.w / 2, d.rect.y end
  end
end

local function draw_message(text)
  local sw = get_screen_size()
  local w = #text * 6 + 16
  local x = math.floor((sw - w) / 2)
  draw_rect(x, 50, w, 16, 10, 10, 20, 210, true)
  draw_rect(x, 50, w, 16, 235, 225, 200, 255, false)
  draw_text(x + 8, 53, text, "default", 255, 230, 140, 255)
end

function M.tick(dt, idx)
  clock = clock + dt
  if not M.active() then shown = 0; return end
  if tod.is_busy() then return end
  local tx, ty = door_target(idx)
  if not tx or not player_entity then return end
  if shown < M.MESSAGE_TIME then
    shown = shown + dt
    draw_message(current_message())
  end
  local px, py = get_position(player_entity)
  px, py = px + M.FEET.x, py + M.FEET.y
  local dx, dy = tx - px, ty - py
  local bob = math.floor(math.sin(clock * 5) * 2 + 0.5)
  if dx * dx + dy * dy < M.NEAR * M.NEAR then
    draw_text_world(tx - 3, ty - 22 + bob, "v", "default", 255, 220, 80, 255)
    return
  end
  local len = math.sqrt(dx * dx + dy * dy)
  local ux, uy = dx / len, dy / len
  local ch
  if math.abs(dx) > math.abs(dy) then ch = dx > 0 and ">" or "<" else ch = dy > 0 and "v" or "^" end
  draw_text_world(px + ux * M.ORBIT - 3 + (ux * bob), py + uy * M.ORBIT - 6 + (uy * bob), ch, "default", 255, 220, 80, 255)
end

return M
