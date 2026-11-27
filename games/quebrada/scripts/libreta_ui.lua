-- Pantalla de la libreta (issue #80). Docs: games/quebrada/docs/libreta.md
-- Abre con Tab / L (lo conecta town_controller). Tres pestanas: Historias, Pistas, Misiones.
-- Toda la logica de datos esta en libreta_logic.lua; aqui solo hay entrada y dibujo.
-- No pausa el ambiente: el controlador solo bloquea al jugador y las interacciones.
local ws = require("world_state")
local libreta = require("libreta")
local logic = require("libreta_logic")
local story = require("story")
local missions = require("missions")
local dlogic = require("dialogue_logic")
local mlogic = require("missions_logic")
local llogic = require("leads_logic")
local leads = require("leads")

local FONT = "default"

-- GLOBAL: sobrevive a load_scene
libreta_state = libreta_state or { open = false, tab = 1, sel = { 0, 0, 0 } }
local st = libreta_state

local M = {}
local was = {}
local clock = 0

local function held(a, b)
  return is_action_activated(a) or (b ~= nil and is_action_activated(b)) or false
end

local function edge(k, down)
  local p = down and not was[k]
  was[k] = down
  return p
end

function M.is_open() return st.open end

-- ---- datos de las pestanas ----
local function titles()
  local t = {}
  for _, s in ipairs(story.list()) do t[s.id] = s.title end
  return t
end

-- "Aun no se fue": la regla elegida de la leyenda tiene un marcador sin visitar
local function lead_pending(l)
  local lg = story.legends[l.source or l.id]
  local idx = ws.get(llogic.key_rule(l.source or l.id))
  if not lg or type(idx) ~= "number" then return false end
  local rule = llogic.rules(lg.next)[idx]
  for _, k in ipairs((rule and rule.unlocks) or {}) do
    if llogic.marker_visible(k, ws.has) then return true end
  end
  return false
end

local function build()
  local legends = story.legends
  local clues, lds = libreta.clues(), libreta.leads()
  local rows = {}
  rows[1] = logic.story_entries(story.list(), legends, ws.has, ws.get, clues, lds)
  rows[2] = logic.clue_rows(logic.clue_groups(clues, titles(), ws.has))
  local mt = {}
  local ending_of = {}
  for id, d in pairs(missions.defs) do mt[id] = d.title end
  for _, lg in pairs(legends) do
    if lg.mission_offer then ending_of[lg.mission_offer] = logic.ending_text(lg, ws.get) end
  end
  local sec = logic.mission_sections(missions.ids(), missions.state,
    function(id)
      local o = ws.get("mission." .. id .. ".outcome")
      return o ~= nil and tostring(o) or ending_of[id]
    end, mt, lds, lead_pending, ws.has)
  rows[3] = logic.mission_rows(sec)
  return rows
end

local function mark_seen(entry)
  if entry and entry.kind and entry.id and logic.is_new(entry.kind, entry.id, ws.has) then
    ws.set(logic.seen_key(entry.kind, entry.id), true)
  end
end

local function new_count(rows, tab)
  local n = 0
  for _, e in ipairs(rows[tab]) do
    if e.kind and e.id and logic.is_new(e.kind, e.id, ws.has) then n = n + 1 end
  end
  return n
end

-- ---- abrir / cerrar ----
function M.open()
  if st.open then return end
  st.open = true
  ws.set("libreta.open", true)
  local rows = build()
  was = {}
  edge("l", held("walk_left", "walk_left_alt"))
  edge("r", held("walk_right", "walk_right_alt"))
  edge("u", held("walk_up", "walk_up_alt"))
  edge("d", held("walk_down", "walk_down_alt"))
  edge("ok", held("interact", "interact_alt"))
  for t = 1, 3 do
    if st.sel[t] < 1 or st.sel[t] > #rows[t] or (rows[t][st.sel[t]] or {}).header then
      st.sel[t] = logic.first_selectable(rows[t])
    end
  end
  -- Aviso suave si hay algo nuevo
  local total = new_count(rows, 1) + new_count(rows, 2) + new_count(rows, 3)
  if total > 0 and play_sound then
    libreta.notify()
  end
end

function M.close()
  st.open = false
  if ws.has("libreta.open") then ws.set("libreta.open", false) end
end

function M.toggle()
  if st.open then M.close() else M.open() end
end

-- Al cargar una escena: la libreta no sigue abierta
function M.reset()
  st.open = false
  if ws.has("libreta.open") then ws.set("libreta.open", false) end
end

-- ---- entrada ----
-- Devuelve "replay", id cuando el jugador pide volver a oir una historia: el controlador
-- cierra la libreta, desbloquea al jugador y llama a story.play(id, { replay = true })
function M.update(dt)
  if not st.open then return nil end
  clock = clock + dt
  local rows = build()
  local tab = st.tab
  local l = edge("l", held("walk_left", "walk_left_alt"))
  local r = edge("r", held("walk_right", "walk_right_alt"))
  local u = edge("u", held("walk_up", "walk_up_alt"))
  local d = edge("d", held("walk_down", "walk_down_alt"))
  local ok = edge("ok", held("interact", "interact_alt"))

  if l then st.tab = logic.prev_tab(st.tab) end
  if r then st.tab = logic.next_tab(st.tab) end
  if st.tab ~= tab then
    tab = st.tab
    local list = rows[tab]
    if st.sel[tab] < 1 or st.sel[tab] > #list or (list[st.sel[tab]] or {}).header then
      st.sel[tab] = logic.first_selectable(list)
    end
  end

  local list = rows[tab]
  if u then st.sel[tab] = logic.step_selection(list, st.sel[tab], -1) end
  if d then st.sel[tab] = logic.step_selection(list, st.sel[tab], 1) end
  local cur = list[st.sel[tab]]
  mark_seen(cur)

  if ok and tab == 1 and cur and cur.can_replay then
    return "replay", cur.id
  end
  return nil
end

-- ---- dibujo ----
local function measure(t) return (measure_text(t, FONT)) end

local function clip(text, max_w)
  if measure(text) <= max_w then return text end
  while #text > 1 and measure(text .. "...") > max_w do
    -- recorta por caracteres UTF-8 completos
    local cut = #text - 1
    while cut > 1 and (text:byte(cut + 1) or 0) >= 0x80 and (text:byte(cut + 1) or 0) < 0xC0 do cut = cut - 1 end
    text = text:sub(1, cut)
  end
  return text .. "..."
end

-- Icono de grabadora hecho con rects (microfono de grabadora de mano)
local function recorder_icon(x, y)
  draw_rect(x + 2, y, 5, 8, 60, 55, 60, 255, true)       -- cuerpo
  draw_rect(x + 3, y + 1, 3, 3, 200, 60, 60, 255, true)  -- boton rojo
  draw_rect(x + 3, y + 5, 3, 2, 150, 150, 160, 255, true) -- rejilla
  draw_rect(x + 4, y + 8, 1, 2, 60, 55, 60, 255, true)   -- mango
end

local function sparkle(x, y, w, h, seed)
  for _, p in ipairs(logic.sparkle(clock, 4, w, h, seed)) do
    draw_rect(x + p.x, y + p.y, 1, 1, 255, 235, 150, math.floor(255 * p.a), true)
  end
end

function M.draw()
  if not st.open then return end
  local sw, sh = get_screen_size()
  local lh = get_line_height(FONT)
  if not lh or lh <= 0 then lh = 12 end
  local rows = build()
  local tab = st.tab

  -- Hoja: papel crema con lomo marron, como un cuaderno
  local px, py, pw, ph = 18, 10, sw - 36, sh - 20
  draw_rect(0, 0, sw, sh, 0, 0, 0, 120, true)
  draw_rect(px, py, pw, ph, 238, 228, 200, 255, true)
  draw_rect(px, py, 10, ph, 110, 70, 45, 255, true)
  for i = 0, 5 do draw_rect(px + 3, py + 14 + i * 40, 4, 6, 200, 190, 160, 255, true) end -- anillas
  draw_rect(px, py, pw, ph, 70, 45, 30, 255, false)

  -- Pestanas
  local tx = px + 18
  for i, name in ipairs(logic.TABS) do
    local label = logic.TAB_NAMES[name]
    local w = measure(label) + 12
    local sel = (i == tab)
    draw_rect(tx, py + 4, w, lh + 4, sel and 255 or 205, sel and 248 or 190, sel and 225 or 150, 255, true)
    draw_rect(tx, py + 4, w, lh + 4, 70, 45, 30, 255, false)
    draw_text(tx + 6, py + 6, label, FONT, 60, 40, 30, 255)
    if i ~= tab and new_count(rows, i) > 0 then
      draw_rect(tx + w - 5, py + 2, 4, 4, 220, 70, 50, 255, true)
      sparkle(tx, py + 2, w, lh + 4, 100 + i)
    end
    tx = tx + w + 4
  end
  draw_text(px + pw - 150, py + 6, "Tab/L cerrar  <- -> pestañas", FONT, 120, 100, 80, 255)

  -- Lista (izquierda) y detalle (derecha)
  local top = py + lh + 14
  local lx, lw = px + 18, 170
  local dx = lx + lw + 10
  local dw = px + pw - 10 - dx
  local list = rows[tab]
  local visible = math.floor((py + ph - 8 - top) / lh)
  local first = mlogic.window_start(st.sel[tab], #list, visible)
  draw_rect(dx - 5, top, 1, py + ph - 8 - top, 150, 130, 100, 255, false)

  if #list == 0 then
    draw_text(lx, top + 4, "Nada por aquí todavía.", FONT, 130, 110, 90, 255)
  end
  for i = first, math.min(#list, first + visible - 1) do
    local e = list[i]
    local ty = top + (i - first) * lh
    if e.blank then
      -- pagina en blanco: renglones vacios
      draw_rect(lx, ty + lh - 2, lw - 10, 1, 190, 175, 145, 255, true)
    elseif e.header then
      draw_text(lx, ty, e.text, FONT, 130, 60, 40, 255)
    else
      if i == st.sel[tab] then draw_rect(lx - 3, ty, lw, lh, 215, 190, 150, 255, true) end
      local label = e.title or e.text or ""
      if e.kind == "lead" then label = "-> " .. label end
      local tw = lw - 16 - (e.recorder and 12 or 0) - (e.new and 30 or 0)
      draw_text(lx, ty, clip(label, tw), FONT, 50, 35, 25, 255)
      local rx = lx + lw - 8
      if e.new then
        rx = rx - 28
        draw_text(rx, ty, "Nuevo", FONT, 200, 60, 40, 255)
        sparkle(rx - 2, ty - 1, 34, lh, i)
      end
      if e.recorder then recorder_icon(lx + lw - 14, ty + 1) end
    end
  end

  -- Detalle de la entrada elegida
  local cur = list[st.sel[tab]]
  local cy = top
  local function para(text, r, g, b)
    for _, ln in ipairs(dlogic.wrap(text, dw, measure)) do
      if cy + lh > py + ph - 8 then return end
      draw_text(dx, cy, ln, FONT, r, g, b, 255)
      cy = cy + lh
    end
  end
  if cur and cur.kind == "story" then
    para(cur.title, 50, 35, 25)
    if cur.teller then para("Contó: " .. cur.teller, 110, 85, 60) end
    if cur.recorder then recorder_icon(dx + dw - 12, top + 1) end
    cy = cy + 4
    para(logic.status_text(cur.status), 40, 110, 60)
    if cur.ending then para("Final: " .. cur.ending, 130, 60, 40) end
    cy = cy + 4
    para(cur.summary, 70, 55, 40)
    cy = cy + 6
    if cur.can_replay then
      para("[E] Escuchar de nuevo la grabación completa", 40, 80, 140)
    elseif cur.recorder then
      para("Aún no se ha escuchado.", 130, 110, 90)
    else
      para("Sin grabación.", 130, 110, 90)
    end
  elseif cur and cur.kind == "clue" then
    para(cur.text, 50, 35, 25)
  elseif cur and cur.kind == "mission" then
    para(cur.text, 50, 35, 25)
    cy = cy + 4
    local ending = nil
    para(logic.outcome_text(cur.state, cur.outcome, ending), 40, 110, 60)
  elseif cur and cur.kind == "lead" then
    para(cur.text, 50, 35, 25)
    if cur.person then para("Ir donde: " .. cur.person, 110, 85, 60) end
  elseif cur and cur.blank then
    para("Una página en blanco.", 150, 135, 105)
  end
end

return M
