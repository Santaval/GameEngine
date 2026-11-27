-- Triggers de mapa (issue #78). Pegamento entre el controlador y triggers_logic:
--   triggers.init(map)     en la carga del mapa
--   triggers.tick(foot)    cada frame con la caja de pies del jugador
--   triggers.say = fn(text)  frase que se muestra al disparar (la pone el controlador)
-- Los handlers de cada trigger viven en DEFS[mission][id] = { on_enter, on_exit }.
-- Un mapa sin objetos class="trigger" no hace nada. Docs: games/quebrada/docs/zona1.md
local ws = require("world_state")
local missions = require("missions")
local logic = require("triggers_logic")

local M = {}

M.DEFS = { chequelo = require("chequelo_triggers") }
M.say = nil
-- Triggers que debe tener un mapa que use la mision del chequelo (solo se avisa, no falla)
M.REQUIRED = { chequelo = { "walk_start", "road", "light_appears", "detour_cafetal", "detour_door", "house_arrival" } }

local groups, order, st = {}, {}, nil

function M.init(map)
  groups, order = logic.group(logic.index(map and map.objects))
  st = logic.new_state()
  if #order == 0 then return end
  local mission_of = {}
  for _, id in ipairs(order) do
    local m = groups[id].props.mission
    if m and m ~= "" then mission_of[m] = true end
    if m and m ~= "" and not M.DEFS[m] then
      print("[triggers] ERROR: el trigger '" .. id .. "' usa la mision '" .. m .. "' sin handlers")
    end
  end
  for m in pairs(mission_of) do
    for _, e in ipairs(logic.validate(groups, M.REQUIRED[m])) do print("[triggers] ERROR: " .. e) end
  end
end

local function run(fn, g)
  if not fn then return end
  local ok, e = pcall(fn, g)
  if not ok then print("[triggers] el handler de '" .. g.id .. "' fallo: " .. tostring(e)) end
end

function M.tick(foot)
  if not st or #order == 0 then return end
  local events = logic.step(st, groups, order, foot, function(g)
    return logic.condition_ok(g, ws.has, missions.state)
  end)
  for _, ev in ipairs(events) do
    local g = ev.group
    local defs = M.DEFS[g.props.mission]
    local h = defs and defs[g.id]
    if ev.kind == "enter" then
      run(h and h.on_enter, g)
      for _, f in ipairs(logic.split_flags(g.props.sets)) do ws.set(f, true) end
      local text = g.props.line
      if text and text ~= "" and M.say then M.say(text) end
    else
      run(h and h.on_exit, g)
    end
    print("[triggers] " .. ev.kind .. " " .. g.id)
  end
end

return M
