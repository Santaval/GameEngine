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
--   debug_flag  flag que alterna la tecla F ("house.chayo.open")
--   debug_overlay  true = F3 abre el overlay de flags y misiones (tecla "debug_overlay" en la escena)
--   back_scene  escena a la que vuelve la tecla 0 ("scenes/main.lua"); nil = sin salida
local logic = require("door_logic")
local ws = require("world_state")
local fade = require("fade")
local surfaces = require("surface_logic")
local footsteps = require("footsteps")
local amb = require("ambience")
local interaction = require("interaction")
local dialogue = require("dialogue")
local missions = require("missions")
local mlogic = require("missions_logic")

local M = {}

M.DEFAULTS = {
  box = { x = 3, y = 8, w = 10, h = 8 },
  scenes = {},
  grid = 32,
  debug_flag = "house.chayo.open",
  debug_overlay = true,
  back_scene = "scenes/main.lua",
  default_prompt = "E: entrar",
  default_locked_line = "Está cerrado.",
  toast_time = 2.0,
  line_time = 2.0,
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
  local toast = { text = nil, left = 0 }  -- aviso de zona (arriba)
  local line = { text = nil, left = 0 }   -- frase de puerta cerrada / depuracion (abajo)
  local saved_input = nil
  local ov = { open = false, sel = 1, rows = {} } -- overlay de depuracion (F3)
  local ovk = {}                                  -- estado previo de teclas del overlay

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
      elseif placed and not transition and not dlg_open and fade.alpha() == 0 then
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
    draw_text(x + 6, y + 4, "DEBUG F3 | Arriba/Abajo: mover  Izq/Der: cambiar  E: siguiente", FONT, 255, 220, 80, 255)
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
    interaction.say = function(t) line.text, line.left = t, c.line_time end
    player_walker = nil -- un walker de la escena anterior no vale
    local m, err = load_tmx(c.map)
    if not m then
      print("[town] no se pudo cargar " .. tostring(c.map) .. ": " .. tostring(err))
      failed = true
      return
    end
    map = m
    idx = logic.index_objects(m)
    interaction.from_map(m)
    footsteps.set_source(surfaces.build(m))
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
    for x = 0, mw, c.grid do draw_rect_world(x, 0, 1, mh, 90, 90, 100, 90, true) end
    for y = 0, mh, c.grid do draw_rect_world(0, y, mw, 1, 90, 90, 100, 90, true) end
    draw_rect_world(0, 0, mw, mh, 255, 255, 255, 255, false)
    for _, o in ipairs(map.objects) do
      if o.layer == "collision" and o.shape == "rect" then
        local r = o.rect
        draw_rect_world(r.x, r.y, r.w, r.h, 120, 90, 60, 255, true)
      end
    end
    for _, d in ipairs(idx.doors) do
      local r = d.rect
      if logic.is_locked(d, ws.has) then
        draw_rect_world(r.x, r.y, r.w, r.h, 200, 60, 60, 160, true)
      else
        draw_rect_world(r.x, r.y, r.w, r.h, 80, 200, 90, 160, true)
      end
    end
  end

  -- ---- frame ----
  return function()
    local dt = math.min(get_delta_time(), 0.05)
    fade.update(dt)

    if not map and not failed then init() end
    if failed then
      fade.draw()
      return
    end

    local dlg_open = dialogue.is_open() -- foto del inicio del frame (la E que cierra no abre puertas)

    draw_world()

    local prompt = nil
    if not placed then
      placed = try_place()
    else
      local px, py = get_position(player_entity)
      local foot = logic.foot_box(px, py, c.box)
      local fcx, fcy = foot.x + foot.w / 2, foot.y + foot.h / 2
      local door = logic.find_door(idx.doors, foot)
      local door_raw = door

      -- Tras llegar, no se puede interactuar hasta salir una vez de toda puerta
      if ignore_until_clear then
        if not door then ignore_until_clear = false end
        door = nil
      end
      if transition then door = nil end
      if dlg_open then door = nil end
      if ov.open then door = nil end

      -- Zona: aviso solo al cambiar (no al volver a entrar en la misma)
      local z = logic.find_zone(idx.zones, fcx, fcy)
      if z then
        local zid = z.properties.zone or z.name
        local ctx = ws.ctx()
        if zid ~= ctx.zone then
          ctx.zone = zid
          toast.text = z.properties.title or zid
          toast.left = c.toast_time
        end
        amb.set_zone(z.properties.ambience) -- idempotente; tambien tras recargar escena
      end

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
      local suppress = dlg_open or transition or ignore_until_clear or door_raw ~= nil or fade.alpha() > 0 or ov.open
      local ihint = interaction.update(dt, {
        x = fcx, y = fcy, facing = player_walker:get_facing(), suppress = suppress,
      })
      if ihint and not prompt then prompt = ihint end

      -- Depuracion: F alterna el flag (la puerta cambia al frame siguiente)
      local fdown = is_action_activated("debug_toggle")
      if fdown and not was_debug and c.debug_flag and not ov.open then
        local v = not ws.has(c.debug_flag)
        ws.set(c.debug_flag, v)
        line.text = c.debug_flag .. " = " .. tostring(v)
        line.left = c.line_time
      end
      was_debug = fdown

      -- N alterna dia/noche (el ambiente solo lee la hora)
      local tdown = is_action_activated("toggle_time")
      if tdown and not was_time then
        amb.set_time(amb.get_time() == "day" and "night" or "day")
        print("[ambience] hora: " .. amb.get_time())
      end
      was_time = tdown
      amb.tick(dt)
    end

    -- F3: overlay de depuracion (tambien captura teclas mientras esta abierto)
    update_overlay(dlg_open)

    -- Tecla 0: volver a la escena principal (flanco; no durante una transicion)
    local bdown = is_action_activated("back")
    if bdown and not was_back and c.back_scene and not transition and not dlg_open and not ov.open then
      load_scene(c.back_scene)
    end
    was_back = bdown

    -- El dialogo va despues de puertas e interaccion: la E que lo cierra ya fue consumida
    dialogue.update(dt)

    -- Textos: solo con la pantalla despejada (los rects HUD se pintan bajo el
    -- texto y el fundido quedaria tapado por el)
    if fade.alpha() == 0 and not dialogue.is_open() and not ov.open then
      if toast.left > 0 then
        toast.left = toast.left - dt
        draw_centered(toast.text, 12)
      end
      if line.left > 0 then
        line.left = line.left - dt
        draw_centered(line.text, 226)
      elseif prompt then
        draw_centered(prompt, 226)
      end
    end

    draw_overlay()

    fade.draw() -- siempre el ultimo
  end
end

return M
