-- Minijuego "Quieto cuando silba" (apagon de la noche del chequelo). Logica en silbido_logic.lua.
-- Activo mientras dura el apagon (time_of_day.blackout()). Suena un silbido: hay que quedarse quieto
-- y con el foco apagado hasta que pase. Tres descuidos (guardados en chequelo.silbidos) pierden la
-- noche (missions.fail). tick(dt) lo llama el controlador (cfg.on_tick). Docs: docs/blackout.md
local ws = require("world_state")
local tod = require("time_of_day")
local dialogue = require("dialogue")
local logic = require("silbido_logic")
local blackout = require("blackout")

local M = {}
local CFG = logic.CONFIG
local st = logic.new()
local was_active = false
local last_x, last_y = nil, nil
local pick = nil
local flash, notice, notice_left = 0, "", 0

local function say(text, secs) notice, notice_left = text, secs or 3 end

local function draw_box(text, y, r, g, b)
  local sw = get_screen_size()
  local w = #text * 6 + 16
  local x = math.floor((sw - w) / 2)
  draw_rect(x, y, w, 16, 10, 10, 20, 220, true)
  draw_rect(x, y, w, 16, r, g, b, 255, false)
  draw_text(x + 8, y + 3, text, "default", r, g, b, 255)
end

local function draw_hud()
  local sw, sh = get_screen_size()
  if flash > 0 then draw_rect(0, 0, sw, sh, 120, 0, 0, math.floor(110 * math.min(1, flash / 0.6)), true) end
  if notice_left > 0 then draw_box(notice, 70, 255, 150, 130) end
  if st.phase == "whistle" then
    local msg = logic.in_grace(st, CFG) and "¡Silba! Quieto y apaga el foco" or "Quieto... y sin luz"
    draw_box(msg, 70, 255, 230, 140)
    local w = 120
    local x = math.floor((sw - w) / 2)
    draw_rect(x, 90, w, 4, 40, 36, 60, 230, true)
    draw_rect(x, 90, math.floor(w * logic.left(st)), 4, 255, 220, 80, 255, true)
  end
  -- golpes: tres cuadros arriba a la derecha
  for i = 1, CFG.max_strikes do
    local on = i <= st.strikes
    draw_rect(sw - 12 - (CFG.max_strikes - i + 1) * 10, 8, 8, 8, on and 220 or 60, on and 60 or 60, on and 60 or 70, 255, true)
  end
end

-- Sin foco no se puede andar (esta demasiado oscuro). Si la bateria se agota se deja andar a tientas:
-- si no, el jugador quedaria atrapado. player_walker.input puede ser "keyboard" (texto) o una funcion:
-- el bloqueo la sustituye por un stub y la devuelve al desbloquear (como dialogue.lua)
local STUB = function() return 0, 0, false end
local saved_input = nil

local function set_blocked(b)
  if not player_walker then return end
  if b then
    if player_walker.input ~= STUB and not dialogue.is_open() and not require("story").is_open() then
      saved_input = player_walker.input
      player_walker.input = STUB
    end
  elseif player_walker.input == STUB and saved_input ~= nil then
    player_walker.input = saved_input
    saved_input = nil
  end
end

local function foco_ready()
  local f = rawget(_G, "foco_state")
  return f ~= nil and f.on or (f ~= nil and f.battery <= 0)
end

function M.tick(dt)
  local active = tod.blackout() and not ws.has("chequelo.arrived")
  if not active then
    set_blocked(false)
    if was_active then st = logic.new(); was_active = false end
    notice_left, flash = 0, 0
    return
  end
  if not was_active then
    st = logic.new()
    st.strikes = ws.get("chequelo.silbidos", 0) or 0
    was_active, last_x, last_y = true, nil, nil
  end
  if flash > 0 then flash = flash - dt end
  if notice_left > 0 then notice_left = notice_left - dt end
  local blocked = not foco_ready()
  set_blocked(blocked)
  draw_hud()
  if blocked and st.phase ~= "whistle" and notice_left <= 0 then draw_box("Muy oscuro: prendé el foco (X)", 70, 255, 230, 140) end
  if dialogue.is_open() or tod.is_busy() or not player_entity then return end

  local px, py = get_position(player_entity)
  local moving = false
  if last_x and dt > 0 then
    local dx, dy = px - last_x, py - last_y
    moving = math.sqrt(dx * dx + dy * dy) / dt > CFG.move_speed
  end
  last_x, last_y = px, py

  pick = pick or blackout.WHISTLES[math.random(#blackout.WHISTLES)]
  local len = sound_duration and sound_duration(pick) or nil
  local light_on = rawget(_G, "foco_state") and foco_state.on or false
  local ev = logic.step(st, CFG, dt, { moving = moving, light_on = light_on,
                                       duration = logic.window(CFG, len) }, math.random)
  if ev == "start" then
    blackout.around(pick, 0.9)
    pick = nil
  elseif ev == "strike" then
    ws.set("chequelo.silbidos", st.strikes)
    flash = 0.6
    say("Te oyó... (" .. st.strikes .. "/" .. CFG.max_strikes .. ")")
  elseif ev == "fail" then
    ws.set("chequelo.silbidos", st.strikes)
    flash = 1.2
    require("missions").fail("chequelo")
  elseif ev == "pass" then
    say("El silbido pasó de largo", 2)
  end
end

return M
