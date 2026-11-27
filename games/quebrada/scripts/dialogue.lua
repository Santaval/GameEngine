-- Caja de dialogo (issue #50). Docs: games/quebrada/docs/dialogue.md
--   local h = dialogue.start(script, { on_choice = fn(idx, line, opt), on_end = fn(results) })
local logic = require("dialogue_logic")
local ws = require("world_state")
local interaction = require("interaction")

local M = {}
M.FONT = "dialogue"
M.CPS = 40            -- caracteres por segundo
M.MAX_LINES = 3       -- lineas por pagina
M.PAD = 6
M.MARGIN = 8
M.play_voices = true
M.box = nil           -- opcional: { asset = "id", slice = 8 } para caja 9-slice (solo si M.nine_slice existe)
M.scripts = require("dialogues")

local cur = nil
local time = 0

-- ---- utilidades ----
local function layout()
  local sw, sh = get_screen_size()
  local lh = get_line_height(M.FONT)
  if not lh or lh <= 0 then lh = 12 end
  local bh = M.PAD * 2 + M.MAX_LINES * lh
  return { sw = sw, sh = sh, lh = lh, x = M.MARGIN, y = sh - bh - M.MARGIN,
           w = sw - 2 * M.MARGIN, h = bh }
end

local function measure(s)
  local w = measure_text(s, M.FONT)
  return w
end

local function key2(a, b) return is_action_activated(a) or is_action_activated(b) end

local function lock_input(h)
  if not player_walker then return end
  local stub = function() return 0, 0, false end
  h.saved = { fn = player_walker.input, stub = stub }
  player_walker.input = stub
end

local function unlock_input(h)
  if h.saved and player_walker and player_walker.input == h.saved.stub then
    player_walker.input = h.saved.fn
  end
  h.saved = nil
end

local function stop_voice(h)
  if h.voice and h.voice ~= 0 then pcall(stop_sound, h.voice, 100) end
  h.voice = nil
end

-- ---- dibujo ----
local function panel(x, y, w, h)
  if M.box and M.box.asset and M.nine_slice then
    M.nine_slice(M.box.asset, x, y, w, h, M.box.slice or 8)
    return
  end
  draw_rect(x, y, w, h, 18, 14, 26, 240, true)                    -- fondo
  draw_rect(x, y, w, h, 235, 225, 200, 255, false)                -- borde exterior
  draw_rect(x + 2, y + 2, w - 4, h - 4, 110, 100, 95, 255, false) -- borde interior
end

local function draw(h)
  local L = layout()
  local line = h.line
  panel(L.x, L.y, L.w, L.h)

  if line.speaker and line.speaker ~= "" then
    local tw = measure(line.speaker) + M.PAD * 2
    local th = L.lh + 6
    panel(L.x + 8, L.y - th + 1, tw, th)
    draw_text(L.x + 8 + M.PAD, L.y - th + 4, line.speaker, M.FONT, 255, 220, 80, 255)
  end

  draw_text_wrapped(L.x + M.PAD, L.y + M.PAD, L.w - 2 * M.PAD,
    logic.visible(h.st), M.FONT, 255, 255, 255, 255)

  if h.st.phase == "wait" and math.floor(time * 2.5) % 2 == 0 then
    -- "v" en vez de un triangulo: no depender de la cobertura de glifos de la fuente
    draw_text(L.x + L.w - M.PAD - 10, L.y + L.h - M.PAD - L.lh, "v", M.FONT, 255, 255, 255, 255)
  end

  if h.st.phase == "choose" then
    local maxw = 0
    for _, o in ipairs(h.choices) do
      local w = measure(o.text)
      if w > maxw then maxw = w end
    end
    local cw = maxw + M.PAD * 2 + 12
    local ch = #h.choices * L.lh + M.PAD * 2
    local cx = L.x + L.w - cw
    local cy = L.y - ch - 2
    panel(cx, cy, cw, ch)
    for i, o in ipairs(h.choices) do
      local ty = cy + M.PAD + (i - 1) * L.lh
      if i == h.st.sel then
        draw_rect(cx + 3, ty, cw - 6, L.lh, 70, 55, 110, 255, true)
        draw_text(cx + M.PAD, ty, ">", M.FONT, 255, 220, 80, 255)
      end
      draw_text(cx + M.PAD + 12, ty, o.text, M.FONT, 255, 255, 255, 255)
    end
  end
end

-- ---- ciclo de vida ----
local function safe(fn, ...)
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok then print("[dialogue] callback fallo: " .. tostring(err)) end
end

local function finish(h)
  stop_voice(h)
  unlock_input(h)
  ws.set("dialogue.open", false)
  cur = nil
  safe(h.opts.on_end, h.results)
end

local function next_line(h)
  stop_voice(h)
  h.i = h.i + 1
  if h.i > #h.queue then finish(h); return end
  local line = h.queue[h.i]
  h.line = line
  local L = layout()
  local lines = logic.wrap(line.text or "", L.w - 2 * M.PAD, measure)
  local pages = logic.paginate(lines, M.MAX_LINES)
  h.choices = {}
  for _, c in ipairs(line.choices or {}) do
    h.choices[#h.choices + 1] = (type(c) == "string") and { text = c } or c
  end
  h.st = logic.new(pages, #h.choices, M.CPS)
  if line.voice and M.play_voices then
    local ok, handle = pcall(play_sound, line.voice, { bus = "voice" })
    if ok then h.voice = handle end
  end
end

-- Intercala el guion `extra` justo despues de la linea actual
local function splice(h, extra)
  local new = {}
  for k = 1, h.i do new[#new + 1] = h.queue[k] end
  for k = 1, #extra do new[#new + 1] = extra[k] end
  for k = h.i + 1, #h.queue do new[#new + 1] = h.queue[k] end
  h.queue = new
end

function M.start(script, opts)
  if cur then return nil end
  if type(script) ~= "table" or #script == 0 then return nil end
  local q = {}
  for k = 1, #script do q[k] = script[k] end -- copia: el dato original no se toca
  local h = { queue = q, i = 0, results = {}, opts = opts or {},
              -- sembrado con el estado actual: la E que abre no avanza la primera linea
              was_c = key2("interact", "interact_alt"),
              was_u = key2("walk_up", "walk_up_alt"),
              was_d = key2("walk_down", "walk_down_alt") }
  cur = h
  ws.set("dialogue.open", true)
  lock_input(h)
  next_line(h)
  return h
end

function M.is_open() return cur ~= nil end

-- Llamar al cargar la escena: el flag es global y sobrevive a la recarga del modulo
function M.reset()
  cur = nil
  if ws.has("dialogue.open") then ws.set("dialogue.open", false) end
end

-- Conecta interaction.on_npc con M.scripts (llamar en cada carga de escena)
function M.attach()
  interaction.on_npc = function(name, obj)
    local s = M.scripts[name]
    if s then
      M.start(s)
    elseif interaction.say then
      local p = (obj and obj.properties) or {}
      interaction.say(p.line or "...")
    end
  end
end

function M.register_script(name, script) M.scripts[name] = script end

function M.update(dt)
  if not cur then return end
  local h = cur
  time = time + dt
  local c = key2("interact", "interact_alt")
  local u = key2("walk_up", "walk_up_alt")
  local d = key2("walk_down", "walk_down_alt")
  local inp = { confirm = c and not h.was_c, up = u and not h.was_u, down = d and not h.was_d }
  h.was_c, h.was_u, h.was_d = c, u, d

  local ev, idx = logic.step(h.st, dt, inp)
  if ev == "done" then
    if h.line.set_flag then ws.set(h.line.set_flag, true) end
    next_line(h)
  elseif ev == "chosen" then
    local opt = h.choices[idx]
    h.results[#h.results + 1] = idx
    safe(h.line.on_choice, idx, opt)
    safe(h.opts.on_choice, idx, h.line, opt)
    if opt.set_flag then ws.set(opt.set_flag, true) end
    if opt.next then splice(h, opt.next) end
    next_line(h)
  end
  if cur == h and h.st then draw(h) end
end

return M
