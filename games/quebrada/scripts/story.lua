-- Historias narradas (issue #68). Docs: games/quebrada/docs/stories.md
-- Reproduce la grabacion COMPLETA (sin cortes ni sincronia) en el bus `voice`,
-- con un overlay de reproductor, y dispara pistas guardadas en la libreta.
local logic = require("story_logic")
local dlogic = require("dialogue_logic")
local ws = require("world_state")
local missions = require("missions")
local libreta = require("libreta")
local interaction = require("interaction")
local dialogue = require("dialogue")

-- GLOBAL: la sesion de reproduccion sobrevive a la recarga de modulos
story_state = story_state or { sess = nil }
local st = story_state

local M = {}
M.FONT = "default"
M.FADE_MS = 150
M.legends = {}  -- id -> leyenda
M.order = {}    -- ids en orden de carga

local was = { pause = false, stop = false }
local clue_q, clue_cur, clue_left = {}, nil, 0

function M.define(def)
  if type(def) ~= "table" or not def.id or not def.sound then
    print("[story] leyenda invalida (falta id o sound)")
    return
  end
  if M.legends[def.id] == nil then M.order[#M.order + 1] = def.id end
  M.legends[def.id] = def
end

for _, def in ipairs(require("legend_index")) do M.define(def) end

local function held(a, b)
  return is_action_activated(a) or (b ~= nil and is_action_activated(b)) or false
end

local function say(t)
  if interaction.say then interaction.say(t) else print("[story] " .. t) end
end

-- ---- estado persistente (world_state) ----
function M.state(id)
  if ws.has(logic.key(id, "heard")) then return "heard" end
  if ws.has(logic.key(id, "started")) then return "started" end
  return "none"
end

function M.progress(id) return ws.get(logic.key(id, "progress"), 0) end

-- Guarda la fraccion alcanzada. Devuelve true si la historia acaba de pasar a "heard".
-- Nunca se llama por frame: solo al cruzar el umbral, pausar, parar o terminar.
local function commit(id, frac)
  local lg = M.legends[id]
  if not lg then return false end
  local s = logic.status(frac, logic.heard_at(lg))
  local rounded = math.floor(frac * 100 + 0.5) / 100
  if rounded > M.progress(id) then ws.set(logic.key(id, "progress"), rounded) end
  if s ~= "none" and not ws.has(logic.key(id, "started")) then
    ws.set(logic.key(id, "started"), true)
  end
  if s == "heard" and not ws.has(logic.key(id, "heard")) then
    ws.set(logic.key(id, "heard"), true)
    if lg.on_heard then
      local ok, err = pcall(lg.on_heard, id)
      if not ok then print("[story] on_heard fallo: " .. tostring(err)) end
    end
    return true
  end
  return false
end

-- ---- disponibilidad ----
function M.available(id)
  local lg = M.legends[id]
  if not lg then return false end
  return logic.can_listen(M.state(id), missions.check(lg.requires), st.sess ~= nil, lg.repeatable)
end

function M.is_open() return st.sess ~= nil end

-- Llamar en cada carga de escena: conecta los ganchos de interaction
function M.attach()
  interaction.story_available = function(id) return M.available(id) end
  interaction.on_story = function(id) M.listen(id) end
end

-- Llamar en cada carga de escena (tras interaction.clear): load_scene detuvo todos los
-- sonidos, asi que una sesion vieja tiene el handle muerto. Se guarda su progreso.
function M.reset()
  if st.sess then
    commit(st.sess.id, st.sess.frac)
    st.sess = nil
  end
  clue_q, clue_cur, clue_left = {}, nil, 0
  if ws.has("story.open") then ws.set("story.open", false) end
end

-- ---- entrada del jugador ----
local function lock_input(s)
  if not player_walker then return end
  local stub = function() return 0, 0, false end
  s.saved = { fn = player_walker.input, stub = stub }
  player_walker.input = stub
end

local function unlock_input(s)
  if s.saved and player_walker and player_walker.input == s.saved.stub then
    player_walker.input = s.saved.fn
  end
  s.saved = nil
end

-- ---- flujo: saludo (dialogo) y luego grabacion ----
function M.listen(id)
  local lg = M.legends[id]
  if not lg or st.sess then return end
  if lg.mission_offer then missions.offer(lg.mission_offer) end
  local greeted = logic.key(id, "greeted")
  if lg.greeting and #lg.greeting > 0 and not ws.has(greeted) then
    ws.set(greeted, true)
    -- Si todas las lineas se filtran, start() ya ejecuto on_end (y por tanto play)
    dialogue.start(lg.greeting, { on_end = function() M.play(id) end })
    return
  end
  M.play(id)
end

function M.play(id)
  local lg = M.legends[id]
  if not lg or st.sess then return false end
  local ok, handle = pcall(play_sound, lg.sound, { bus = "voice" })
  if not ok or not handle or handle == 0 then
    say("No se pudo reproducir la grabación.")
    return false
  end
  -- La duracion se pide con la voz activa: un stream solo se decodifica una vez
  local dur = sound_duration(lg.sound) or 0
  st.sess = { id = id, handle = handle, dur = dur, pos = 0, frac = 0,
              state = logic.next_state("idle", "start"), newly = false }
  -- Flancos sembrados con el estado actual: la tecla que abrio no cuenta
  was.pause, was.stop = held("story_pause"), held("story_stop", "story_stop_alt")
  ws.set("story.open", true)
  lock_input(st.sess)
  return true
end

local function concat(a, b)
  local out = {}
  for _, l in ipairs(a or {}) do out[#out + 1] = l end
  for _, l in ipairs(b or {}) do out[#out + 1] = l end
  return out
end

-- reason: "stopped" (el jugador), "ended" (fin natural), "lost" (handle muerto)
local function close(reason)
  local s = st.sess
  if not s then return end
  if reason == "ended" then s.frac = 1 end
  local newly = commit(s.id, s.frac) or s.newly
  if reason == "stopped" then
    -- Un canal en pausa no termina un fundido: se corta en seco
    local fade = (s.state == "paused") and 0 or M.FADE_MS
    pcall(stop_sound, s.handle, fade)
  end
  unlock_input(s)
  ws.set("story.open", false)
  st.sess = nil
  local lg = M.legends[s.id]
  if lg and reason ~= "lost" and (newly or reason == "ended") then
    local script = concat(lg.closing, lg.recommendations)
    if #script > 0 then dialogue.start(script) end
  end
end

-- ---- dibujo del overlay (mismo estilo que F3 / dialogo) ----
local function measure(t)
  local w = measure_text(t, M.FONT)
  return w
end

local function draw(s)
  local lg = M.legends[s.id]
  local sw, sh = get_screen_size()
  local lh = get_line_height(M.FONT)
  if not lh or lh <= 0 then lh = 12 end
  local pad = 8
  local x, w = 32, sw - 64
  local lines = {}
  if lg.summary and lg.summary ~= "" then
    lines = dlogic.wrap(lg.summary, w - 2 * pad, measure)
  end
  local nl = #lines
  if nl > 6 then nl = 6 end
  local h = pad + lh + lh + 4 + nl * lh + 8 + 10 + lh + lh + pad
  local y = math.floor((sh - h) / 2)
  draw_rect(x, y, w, h, 10, 10, 20, 240, true)
  draw_rect(x, y, w, h, 235, 225, 200, 255, false)
  draw_rect(x + 2, y + 2, w - 4, h - 4, 110, 100, 95, 255, false)

  local cy = y + pad
  draw_text(x + pad, cy, lg.teller_name or lg.teller or "", M.FONT, 255, 220, 80, 255)
  cy = cy + lh
  draw_text(x + pad, cy, lg.title or lg.id, M.FONT, 255, 255, 255, 255)
  cy = cy + lh + 4
  for i = 1, nl do
    draw_text(x + pad, cy, lines[i], M.FONT, 190, 185, 200, 255)
    cy = cy + lh
  end
  cy = cy + 8

  -- Barra de progreso con una marca en el umbral de "escuchada"
  local bx, bw, bh = x + pad, w - 2 * pad, 8
  draw_rect(bx, cy, bw, bh, 40, 36, 60, 255, true)
  local fill = logic.bar_fill(bw, s.frac)
  if fill > 0 then draw_rect(bx, cy, fill, bh, 255, 220, 80, 255, true) end
  draw_rect(bx, cy, bw, bh, 235, 225, 200, 255, false)
  draw_rect(bx + math.floor(bw * logic.heard_at(lg)), cy - 2, 1, bh + 4, 120, 220, 140, 255, true)
  cy = cy + 10

  local label = logic.fmt_time(s.pos) .. " / " .. logic.fmt_time(s.dur) .. "  " .. logic.percent(s.frac) .. "%"
  draw_text(bx, cy, label, M.FONT, 255, 255, 255, 255)
  local status = (s.state == "paused") and "En pausa" or "Escuchando"
  if ws.has(logic.key(s.id, "heard")) then status = status .. " - escuchada" end
  draw_text(bx + bw - measure(status), cy, status, M.FONT, 255, 220, 80, 255)
  cy = cy + lh
  local hint = "Retroceso / Q: detener"
  if pause_sound then hint = "Espacio: pausa / reanudar   " .. hint end
  draw_text(bx, cy, hint, M.FONT, 150, 150, 160, 255)
end

-- Overlay por frame (llamar despues de dialogue.update)
function M.update(dt)
  local s = st.sess
  if not s then return end
  local pd, sd = held("story_pause"), held("story_stop", "story_stop_alt")
  local p_edge, s_edge = pd and not was.pause, sd and not was.stop
  was.pause, was.stop = pd, sd

  if s_edge then close("stopped"); return end

  if not is_playing(s.handle) then
    -- Fin natural o handle perdido (load_scene detiene todos los sonidos)
    if logic.is_natural_end(s.pos, s.dur) then close("ended") else close("lost") end
    return
  end

  if p_edge and pause_sound then
    local ev = (s.state == "playing") and "pause" or "resume"
    local to = logic.next_state(s.state, ev)
    if to then
      if ev == "pause" then pause_sound(s.handle); commit(s.id, s.frac)
      else resume_sound(s.handle) end
      s.state = to
    end
  end

  if s.state == "playing" then
    local pos = sound_position(s.handle)
    if pos then
      s.pos = pos
      s.frac = logic.fraction(pos, s.dur)
      if not ws.has(logic.key(s.id, "heard")) and s.frac >= logic.heard_at(M.legends[s.id]) then
        if commit(s.id, s.frac) then s.newly = true end
      end
    end
  end
  draw(s)
end

-- ---- pistas ----
-- ctx = { x, y, zone, time, map, hidden }. Con hidden no se evalua (la pista no se pierde)
function M.tick(dt, ctx)
  if clue_cur and not ctx.hidden then
    clue_left = clue_left - dt
    if clue_left <= 0 then clue_cur = nil end
  end
  if not clue_cur then
    local nxt = logic.queue_pop(clue_q)
    if nxt then clue_cur, clue_left = nxt, logic.CLUE_TIME end
  end
  if ctx.hidden then return end
  local c2 = { x = ctx.x, y = ctx.y, zone = ctx.zone, time = ctx.time, map = ctx.map,
               check = missions.check }
  for _, lid in ipairs(M.order) do
    for _, clue in ipairs(M.legends[lid].clues or {}) do
      local cid = logic.clue_id(lid, clue.id)
      if not libreta.has_clue(cid) and logic.has_trigger(clue) and logic.clue_matches(clue, c2) then
        if libreta.add_clue(cid, clue.text, lid) then logic.queue_push(clue_q, clue.text) end
      end
    end
  end
end

function M.clue_text() return clue_cur end

-- Para la libreta: [{ id, title, teller, summary, state, progress }]
function M.list()
  local out = {}
  for _, id in ipairs(M.order) do
    local lg = M.legends[id]
    out[#out + 1] = { id = id, title = lg.title, teller = lg.teller_name or lg.teller,
                      summary = lg.summary, state = M.state(id), progress = M.progress(id) }
  end
  return out
end

return M
