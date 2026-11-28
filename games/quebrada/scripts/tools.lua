-- Herramientas en vez de armas (issue #53). Docs: games/quebrada/docs/tools.md
-- Cada herramienta es un dato (DEFS): nombre, etiqueta del HUD, color, de donde sale y su
-- unico uso. El jugador no sabe de ninguna en concreto: tools.use() ejecuta el uso generico.
-- La posesion es el flag `tool.<id>` en world_state (sobrevive a las escenas y lo guarda
-- save.lua sin cambios). Este modulo NO debe requerir missions, interaction ni
-- town_controller.
local ws = require("world_state")
local logic = require("tools_logic")
local foco = require("foco")

-- Seleccion actual: global para sobrevivir a load_scene
tools_state = tools_state or { selected = nil }
local st = tools_state

local M = {}

-- Uso de cada herramienta (use):
--   when      condicion de flags ("a,!b"); si no se cumple, no se usa y se dice `blocked`
--   blocked   texto si `when` falla (por defecto "No es para esto")
--   fn(ctx)   accion propia; devuelve (ok, mensaje). ok == false cancela el resto
--   set_flag  flag que se activa al usar (las leyendas lo leen: when = "sal.used")
--   consume   true = la herramienta se gasta (se borra su flag)
--   line      mensaje al usarla
-- El orden de la lista es el orden de la barra.
M.DEFS = {
  { id = "foco", name = "Foco", label = "FOCO", color = { 230, 200, 90 },
    source = "Linterna en la casa de mama",
    use = { fn = function() return foco.toggle() end } },
  { id = "rosario", name = "Rosario", label = "ROS", color = { 150, 110, 200 },
    source = "Lo que digan los viejos (historias)",
    use = { set_flag = "rosario.used", consume = true, line = "Rezas con el rosario." } },
  { id = "sal", name = "Sal", label = "SAL", color = { 235, 235, 235 },
    source = "Lo que digan los viejos (historias)",
    use = { set_flag = "sal.used", consume = true, line = "Tiras una linea de sal." } },
  { id = "machete", name = "Machete", label = "MACH", color = { 190, 190, 205 },
    source = "Mona y el machete",
    -- Solo sirve durante una pelea (mona.battle: lo pone simio.lua). El golpe lo resuelve simio.attack (global
    -- machete_hook); sin `line` para no repetir un mensaje en cada golpe
    use = { when = "mona.battle", blocked = "El machete no es para esto.", set_flag = "machete.used",
            fn = function()
              local hook = rawget(_G, "machete_hook")
              if not hook then return false, "El machete no es para esto." end
              return hook()
            end } },
  { id = "cables", name = "Cables", label = "CABL", color = { 210, 120, 60 },
    source = "Electrocutada",
    use = { set_flag = "cables.used", consume = true, line = "Conectas los cables." } },
}

function M.def(id)
  for _, d in ipairs(M.DEFS) do
    if d.id == id then return d end
  end
  return nil
end

function M.has(id) return ws.has(logic.flag(id)) end

-- Da una herramienta (idempotente). false si no existe la definicion
function M.give(id)
  if not M.def(id) then
    print("[tools] herramienta desconocida: " .. tostring(id))
    return false
  end
  ws.set(logic.flag(id), true)
  return true
end

function M.take(id) ws.set(logic.flag(id), nil) end

local function owned() return logic.owned(M.DEFS, ws.has) end

function M.owned() return owned() end
function M.count() return #owned() end

-- Herramienta seleccionada (def) o nil
function M.selected()
  return logic.ensure_selected(st, owned())
end

-- Tecla 1..4: selecciona la n-esima. true si cambio la seleccion
function M.select(n)
  return logic.select(st, owned(), n)
end

-- Selecciona la herramienta `id` si se tiene (la pelea del simio saca el machete sola). true si quedo seleccionada
function M.select_id(id)
  for _, d in ipairs(owned()) do
    if d.id == id then
      st.selected = d.id -- directo: select(n) solo llega a MAX_SLOTS casillas
      return true
    end
  end
  return false
end

-- Usa la seleccionada. Devuelve el mensaje a mostrar (o nil si no hay nada que decir)
function M.use()
  local def = M.selected()
  if not def then return nil end
  local ok, why = logic.check_use(def, ws.has)
  if not ok then return why end
  local use = def.use
  local msg = use.line
  if use.fn then
    local r, m = use.fn({ def = def })
    if r == false then return m end
    if m then msg = m end
  end
  if use.set_flag then ws.set(use.set_flag, true) end
  if use.consume then M.take(def.id) end
  return msg
end

-- Barra de herramientas abajo al centro: solo con al menos una. Selecciona con 1-4
function M.draw_hud()
  local list = owned()
  if #list == 0 then return end
  local sel = logic.selected_index(st, list)
  if not sel then M.selected(); sel = logic.selected_index(st, list) end
  local sw, sh = get_screen_size()
  local slots = logic.slot_layout(#list, sw, sh)
  for i, r in ipairs(slots) do
    local d = list[i]
    local usable = logic.check_use(d, ws.has)
    local a = usable and 255 or 110
    draw_rect(r.x, r.y, r.w, r.h, 0, 0, 0, 170, true)
    draw_rect(r.x + 2, r.y + 2, r.w - 4, 3, d.color[1], d.color[2], d.color[3], a, true)
    draw_text(r.x + 2, r.y + 6, d.label, "default", 255, 255, 255, a)
    draw_text(r.x + 1, r.y - 1, tostring(i), "default", 200, 200, 200, 200)
    if i == sel then
      draw_rect(r.x - 1, r.y - 1, r.w + 2, r.h + 2, 255, 230, 120, 255, false)
    end
  end
end

return M
