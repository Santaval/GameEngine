-- Prueba de la logica pura de la libreta (issue #80).
-- Se corre desde la raiz del repo:
--   lua5.3 games/quebrada/tests/libreta_logic.lua
package.path = "./games/quebrada/scripts/?.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg)
  check(a == b, msg .. " (esperado " .. tostring(b) .. ", obtenido " .. tostring(a) .. ")")
end

local L = require("libreta_logic")

local flags = {}
local function has(f) return flags[f] and true or false end
local function get(f) return flags[f] end

-- pestanas
do
  eq(L.next_tab(1), 2, "next 1")
  eq(L.next_tab(3), 1, "next envuelve")
  eq(L.prev_tab(1), 3, "prev envuelve")
  eq(L.prev_tab(3), 2, "prev 3")
end

-- grabadora: solo real Y con sonido
do
  check(L.has_recorder({ kind = "real", sound = "x" }), "real con sonido")
  check(not L.has_recorder({ kind = "real" }), "real sin sonido: sin icono")
  check(not L.has_recorder({ kind = "generated", sound = "x" }), "generada: sin icono")
  check(not L.has_recorder(nil), "nil")
end

-- historias
do
  local legends = {
    chequelo = { id = "chequelo", kind = "real", sound = "story_chequelo",
                 ending_flag = "chequelo.ending",
                 endings = { stayed_home = "Te quedaste en casa", done = "Fuiste" } },
    chayo = { id = "chayo", kind = "real" },
    otra = { id = "otra", kind = "generated", sound = "s" },
  }
  local list = {
    { id = "chequelo", title = "El chequelo", teller = "Mama", summary = "s1", state = "none", progress = 0 },
    { id = "chayo", title = "La cuenta", teller = "Chayo", summary = "s2", state = "none", progress = 0 },
    { id = "otra", title = "Otra", teller = "X", summary = "s3", state = "none", progress = 0 },
  }
  -- nada encontrado: solo paginas en blanco, y siempre el mismo numero
  local e = L.story_entries(list, legends, has, get, {}, {})
  eq(#e, L.BLANK_PAGES, "sin nada: solo paginas en blanco")
  check(e[1].blank, "en blanco")

  -- empezada: aparece, con grabadora y re-escucha
  flags["story.chequelo.started"] = true
  list[1].state = "started"
  e = L.story_entries(list, legends, has, get, {}, {})
  eq(#e, 1 + L.BLANK_PAGES, "una encontrada + blancas")
  eq(e[1].id, "chequelo", "la encontrada")
  eq(e[1].status, "started", "empezada")
  check(e[1].recorder and e[1].can_replay, "grabadora y re-escucha")
  check(e[1].new, "nueva")
  eq(e[1].ending, nil, "sin final aun")

  -- escuchada + final
  flags["story.chequelo.heard"] = true
  list[1].state = "heard"
  flags["chequelo.ending"] = "stayed_home"
  e = L.story_entries(list, legends, has, get, {}, {})
  eq(e[1].status, "heard", "escuchada")
  eq(e[1].ending, "Te quedaste en casa", "final alcanzado")
  flags["chequelo.ending"] = "raro"
  e = L.story_entries(list, legends, has, get, {}, {})
  eq(e[1].ending, "raro", "final sin texto: el valor")

  -- encontrada por una pista (sin grabacion): sin grabadora ni re-escucha
  local clues = { { id = "chayo.x", text = "t", source = "chayo", n = 1 } }
  e = L.story_entries(list, legends, has, get, clues, {})
  eq(#e, 2 + L.BLANK_PAGES, "chayo encontrada por pista")
  local chayo
  for _, x in ipairs(e) do if x.id == "chayo" then chayo = x end end
  check(chayo ~= nil, "chayo presente")
  check(not chayo.recorder, "chayo: kind real pero sin sonido -> sin icono")
  check(not chayo.can_replay, "chayo: sin re-escucha")
  eq(chayo.status, "found", "chayo: encontrada")

  -- encontrada por resolverse
  flags["lead.resolved.otra"] = true
  e = L.story_entries(list, legends, has, get, {}, {})
  local otra
  for _, x in ipairs(e) do if x.id == "otra" then otra = x end end
  check(otra and not otra.recorder, "generada: sin grabadora")

  -- visto
  flags["libreta.seen.story.chequelo"] = true
  e = L.story_entries(list, legends, has, get, {}, {})
  check(not e[1].new, "ya vista")
  eq(L.status_text("heard"), "Escuchada", "texto estado")
  flags = {}
end

-- nuevo
do
  eq(L.seen_key("clue", "a.b"), "libreta.seen.clue.a.b", "seen_key")
  check(L.is_new("clue", "x", has), "nueva")
  flags["libreta.seen.clue.x"] = true
  check(not L.is_new("clue", "x", has), "vista")
  local n = L.count_new({ { kind = "clue", id = "x" }, { kind = "clue", id = "y" }, { blank = true } }, has)
  eq(n, 1, "count_new")
  flags = {}
end

-- pistas
do
  local clues = {
    { id = "chequelo.luz", text = "a", source = "chequelo" },
    { id = "chayo.cuenta", text = "b", source = "chayo" },
    { id = "chequelo.puerta", text = "c", source = "chequelo" },
    { id = "suelta", text = "d" },
  }
  local g = L.clue_groups(clues, { chequelo = "El chequelo", chayo = "La cuenta" }, has)
  eq(#g, 3, "grupos")
  eq(g[1].title, "El chequelo", "orden por primera pista")
  eq(#g[1].clues, 2, "dos pistas en chequelo")
  eq(g[2].title, "La cuenta", "segundo grupo")
  eq(g[3].title, "Otras", "sin origen")
  local rows = L.clue_rows(g)
  eq(#rows, 3 + 4, "filas = cabeceras + pistas")
  check(rows[1].header and not rows[2].header, "cabecera primero")
  check(g[1].clues[1].new, "pista nueva")
end

-- misiones
do
  local states = { chequelo = "accepted", mona = "done", vieja = "failed", x = "none", y = "rejected" }
  local outcomes = { mona = "detour" }
  local leads = { { id = "chequelo", text = "Ir donde Ña Chayo", person = "chayo", source = "chequelo" },
                  { id = "otra", text = "ya fui", person = "p" } }
  local sec = L.mission_sections(
    { "chequelo", "mona", "vieja", "x", "y" },
    function(id) return states[id] end, function(id) return outcomes[id] end,
    { chequelo = "El chequelo" }, leads, function(l) return l.id == "chequelo" end, has)
  eq(#sec.active, 1, "una activa")
  eq(sec.active[1].text, "El chequelo", "titulo")
  eq(#sec.finished, 3, "terminadas: done, failed, rejected")
  eq(#sec.recommendations, 1, "una recomendacion pendiente")
  eq(sec.recommendations[1].text, "Ir donde Ña Chayo", "texto de la pista")
  local rows = L.mission_rows(sec)
  eq(#rows, 3 + 1 + 1 + 3, "filas con 3 cabeceras")
  check(rows[1].header and rows[1].text == "Activas", "cabecera activas")
  local empty = L.mission_rows({ active = {}, recommendations = {}, finished = {} })
  eq(#empty, 0, "sin secciones vacias")
  eq(L.outcome_text("done", "detour"), "Terminada: detour", "resultado")
  eq(L.outcome_text("failed", nil, "failed"), "Fallida: failed", "resultado por final")
  eq(L.outcome_text("done", nil, nil), "Terminada", "sin resultado")
  eq(L.outcome_text("done", nil, true), "Terminada", "final true no se muestra")
end

-- seleccion saltando cabeceras
do
  local rows = { { header = true }, { id = 1 }, { id = 2 }, { header = true }, { id = 3 } }
  eq(L.first_selectable(rows), 2, "primero seleccionable")
  eq(L.step_selection(rows, 2, 1), 3, "abajo")
  eq(L.step_selection(rows, 3, 1), 5, "abajo salta cabecera")
  eq(L.step_selection(rows, 5, 1), 5, "abajo en el final")
  eq(L.step_selection(rows, 2, -1), 2, "arriba no entra a la cabecera")
  eq(L.step_selection(rows, 5, -1), 3, "arriba salta cabecera")
  eq(L.step_selection({}, 1, 1), 0, "vacia")
  eq(L.first_selectable({ { header = true } }), 0, "solo cabeceras")
end

-- destello
do
  local a = L.sparkle(1.5, 6, 100, 40, 7)
  local b = L.sparkle(1.5, 6, 100, 40, 7)
  eq(#a, 6, "n puntos")
  for i, p in ipairs(a) do
    eq(p.x, b[i].x, "determinista x")
    check(p.x >= 0 and p.x < 100 and p.y >= 0 and p.y < 40, "dentro")
    check(p.a >= 0 and p.a <= 1, "alfa en rango")
  end
  local c = L.sparkle(1.5, 6, 100, 40, 8)
  local diff = false
  for i, p in ipairs(a) do if p.x ~= c[i].x or p.y ~= c[i].y then diff = true end end
  check(diff, "otra semilla, otros puntos")
end

if failures > 0 then print(failures .. " fallos"); os.exit(1) end
print("libreta_logic: todo OK")
