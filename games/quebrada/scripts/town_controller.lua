-- Controlador de mapa con puertas y zonas (issue #62). Un script por escena:
--   update = require("town_controller").make_update({ map = "maps/town.tmx", scenes = {...} })
--
-- Los rects de puertas y zonas del TMX se sondean cada frame con la caja de pies
-- del jugador (el motor no tiene triggers estaticos). El jugador publica los
-- globales player_entity y player_walker (ver town_player.lua).
-- Tambien alimenta el ambiente por zona/hora y la superficie de los pasos (issue #65).
--
-- Config:
--   map      ruta del TMX de esta escena (obligatorio)
--   scenes   { [ruta del TMX] = ruta de la escena } para las puertas que cambian de mapa
--   box      caja de pies {x,y,w,h} dentro del sprite (por defecto 3,8,10,8)
--   grid     paso de la rejilla de suelo en px (32)
--   debug_flag  flag que alterna la tecla F ("unlock.house.chayo")
--   debug_overlay  true = F3 abre el overlay de flags y misiones (tecla "debug_overlay" en la escena)
--   back_scene  escena a la que vuelve la tecla 0 ("scenes/main.lua"); nil = sin salida
--   Historias narradas y libreta (issue #68): story.lua reproduce la grabacion con el
--   overlay del reproductor y dispara pistas. Teclas opcionales de la escena:
--   story_pause (Espacio), story_stop y story_stop_alt (Retroceso y Q).
--   Pistas de boca en boca y compuertas (issue #69): leads.lua resuelve las leyendas y publica
--   flags unlock.*; las compuertas (class "gate", capa "gates") devuelven al jugador a su ultima
--   posicion libre mientras esten cerradas. Docs: games/quebrada/docs/leads.md
--   Consecuencias (#70): consequences.lua (dia, comentarios), docs/consequences.md
--   tile_map  true = ademas dibuja las capas de tiles del TMX (tileset del pueblo, issue #55,
--   docs/tileset.md); los tiles solid tambien colisionan. town.tmx no lo usa (solo objetos).
--   roofs  techos que se desvanecen y ventanas encendidas (issue #71, scripts/roofs.lua,
--   docs/buildings.md). nil = sigue a tile_map; false = apagado.
--   world_debug  true (por defecto) = dibuja la rejilla, los rects de colision y las puertas
--   encima del mapa; las escenas con tiles de edificios lo ponen en false.
--   Triggers y emisores (issue #78): triggers.lua dispara los rects class="trigger" de la capa
--   `triggers` (misiones, p. ej. la noche del chequelo) y emitters.lua reproduce los class="emitter"
--   segun `only` / `when`. Docs: games/quebrada/docs/zona1.md
--   on_start  funcion opcional que se llama una vez cuando el jugador ya esta colocado en el mapa.
local logic = require("door_logic")
local ws = require("world_state")
local fade = require("fade")
local surfaces = require("surface_logic")
local footsteps = require("footsteps")
local amb = require("ambience")
local interaction = require("interaction")
local save = require("save")
local dialogue = require("dialogue")
local missions = require("missions")
local mlogic = require("missions_logic")
local story = require("story")
local leads = require("leads")
local llogic = require("leads_logic")
local consequences = require("consequences")
local lighting = require("lighting")
local tod = require("time_of_day")
local foco = require("foco")
local companion = require("companion_light")
local tools = require("tools")
local libreta_ui = require("libreta_ui")
local roofs = require("roofs")
local triggers = require("triggers")
local emitters = require("emitters")

local M = {}

M.DEFAULTS = {
  box = { x = 3, y = 8, w = 10, h = 8 },
  scenes = {},
  grid = 32,
  debug_flag = "unlock.house.chayo",
  debug_overlay = true,
  back_scene = "scenes/main.lua",
  default_prompt = "E: entrar",
  default_locked_line = "Está cerrado.",
  toast_time = 2.0,
  line_time = 2.0,
  lead_time = 5.0,
  tile_map = false, -- true = dibujar las capas de tiles del TMX con load_tile_map (issue #55)
  roofs = nil,      -- nil = sigue a tile_map; techos que se desvanecen + ventanas encendidas (issue #71)
  world_debug = true, -- false = sin rejilla / colisiones / puertas dibujadas (issue #71)
  on_start = nil,   -- funcion llamada una vez al colocar al jugador (issue #78)
  companion = false, -- true = luz companera de la noche del chequelo (issue #81)
}

local FONT = "default"
local CHAR_W = 6 -- ancho aproximado de DejaVuSansMono a tamano 10

-- Ancho aproximado del texto en px (cuenta caracteres UTF-8, no bytes)
local function text_width(s)
  return ((utf8 and utf8.len(s)) or #s) * CHAR_W
end

-- Texto centrado en x con un fondo oscuro (los rects HUD se pintan bajo el texto)
local function draw_centered(text, y)
  local sw = get_screen_size()
  local w = text_width(text)
  local x = math.floor((sw - w) / 2)
  draw_rect(x - 4, y - 2, w + 8, 14, 0, 0, 0, 170, true)
  draw_text(x, y, text, FONT, 255, 255, 255, 255)
end

-- Objetos de Tiled con `only` (issue #66): solo los visibles en la fase actual
local function visible_only(list)
  local out = {}
  for _, o in ipairs(list) do
    if tod.visible(o.properties) then out[#out + 1] = o end
  end
  return out
end

function M.make_update(cfg)
  local c = {}
  for k, v in pairs(M.DEFAULTS) do c[k] = v end
  for k, v in pairs(cfg or {}) do c[k] = v end

  local map, idx
  local failed = false
  local placed = false
  local transition = false      -- true desde que se acepta la puerta hasta que acaba el fundido
  local ignore_until_clear = false
  local was_interact = false
  local was_debug = false
  local was_back = false
  local was_time = false
  local was_libreta = false               -- flanco de Tab / L (libreta, issue #80)
  local was_tool = {}                     -- flancos de las teclas de herramientas (issue #53)
  local toast = { text = nil, left = 0 }  -- aviso de zona (arriba)
  local line = { text = nil, left = 0 }   -- frase de puerta cerrada / depuracion (abajo)
  local saved_input = nil
  local ov = { open = false, sel = 1, rows = {} } -- overlay de depuracion (F3)
  local ovk = {}                                  -- estado previo de teclas del overlay
  local lidx = { gates = {}, markers = {} }       -- compuertas y marcadores de pistas (#69)
  local safe = nil                                -- ultima posicion libre de compuertas {x,y}
  local clock = 0                                 -- reloj para el vaiven de los marcadores

  -- ---- input del jugador ----
  local function lock_input()
    if saved_input or not player_walker then return end
    saved_input = { fn = player_walker.input }
    player_walker.input = function() return 0, 0, false end
  end

  local function unlock_input()
    if saved_input and player_walker then player_walker.input = saved_input.fn end
    saved_input = nil
  end

  local function interact_down()
    return is_action_activated("interact") or is_action_activated("interact_alt")
  end

  -- ---- overlay de depuracion (F3) ----
  local function held(a, b)
    return is_action_activated(a) or (b ~= nil and is_action_activated(b)) or false
  end

  -- Flanco por clave; se llama todos los frames para no arrastrar estados viejos
  local function edge(k, down)
    local p = down and not ovk[k]
    ovk[k] = down
    return p
  end

  local function update_overlay(dlg_open)
    if not c.debug_overlay then return end
    local f3 = edge("f3", held("debug_overlay"))
    local up = edge("up", held("walk_up", "walk_up_alt"))
    local dn = edge("dn", held("walk_down", "walk_down_alt"))
    local lf = edge("lf", held("walk_left", "walk_left_alt"))
    local rt = edge("rt", held("walk_right", "walk_right_alt"))
    local ok = edge("ok", interact_down())
    if f3 then
      if ov.open then
        ov.open = false
        unlock_input()
      elseif placed and not transition and not dlg_open and fade.alpha() == 0 and not story.is_open() and not libreta_ui.is_open() then
        ov.open = true
        ov.sel = 1
        lock_input()
      end
      return
    end
    if not ov.open then return end

    ov.rows = mlogic.build_rows(missions.ids(), missions.state, ws.flags)
    local n = #ov.rows
    if up then ov.sel = ov.sel - 1 end
    if dn then ov.sel = ov.sel + 1 end
    if ov.sel > n then ov.sel = n end
    if ov.sel < 1 then ov.sel = 1 end
    local r = ov.rows[ov.sel]
    if not r then return end
    local dir = (lf and -1) or ((rt or ok) and 1) or 0
    if dir == 0 then return end
    if r.kind == "mission" then
      missions.jump(r.id, mlogic.cycle_state(missions.state(r.id), dir))
    else
      ws.set(r.name, mlogic.step_value(ws.get(r.name), dir))
    end
  end

  local function draw_overlay()
    if not ov.open or fade.alpha() > 0 then return end
    local sw, sh = get_screen_size()
    local lh = get_line_height(FONT)
    if not lh or lh <= 0 then lh = 12 end
    local x, y, w, h = 8, 8, sw - 16, sh - 16
    draw_rect(x, y, w, h, 10, 10, 20, 235, true)
    draw_rect(x, y, w, h, 235, 225, 200, 255, false)
    draw_text(x + 6, y + 4, "DEBUG F3 (día " .. consequences.day() .. ") | Arriba/Abajo: mover  Izq/Der: cambiar  E: siguiente", FONT, 255, 220, 80, 255)
    local rows = ov.rows
    local top = y + 4 + lh + 4
    local visible = math.floor((y + h - 4 - top) / lh)
    local first = mlogic.window_start(ov.sel, #rows, visible)
    for i = first, math.min(#rows, first + visible - 1) do
      local ty = top + (i - first) * lh
      if i == ov.sel then draw_rect(x + 3, ty, w - 6, lh, 70, 55, 110, 255, true) end
      draw_text(x + 8, ty, rows[i].text, FONT, 255, 255, 255, 255)
    end
  end

  -- ---- colocar al jugador ----
  -- Teletransporta la caja de pies al spawn, orienta al walker y reinicia la camara
  local function place_player(sx, sy, facing)
    safe = nil -- un teletransporte invalida la ultima posicion libre
    local px, py = logic.spawn_to_position(sx, sy, c.box)
    set_position(player_entity, px, py)
    set_velocity(player_entity, 0, 0)
    if facing then player_walker:set_facing(facing) end
    player_walker.cam_state = {} -- la camara salta al jugador en vez de deslizarse
  end

  local function door_center(door)
    local r = door.rect
    return r.x + r.w / 2, r.y + r.h / 2
  end

  -- ---- carga y colocacion inicial ----
  local function init()
    ws.clear_listeners()
    ws.on_change(function(name, new, old)
      print("[doors] flag " .. name .. ": " .. tostring(old) .. " -> " .. tostring(new))
    end)
    interaction.clear()
    dialogue.reset()   -- el flag dialogue.open es global: se limpia al recargar la escena
    dialogue.attach()  -- interaction.on_npc se vuelve a conectar en cada escena
    story.reset()      -- load_scene detuvo los sonidos: se guarda/descarta la sesion vieja
    libreta_ui.reset() -- la libreta no sigue abierta tras recargar la escena
    story.attach()
    interaction.say = function(t) line.text, line.left = t, c.line_time end
    leads.say = function(t) line.text, line.left = t, c.lead_time end
    player_walker = nil -- un walker de la escena anterior no vale
    local m, err = load_tmx(c.map)
    if not m then
      print("[town] no se pudo cargar " .. tostring(c.map) .. ": " .. tostring(err))
      failed = true
      return
    end
    map = m
    idx = logic.index_objects(m)
    lidx = llogic.index_map(m.objects)
    leads.validate()
    consequences.init()
    consequences.validate()
    interaction.from_map(m)
    triggers.init(m)
    triggers.say = function(t) line.text, line.left = t, c.line_time end
    emitters.init(m)
    lighting.init()
    foco.init()
    companion.init(m, c.companion)
    tod.init(m)
    save.note_map(c.map, c.scenes and c.scenes[c.map])
    tod.on_day = function(d)
      line.text, line.left = "Día " .. d, c.line_time
      save.autosave() -- amanecer = dia nuevo (issue #52)
    end
    interaction.on_sleep = function()
      if not tod.sleep() then
        line.text, line.left = "Todavía no tengo sueño", c.line_time
      else
        foco.recharge()
      end
    end
    interaction.on_tool = function() save.autosave() end -- recoger una herramienta (issue #53)
    interaction.on_recharge = function(what)
      if what == "foco" then foco.recharge(); line.text, line.left = "Foco cargado", c.line_time end
    end
    footsteps.set_source(surfaces.build(m))
    if c.tile_map then
      local ok, terr = load_tile_map(c.map)
      if not ok then print("[town] tile map: " .. tostring(terr)) end
    end
    if c.roofs == nil then c.roofs = c.tile_map end
    if c.roofs then roofs.init(m) end
    local n, cerr = load_tmx_colliders(c.map)
    if not n then print("[town] colliders: " .. tostring(cerr)) end
    -- Llegada con fundido: el primer frame ya es negro (sin destello)
    if ws.ctx().arrival then fade.set_black() end
  end

  local function try_place()
    if not player_entity or not player_walker then return false end
    local arrival = ws.take_arrival()
    local sx, sy, sfacing
    if arrival then
      sx, sy, sfacing = logic.resolve_spawn(idx.spawns, arrival.spawn)
      if not sx then
        print("[town] llegada: " .. tostring(sy))
        arrival = nil
      end
    end
    if not arrival then
      sx, sy, sfacing = logic.resolve_spawn(idx.spawns, "default")
      if not sx then
        print("[town] el mapa no tiene spawn 'default'")
        return true
      end
    end
    local facing = (arrival and arrival.facing) or sfacing or "down"
    place_player(sx, sy, facing)
    if arrival then
      ignore_until_clear = true
      lock_input()
      transition = true
      fade.start_in(function()
        transition = false
        unlock_input()
      end)
    end
    return true
  end

  -- ---- transicion de puerta ----
  local function finish_same_map(door, spawn_name)
    local sx, sy, sfacing = logic.resolve_spawn(idx.spawns, spawn_name)
    if not sx then
      print("[doors] " .. tostring(sy))
      fade.start_in(function() transition = false; unlock_input() end)
      return
    end
    local cx, cy = door_center(door)
    place_player(sx, sy, sfacing or logic.facing_away(cx, cy, sx, sy))
    ignore_until_clear = true
    fade.start_in(function()
      transition = false
      unlock_input()
    end)
  end

  local function finish_other_map(door, target_map, target_spawn)
    local scene = c.scenes[target_map]
    if not scene then
      print("[doors] no hay escena para el mapa '" .. tostring(target_map) .. "'")
      fade.start_in(function() transition = false; unlock_input() end)
      return
    end
    local ctx = ws.ctx()
    local props = door.properties or {}
    local new_ctx
    if props.target_map == "@return" then
      -- Salir de un interior: vuelve al spawn de la puerta por la que entramos
      new_ctx = { arrival = { map = target_map, spawn = target_spawn, facing = ctx.return_facing } }
    else
      -- Entrar: se recuerda por donde volver y hacia donde se mira al salir
      local rfacing = nil
      if props.exit_spawn then
        local ex, ey, ef = logic.resolve_spawn(idx.spawns, props.exit_spawn)
        if ex then
          local cx, cy = door_center(door)
          rfacing = ef or logic.facing_away(cx, cy, ex, ey)
        end
      end
      new_ctx = {
        arrival = { map = target_map, spawn = target_spawn },
        return_map = c.map,
        return_spawn = props.exit_spawn,
        return_facing = rfacing,
      }
    end
    ws.set_ctx(new_ctx)
    save.autosave({ map = target_map, scene = scene }) -- entrar o salir de una casa (issue #52)
    -- load_scene es diferido: el negro se mantiene hasta que cargue la escena nueva
    load_scene(scene)
  end

  local function begin_transition(door)
    local target_map, target_spawn, err = logic.door_target(door, ws.ctx())
    if err then
      print("[doors] " .. err)
      line.text, line.left = err, c.line_time
      return
    end
    transition = true
    local lk = door.properties and door.properties.lead
    if lk and lk ~= "" then leads.visit(lk) end
    lock_input()
    local same = (target_map == nil) or (target_map == c.map)
    fade.start_out(function()
      if same then
        finish_same_map(door, target_spawn)
      else
        finish_other_map(door, target_map, target_spawn)
      end
    end)
  end

  -- ---- dibujo ----
  local function draw_world()
    local mw = map.width * map.tilewidth
    local mh = map.height * map.tileheight
    if c.world_debug then
      for x = 0, mw, c.grid do draw_rect_world(x, 0, 1, mh, 90, 90, 100, 90, true) end
      for y = 0, mh, c.grid do draw_rect_world(0, y, mw, 1, 90, 90, 100, 90, true) end
      draw_rect_world(0, 0, mw, mh, 255, 255, 255, 255, false)
      for _, o in ipairs(map.objects) do
        if o.layer == "collision" and o.shape == "rect" and tod.visible(o.properties) then
          local r = o.rect
          draw_rect_world(r.x, r.y, r.w, r.h, 120, 90, 60, 255, true)
        end
      end
      for _, d in ipairs(visible_only(idx.doors)) do
        local r = d.rect
        if logic.is_locked(d, ws.has) then
          draw_rect_world(r.x, r.y, r.w, r.h, 200, 60, 60, 160, true)
        else
          draw_rect_world(r.x, r.y, r.w, r.h, 80, 200, 90, 160, true)
        end
      end
    end
    for _, g in ipairs(visible_only(lidx.gates)) do
      if logic.is_locked(g, ws.has) then
        local r = g.rect
        draw_rect_world(r.x, r.y, r.w, r.h, 160, 110, 40, 160, true)
      end
    end
  end

  -- ---- frame ----
  return function()
    local dt = math.min(get_delta_time(), 0.05)
    fade.update(dt)
    clock = clock + dt

    if not map and not failed then init() end
    if failed then
      fade.draw()
      return
    end

    local dlg_open = dialogue.is_open() -- foto del inicio del frame (la E que cierra no abre puertas)
    consequences.tick()

    draw_world()
    interaction.draw_figures()
    if not ov.open and not story.is_open() and not libreta_ui.is_open() then leads.draw_markers(lidx.markers, clock) end

    local prompt = nil
    if not placed then
      if c.roofs then roofs.update(dt, nil) end
      placed = try_place()
      if placed and c.on_start then
        local ok, e = pcall(c.on_start)
        if not ok then print("[town] on_start fallo: " .. tostring(e)) end
      end
    else
      local px, py = get_position(player_entity)
      local foot = logic.foot_box(px, py, c.box)
      if c.roofs then roofs.update(dt, foot) end
      local fcx, fcy = foot.x + foot.w / 2, foot.y + foot.h / 2
      local door = logic.find_door(visible_only(idx.doors), foot)
      local door_raw = door

      -- Compuertas cerradas: sin collider conmutable, se devuelve al jugador a su ultima posicion libre
      local gate = llogic.first_locked_gate(visible_only(lidx.gates), foot, ws.has)
      if gate then
        if safe and not transition then
          set_position(player_entity, safe.x, safe.y)
          set_velocity(player_entity, 0, 0)
          if line.left <= 0 then
            line.text = gate.properties.locked_line or c.default_locked_line
            line.left = c.line_time
          end
        end
      elseif not transition then
        safe = { x = px, y = py }
      end

      -- Tras llegar, no se puede interactuar hasta salir una vez de toda puerta
      if ignore_until_clear then
        if not door then ignore_until_clear = false end
        door = nil
      end
      if transition then door = nil end
      if dlg_open then door = nil end
      if ov.open then door = nil end
      if story.is_open() then door = nil end
      if libreta_ui.is_open() then door = nil end
      if tod.is_busy() then door = nil end

      -- Zona: aviso solo al cambiar (no al volver a entrar en la misma)
      local z = logic.find_zone(idx.zones, fcx, fcy)
      if z then
        local zid = z.properties.zone or z.name
        local ctx = ws.ctx()
        if zid ~= ctx.zone then
          ctx.zone = zid
          leads.visit("zone." .. zid)
          toast.text = z.properties.title or zid
          toast.left = c.toast_time
        end
        amb.set_zone(z.properties.ambience) -- idempotente; tambien tras recargar escena
      end

      -- Triggers de mapa (issue #78): no durante una transicion, con el overlay abierto ni con la tarjeta de hora
      if not transition and not ov.open and not tod.is_busy() then triggers.tick(foot) end

      -- Interaccion por flanco (is_action_activated es "mantenida")
      local down = interact_down()
      local pressed = down and not was_interact
      was_interact = down
      if door then
        if pressed then
          if logic.is_locked(door, ws.has) then
            line.text = door.properties.locked_line or c.default_locked_line
            line.left = c.line_time
          else
            begin_transition(door)
          end
        else
          prompt = door.properties.prompt or c.default_prompt
        end
      end

      -- Interactuables (NPCs/objetos): nunca a la vez que una puerta ni en transicion
      local suppress = dlg_open or transition or ignore_until_clear or door_raw ~= nil or fade.alpha() > 0 or ov.open or story.is_open() or libreta_ui.is_open() or tod.is_busy()
      local ihint = interaction.update(dt, {
        x = fcx, y = fcy, facing = player_walker:get_facing(), suppress = suppress,
      })
      if ihint and not prompt then prompt = ihint end

      -- Depuracion: F alterna el flag (la puerta cambia al frame siguiente)
      local fdown = is_action_activated("debug_toggle")
      if fdown and not was_debug and c.debug_flag and not ov.open and not story.is_open() and not libreta_ui.is_open() then
        local v = not ws.has(c.debug_flag)
        ws.set(c.debug_flag, v)
        line.text = c.debug_flag .. " = " .. tostring(v)
        line.left = c.line_time
      end
      was_debug = fdown

      -- N alterna dia/noche por time_of_day (el mismo camino que la cama y las misiones)
      local tdown = is_action_activated("toggle_time")
      if tdown and not was_time and not tod.is_busy() then
        tod.toggle()
        print("[time_of_day] hora: " .. tod.get())
      end
      was_time = tdown

      -- Herramientas (issue #53): 1-4 seleccionan, X usa la seleccionada. El jugador no sabe
      -- de ninguna en concreto: tools.lua ejecuta el uso definido en sus datos
      -- Libreta (issue #80): Tab / L abre y cierra. Bloquea al jugador como el overlay F3; el
      -- ambiente sigue sonando (amb.tick no depende de los overlays)
      local ldown = is_action_activated("libreta") or is_action_activated("libreta_alt")
      if ldown and not was_libreta then
        if libreta_ui.is_open() then
          libreta_ui.close()
          unlock_input()
        elseif not dlg_open and not ov.open and not story.is_open() and not transition and not tod.is_busy() and fade.alpha() == 0 then
          libreta_ui.open()
          lock_input()
        end
      end
      was_libreta = ldown
      local tools_ok = not dlg_open and not ov.open and not story.is_open() and not libreta_ui.is_open() and not tod.is_busy() and fade.alpha() == 0
      for n = 1, 4 do
        local name = "tool" .. n
        local d = is_action_activated(name)
        if d and not was_tool[name] and tools_ok then tools.select(n) end
        was_tool[name] = d
      end
      local ud = is_action_activated("tool_use")
      if ud and not was_tool.use and tools_ok then
        local msg = tools.use()
        if msg then line.text, line.left = msg, c.line_time end
      end
      was_tool.use = ud
      amb.tick(dt)
      emitters.tick(dt)
      -- Pistas: no se evaluan con pantalla ocupada (no se pierden, esperan)
      local hidden = dlg_open or transition or ov.open or story.is_open() or libreta_ui.is_open() or fade.alpha() > 0 or tod.is_busy()
      story.tick(dt, { x = fcx, y = fcy, zone = ws.ctx().zone, time = amb.get_time(), phase = tod.get(), map = c.map, hidden = hidden })
      leads.tick({ hidden = hidden })
    end

    -- Iluminacion: ambiente segun la hora y linterna del jugador
    lighting.tick()
    tod.tick(dt)
    foco.tick(dt)
    if placed then companion.tick(dt) end

    -- F3: overlay de depuracion (tambien captura teclas mientras esta abierto)
    update_overlay(dlg_open)

    -- Libreta: navegacion; "replay" = volver a oir una historia (cierra y suelta al jugador
    -- antes, para que el bloqueo de la historia no herede el de la libreta)
    local lact, lid = libreta_ui.update(dt)
    if lact == "replay" then
      libreta_ui.close()
      unlock_input()
      story.play(lid, { replay = true })
    end

    -- Tecla 0: volver a la escena principal (flanco; no durante una transicion)
    local bdown = is_action_activated("back")
    if bdown and not was_back and c.back_scene and not transition and not dlg_open and not ov.open and not story.is_open() and not libreta_ui.is_open() then
      load_scene(c.back_scene)
    end
    was_back = bdown

    -- El dialogo va despues de puertas e interaccion: la E que lo cierra ya fue consumida
    dialogue.update(dt)
    story.update(dt)

    -- Textos: solo con la pantalla despejada (los rects HUD se pintan bajo el
    -- texto y el fundido quedaria tapado por el)
    if fade.alpha() == 0 and not dialogue.is_open() and not ov.open and not story.is_open() and not libreta_ui.is_open() then
      if toast.left > 0 then
        toast.left = toast.left - dt
        draw_centered(toast.text, 12)
      end
      local ct = story.clue_text()
      if ct then draw_centered("Pista: " .. ct, 30) end
      if line.left > 0 then
        line.left = line.left - dt
        draw_centered(line.text, 226)
      elseif prompt then
        draw_centered(prompt, 226)
      end
      foco.draw_hud()
      tools.draw_hud()
    end

    libreta_ui.draw()
    draw_overlay()

    fade.draw() -- siempre el ultimo del fundido de puertas
    tod.draw()  -- tarjeta de titulo de la hora (encima de todo)
  end
end

return M
