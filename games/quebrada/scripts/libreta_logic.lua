-- Logica pura de la libreta (issue #80). Sin motor: ni dibujo ni sonido.
-- Docs: games/quebrada/docs/libreta.md
-- Arma las entradas de las 3 pestanas a partir de datos ya existentes (historias, pistas,
-- misiones) y lleva la cuenta de lo "Nuevo" con flags libreta.seen.<tipo>.<id>.
local M = {}

M.TABS = { "historias", "pistas", "misiones" }
M.TAB_NAMES = { historias = "Historias", pistas = "Pistas", misiones = "Misiones" }

-- Paginas en blanco al final de Historias: numero fijo, NUNCA derivado de cuantas
-- leyendas faltan (la coleccion esta abierta y no se dice cuantas hay)
M.BLANK_PAGES = 2

M.STATE_TEXT = {
  offered = "Ofrecida", accepted = "En curso", night_active = "En curso",
  done = "Terminada", failed = "Fallida", rejected = "Rechazada",
}

function M.next_tab(i) return (i % #M.TABS) + 1 end
function M.prev_tab(i) return ((i - 2) % #M.TABS) + 1 end

-- ---- "Nuevo" ----
function M.seen_key(kind, id) return "libreta.seen." .. kind .. "." .. id end
function M.is_new(kind, id, has) return not has(M.seen_key(kind, id)) end

-- Cuantas entradas (con id y tipo) no se han visto
function M.count_new(entries, has)
  local n = 0
  for _, e in ipairs(entries) do
    if e.kind and e.id and M.is_new(e.kind, e.id, has) then n = n + 1 end
  end
  return n
end

-- ---- Historias ----

-- Icono de grabadora: solo en grabaciones reales (kind real Y con sonido)
function M.has_recorder(lg)
  return lg ~= nil and lg.kind == "real" and lg.sound ~= nil
end

-- Una leyenda esta encontrada si se empezo a oir, se resolvio o dejo una pista
function M.discovered(id, has, sources)
  return has("story." .. id .. ".started") or has("story." .. id .. ".heard")
      or has("lead.resolved." .. id) or (sources and sources[id]) or false
end

-- Final alcanzado: legend.ending_flag (flag con el valor) y legend.endings (valor -> texto)
function M.ending_text(lg, get)
  if not lg or not lg.ending_flag then return nil end
  local v = get(lg.ending_flag)
  if v == nil or v == false then return nil end
  local map = lg.endings or {}
  return map[tostring(v)] or (type(v) == "string" and v or nil)
end

-- list: story.list(); legends: id -> definicion; clues/leads: libreta.clues()/leads()
-- Devuelve solo las encontradas, mas M.BLANK_PAGES paginas en blanco (blank = true)
function M.story_entries(list, legends, has, get, clues, leads)
  local sources = {}
  for _, c in ipairs(clues or {}) do if c.source then sources[c.source] = true end end
  for _, l in ipairs(leads or {}) do if l.source then sources[l.source] = true end end
  local out = {}
  for _, s in ipairs(list) do
    if M.discovered(s.id, has, sources) then
      local lg = legends[s.id]
      local heard = s.state == "heard"
      local recorder = M.has_recorder(lg)
      out[#out + 1] = {
        kind = "story", id = s.id, title = s.title or s.id, teller = s.teller,
        summary = s.summary or "",
        status = (heard and "heard") or (s.state == "started" and "started") or "found",
        progress = s.progress or 0,
        ending = M.ending_text(lg, get),
        recorder = recorder,
        can_replay = recorder and (heard or s.state == "started"),
        new = M.is_new("story", s.id, has),
      }
    end
  end
  for i = 1, M.BLANK_PAGES do out[#out + 1] = { blank = true, id = "blank" .. i } end
  return out
end

function M.status_text(status)
  if status == "heard" then return "Escuchada" end
  if status == "started" then return "Empezada" end
  return "Encontrada"
end

-- ---- Pistas ----

-- Agrupa por leyenda de origen, en orden de la primera pista de cada grupo.
-- Devuelve { { source, title, clues = { {id, text, new} } } }. Sin origen: grupo "Otras"
function M.clue_groups(clues, titles, has)
  local groups, by = {}, {}
  for _, c in ipairs(clues) do
    local key = c.source or "_otras"
    local g = by[key]
    if not g then
      g = { source = c.source, title = (c.source and titles[c.source]) or (c.source and c.source) or "Otras",
            clues = {} }
      by[key] = g
      groups[#groups + 1] = g
    end
    g.clues[#g.clues + 1] = { kind = "clue", id = c.id, text = c.text,
                              new = M.is_new("clue", c.id, has) }
  end
  return groups
end

-- Lista plana de filas para dibujar/seleccionar: cabeceras y pistas
function M.clue_rows(groups)
  local rows = {}
  for _, g in ipairs(groups) do
    rows[#rows + 1] = { header = true, text = g.title }
    for _, c in ipairs(g.clues) do rows[#rows + 1] = c end
  end
  return rows
end

-- ---- Misiones ----

-- ids: ids de mision; state_of(id); outcome_of(id) -> texto o nil; titles: id -> titulo
-- leads: libreta.leads(); pending(lead) -> bool (aun no se fue a donde dice)
-- Devuelve { active, recommendations, finished }, cada una lista de { kind, id, text, ... }
function M.mission_sections(ids, state_of, outcome_of, titles, leads, pending, has)
  local active, finished, recs = {}, {}, {}
  for _, id in ipairs(ids) do
    local s = state_of(id)
    local title = (titles and titles[id]) or id
    if s == "accepted" or s == "night_active" then
      active[#active + 1] = { kind = "mission", id = id, text = title, state = s,
                              new = M.is_new("mission", id, has) }
    elseif s == "done" or s == "failed" or s == "rejected" then
      finished[#finished + 1] = { kind = "mission", id = id, text = title, state = s,
                                  outcome = outcome_of(id),
                                  new = M.is_new("mission", id, has) }
    end
  end
  for _, l in ipairs(leads or {}) do
    if pending(l) then
      recs[#recs + 1] = { kind = "lead", id = l.id, text = l.text, person = l.person,
                          new = M.is_new("lead", l.id, has) }
    end
  end
  return { active = active, recommendations = recs, finished = finished }
end

-- Filas planas con cabeceras de seccion (las secciones vacias no se muestran)
function M.mission_rows(sec)
  local rows = {}
  local function add(title, list)
    if #list == 0 then return end
    rows[#rows + 1] = { header = true, text = title }
    for _, e in ipairs(list) do rows[#rows + 1] = e end
  end
  add("Activas", sec.active)
  add("Por hacer", sec.recommendations)
  add("Terminadas", sec.finished)
  return rows
end

-- Texto del resultado de una mision terminada (outcome del flag, o el final de la leyenda)
function M.outcome_text(state, outcome, ending)
  local o = outcome or ending
  local base = M.STATE_TEXT[state] or tostring(state)
  if o ~= nil and o ~= true and o ~= "" then return base .. ": " .. tostring(o) end
  return base
end

-- ---- seleccion ----
-- Siguiente indice seleccionable (salta cabeceras y paginas en blanco). dir = 1 | -1
function M.step_selection(rows, sel, dir)
  local n = #rows
  if n == 0 then return 0 end
  local i = sel
  for _ = 1, n do
    i = i + dir
    if i < 1 or i > n then return sel end
    if not rows[i].header then return i end
  end
  return sel
end

-- Primer indice seleccionable (0 si no hay)
function M.first_selectable(rows)
  for i, r in ipairs(rows) do if not r.header then return i end end
  return 0
end

-- ---- destello ----
-- n puntos deterministas dentro de w x h; a (0..1) titila con t. Sin motor ni random()
function M.sparkle(t, n, w, h, seed)
  local out = {}
  seed = seed or 1
  for i = 1, n do
    local hsh = (seed * 73856093 + i * 19349663) % 1000003
    local x = hsh % math.max(1, w)
    local y = math.floor(hsh / 7) % math.max(1, h)
    local phase = (hsh % 628) / 100
    local a = 0.5 + 0.5 * math.sin(t * 5 + phase)
    out[#out + 1] = { x = x, y = y, a = a }
  end
  return out
end

return M
