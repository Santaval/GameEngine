-- Techos que se desvanecen y ventanas encendidas (issue #71). Pegamento entre el motor
-- y roofs_logic. Lo usa town_controller cuando el mapa se dibuja con tiles:
--   roofs.init(map)            en la carga del mapa
--   roofs.update(dt, foot)     cada frame; foot = caja de pies del jugador o nil
-- Un mapa sin objetos "roof" ni capa windows_lit no hace nada (set_* devuelve 0).
local logic = require("roofs_logic")
local tod = require("time_of_day")

local M = {}

local WINDOWS = "windows_lit"

local roofs = {}
local cur = {}   -- roof_of -> alpha actual (float)
local shown = {} -- roof_of -> ultimo entero enviado al motor
local win = 255
local win_shown = nil

local function lit_now()
  return (tod.visible("dusk,night") and not tod.blackout()) and true or false
end

function M.init(map)
  roofs = logic.index(map and map.objects)
  cur, shown = {}, {}
  for _, r in ipairs(roofs) do
    cur[r.roof_of] = 255
    shown[r.roof_of] = 255
    set_roof_alpha(r.roof_of, 255)
  end
  win = logic.window_target(lit_now())
  win_shown = win
  set_layer_alpha(WINDOWS, win)
end

function M.update(dt, foot)
  local targets = logic.targets(roofs, foot)
  for of, target in pairs(targets) do
    local v = logic.step(cur[of] or 255, target, dt, logic.ROOF_SPEED)
    cur[of] = v
    local n = math.floor(v + 0.5)
    if n ~= shown[of] then
      shown[of] = n
      set_roof_alpha(of, n)
    end
  end
  win = logic.step(win, logic.window_target(lit_now()), dt, logic.WINDOW_SPEED)
  local wn = math.floor(win + 0.5)
  if wn ~= win_shown then
    win_shown = wn
    set_layer_alpha(WINDOWS, wn)
  end
end

return M
