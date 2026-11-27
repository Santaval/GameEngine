-- Interaccion por proximidad (issue #49). Cosas registradas como interactuables:
--   interaction.register({ rect = {x,y,w,h} | entity = e, size = {w,h},
--     radius = 24, label = "Hablar", target = "mamá", on_interact = fn, enabled = fn })
-- Cada frame, interaction.update elige el mas cercano en rango y delante del
-- jugador, dibuja el indicador sobre el y devuelve el texto del HUD.
-- Docs: games/quebrada/docs/interaction.md
local logic = require("interaction_logic")
local door_logic = require("door_logic")
local ws = require("world_state")

local M = {}

M.DEFAULT_RADIUS = 24
M.KEY_LABEL = "E"
M.on_npc = nil -- fn(nombre, obj): la registrara el dialogo (issue futuro)
M.say = nil    -- fn(texto): el controlador muestra una linea de aviso
M.STORY_LABEL = "Escuchar la historia"
M.story_available = nil -- fn(id) -> bool: la registra story.attach()
M.on_story = nil        -- fn(id, npc, obj): la registra story.attach()

local items = {}
local was_down = false
local time = 0

function M.register(it)
  items[#items + 1] = it
  return it
end

function M.unregister(it)
  local n = #items
  for i = 1, n do
    if items[i] == it then
      for j = i, n - 1 do items[j] = items[j + 1] end
      items[n] = nil
      return
    end
  end
end

function M.clear()
  items = {}
  was_down = false
end

-- Interaccion bloqueada mientras haya dialogo o libreta abiertos
function M.is_blocked()
  return ws.has("dialogue.open") or ws.has("libreta.open") or ws.has("story.open")
end

local function say(text)
  if M.say then M.say(text) else print("[interaction] " .. tostring(text)) end
end

-- Rect del interactuable en mundo (nil si la entidad ya no existe)
local function resolve_rect(it)
  if it.rect then return it.rect end
  if it.entity then
    local x, y = get_position(it.entity)
    if not x then return nil end
    local s = it.size or { 16, 16 }
    return { x = x, y = y, w = s[1], h = s[2] }
  end
  return nil
end

local function text_of(it)
  local label, bare = it.label, false
  if it.label_fn then label, bare = it.label_fn(it) end
  local t = label or "Interactuar"
  if not bare and it.target and it.target ~= "" then t = t .. " con " .. it.target end
  return M.KEY_LABEL .. " — " .. t
end

-- Crea interactuables desde los objetos TMX de clase `interactable`
function M.from_map(map)
  for _, o in ipairs(map.objects or {}) do
    if o.type == "interactable" then
      local p = o.properties or {}
      local kind = p.interact
      if (kind == nil or kind == "") and p.npc then kind = "npc" end
      if kind == "door" then
        print("[interaction] '" .. tostring(o.name) .. "': las puertas van en la capa doors")
      else
        local rect = o.rect
        if not rect and o.x then rect = { x = o.x, y = o.y, w = 0, h = 0 } end
        local it = { rect = rect, radius = tonumber(p.radius), name = o.name }
        -- Figura provisional (issue #70): `figure` = "r,g,b"; se dibuja mientras el item este habilitado
        local fr, fg, fb = logic.parse_color(p.figure)
        if fr then it.figure = { fr, fg, fb } end
        if kind == "npc" then
          local npc = p.npc
          local sid = (p.story ~= nil and p.story ~= "") and p.story or nil
          it.label = p.label or "Hablar"
          it.target = p.target
          if sid then
            -- Narrador: con historia disponible el boton es "Escuchar la historia"
            it.label_fn = function()
              if M.story_available and M.story_available(sid) then return M.STORY_LABEL, true end
              return p.label or "Hablar", false
            end
          end
          it.on_interact = function()
            if sid and M.story_available and M.story_available(sid) and M.on_story then
              M.on_story(sid, npc, o)
            elseif M.on_npc then
              M.on_npc(npc, o)
            else
              say(p.line or "...")
            end
          end
        else
          it.label = p.label or "Examinar"
          it.target = p.target
          it.on_interact = function()
            if p.set_flag and p.set_flag ~= "" then ws.set(p.set_flag, true) end
            if p.sleep and M.on_sleep then M.on_sleep(); return end
            say(p.line or "...")
          end
        end
        -- `enabled` (condicion de flags) y `only` (hora del dia, issue #66) se combinan con AND
        local cond = (p.enabled ~= nil and p.enabled ~= "") and p.enabled or nil
        local only = (type(p.only) == "string" and p.only ~= "") and p.only or nil
        if cond or only then
          it.enabled = function()
            if only and not require("time_of_day").visible(only) then return false end
            if cond then return door_logic.eval_condition(cond, ws.has) end
            return true
          end
        end
        if rect then M.register(it) end
      end
    end
  end
end

-- Dibuja las figuras provisionales de los NPC con propiedad `figure` (issue #70).
-- Se llama cada frame desde el controlador; respeta `enabled`.
function M.draw_figures()
  for _, it in ipairs(items) do
    local f = it.figure
    if f and it.rect and (it.enabled == nil or it.enabled()) then
      local cx = math.floor(it.rect.x + it.rect.w / 2)
      local by = math.floor(it.rect.y + it.rect.h)
      draw_rect_world(cx - 5, by - 14, 10, 14, f[1], f[2], f[3], 255, true) -- cuerpo
      draw_rect_world(cx - 3, by - 20, 6, 6, 230, 190, 150, 255, true)      -- cabeza
    end
  end
end

-- o = { x, y (centro de la caja de pies), facing, suppress }
-- Devuelve el texto del HUD del objetivo actual (o nil)
function M.update(dt, o)
  time = time + dt
  local down = is_action_activated("interact") or is_action_activated("interact_alt")
  local pressed
  pressed, was_down = logic.edge(was_down, down)
  if o.suppress or M.is_blocked() then return nil end

  local cands = {}
  for _, it in ipairs(items) do
    local r = resolve_rect(it)
    if r and (it.enabled == nil or it.enabled()) then
      cands[#cands + 1] = { ref = it, rect = r, radius = it.radius or M.DEFAULT_RADIUS }
    end
  end
  local best = logic.pick(cands, o.x, o.y, o.facing)
  if not best then return nil end
  local it = best.ref

  -- Indicador sobre el objetivo, con un pequeno vaiven
  local cx = best.rect.x + best.rect.w / 2
  local bob = math.floor(math.sin(time * 6) * 2 + 0.5)
  draw_text_world(cx - 3, best.rect.y - 14 + bob, "!", "default", 255, 220, 80, 255)

  if pressed and it.on_interact then
    local ok, err = pcall(it.on_interact, it)
    if not ok then print("[interaction] on_interact fallo: " .. tostring(err)) end
  end
  return text_of(it)
end

return M
