-- Logica pura de pistas de boca en boca (issue #69): reglas `next`, grafo, alcanzabilidad,
-- claves de flags, marcadores y compuertas. Sin motor, sin os ni io. leads.lua hace de pegamento.
-- Docs: games/quebrada/docs/leads.md
local door_logic = require("door_logic")

local M = {}
M.ROOT = "chequelo"
M.MAX_LINE = 70
local KINDS = { house = true, zone = true }

-- ---- claves de flags ----
function M.key_resolved(id) return "lead.resolved." .. id end
function M.key_rule(id) return "lead.rule." .. id end
function M.key_person(p) return "lead.person." .. p end
function M.key_unlock(k) return "unlock." .. k end
function M.key_mark(k) return "lead.mark." .. k end
function M.key_seen(k) return "lead.seen." .. k end

-- "house.chayo" -> "house", "chayo" (nil si el formato no vale)
function M.split_key(k)
  if type(k) ~= "string" then return nil end
  local kind, id = k:match("^(%a+)%.([%w_]+)$")
  if not kind or not KINDS[kind] then return nil end
  return kind, id
end
function M.valid_unlock_key(k) return M.split_key(k) ~= nil end

-- ---- reglas ----
-- Lista de reglas; acepta una sola regla suelta como atajo
function M.rules(nxt)
  if type(nxt) ~= "table" then return {} end
  if nxt[1] == nil and next(nxt) ~= nil then return { nxt } end
  return nxt
end

-- Primera regla cuyo `when` es nil o verdadero: devuelve indice, regla (o nil)
function M.pick_rule(rules, check)
  for i, r in ipairs(rules) do
    if r.when == nil or check(r.when) then return i, r end
  end
  return nil
end

-- st = { heard = bool, mission_state = string|nil, when_ok = bool|nil }
function M.should_resolve(lg, st)
  if lg.resolve_when ~= nil then return st.when_ok == true end
  if st.heard then return true end
  local ms = st.mission_state
  if lg.mission_offer and ms and ms ~= "none" and ms ~= "offered" then return true end
  return false
end

-- ---- grafo ----
-- g = { ids = {orden}, by_id = {id=leyenda}, by_teller = {teller={ids}}, dups = {ids} }
function M.build_graph(legends)
  local g = { ids = {}, by_id = {}, by_teller = {}, dups = {} }
  for _, lg in ipairs(legends) do
    local id = lg.id
    if id ~= nil then
      if g.by_id[id] then
        g.dups[#g.dups + 1] = id
      else
        g.by_id[id] = lg
        g.ids[#g.ids + 1] = id
        if lg.teller then
          local l = g.by_teller[lg.teller] or {}
          l[#l + 1] = id
          g.by_teller[lg.teller] = l
        end
      end
    end
  end
  return g
end

-- Ids de leyenda a los que apunta una regla
function M.targets(rule, g)
  if rule.legend then return g.by_id[rule.legend] and { rule.legend } or {} end
  if rule.person then return g.by_teller[rule.person] or {} end
  return {}
end

-- Aristas de una leyenda (todas las reglas, sin repetir)
function M.edges(lg, g)
  local out, seen = {}, {}
  for _, r in ipairs(M.rules(lg.next)) do
    for _, t in ipairs(M.targets(r, g)) do
      if not seen[t] then seen[t] = true; out[#out + 1] = t end
    end
  end
  return out
end

-- Conjunto de ids alcanzables desde root (BFS, sin table.*)
function M.reachable(g, root)
  local seen, q, h = {}, {}, 1
  if g.by_id[root] then seen[root] = true; q[1] = root end
  while h <= #q do
    local id = q[h]; h = h + 1
    for _, t in ipairs(M.edges(g.by_id[id], g)) do
      if not seen[t] then seen[t] = true; q[#q + 1] = t end
    end
  end
  return seen
end

-- Claves de unlock usadas por las leyendas (sin repetir, en orden)
function M.collect_unlock_keys(legends)
  local out, seen = {}, {}
  for _, lg in ipairs(legends) do
    for _, r in ipairs(M.rules(lg.next)) do
      for _, k in ipairs(r.unlocks or {}) do
        if not seen[k] then seen[k] = true; out[#out + 1] = k end
      end
    end
  end
  return out
end

-- Devuelve errors, warns (listas de texto)
function M.validate(legends, root)
  root = root or M.ROOT
  local errors, warns = {}, {}
  local function err(s) errors[#errors + 1] = s end
  local function warn(s) warns[#warns + 1] = s end
  local g = M.build_graph(legends)
  for _, id in ipairs(g.dups) do err("id repetido: " .. id) end
  for i, lg in ipairs(legends) do
    if lg.id == nil then err("leyenda #" .. i .. " sin id") end
  end
  if not g.by_id[root] then err("no existe la leyenda raiz '" .. tostring(root) .. "'") end
  for _, id in ipairs(g.ids) do
    local lg = g.by_id[id]
    local rules = M.rules(lg.next)
    local exits = false
    for i, r in ipairs(rules) do
      local tag = id .. ".next[" .. i .. "]: "
      local links = r.person ~= nil or r.legend ~= nil
      if links and (r.line == nil or r.line == "") then err(tag .. "tiene person/legend pero no line") end
      if type(r.line) == "string" and #r.line > M.MAX_LINE then
        warn(tag .. "line de " .. #r.line .. " bytes (> " .. M.MAX_LINE .. "): puede no caber en pantalla")
      end
      for _, k in ipairs(r.unlocks or {}) do
        if not M.valid_unlock_key(k) then err(tag .. "unlock invalido '" .. tostring(k) .. "' (house.<id> | zone.<id>)") end
      end
      if links then
        if #M.targets(r, g) > 0 then
          exits = true
        elseif r.pending then
          exits = true
          warn(tag .. "pendiente: nadie cuenta aun '" .. tostring(r.legend or r.person) .. "'")
        else
          err(tag .. "'" .. tostring(r.legend or r.person) .. "' no tiene leyenda (usa pending = true si aun no se graba)")
        end
      elseif not lg.final then
        err(tag .. "regla sin person/legend en una leyenda que no es final")
      end
    end
    if not exits and not lg.final then err(id .. ": callejon sin salida (sin next valido y sin final = true)") end
    local last = rules[#rules]
    if last and last.when ~= nil then warn(id .. ": la ultima regla tiene `when` (sin regla por defecto)") end
  end
  if g.by_id[root] then
    local reach = M.reachable(g, root)
    for _, id in ipairs(g.ids) do
      if not reach[id] then err(id .. ": no se alcanza desde '" .. root .. "'") end
    end
  end
  return errors, warns
end

-- ---- mapa: compuertas y marcadores ----
-- objects = map.objects de load_tmx. gates: {name, rect, properties}; markers: {key, x, y}
-- Marcador: cualquier door/gate/marker con la propiedad `lead` ("house.x" | "zone.x")
function M.index_map(objects)
  local idx = { gates = {}, markers = {} }
  for _, o in ipairs(objects or {}) do
    local p = o.properties or {}
    if o.type == "gate" and o.shape == "rect" and o.rect then
      idx.gates[#idx.gates + 1] = { name = o.name, rect = o.rect, properties = p }
    end
    local lead = p.lead
    if type(lead) == "string" and lead ~= "" and (o.type == "door" or o.type == "gate" or o.type == "marker") then
      local cx, top
      if o.rect then cx, top = o.rect.x + o.rect.w / 2, o.rect.y else cx, top = o.x, o.y end
      if cx and top then idx.markers[#idx.markers + 1] = { key = lead, x = cx, y = top } end
    end
  end
  return idx
end

-- Primera compuerta cerrada que solapa la caja de pies (nil si ninguna)
function M.first_locked_gate(gates, foot, flag_fn)
  for _, g in ipairs(gates) do
    if door_logic.rect_overlap(g.rect, foot) and door_logic.is_locked(g, flag_fn) then return g end
  end
  return nil
end

function M.marker_visible(key, has)
  return has(M.key_mark(key)) and not has(M.key_seen(key))
end

-- Vaiven (px) y opacidad pulsante del marcador
function M.marker_bob(t) return math.floor(math.sin(t * 3) + 0.5) end
function M.marker_alpha(t) return 150 + math.floor(70 * (0.5 + 0.5 * math.sin(t * 2))) end

return M
