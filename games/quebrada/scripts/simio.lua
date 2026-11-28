-- Pelea contra el simio de los Caliles (mision volver_casa). Pegamento entre simio_logic (puro), la entidad,
-- la HUD y la entrada del jugador. El machete (tools.lua) llama a M.attack por el global `machete_hook`.
-- Estado local: se reinicia con cada escena (las entidades tampoco sobreviven a load_scene).
-- Reglas de entrada: player_walker.input puede ser "keyboard" (texto) o una funcion; aqui se sustituye por un
-- stub / empujon y se devuelve el valor guardado. Soltar SIEMPRE el override antes de dialogue.start y fade.start_out.
-- Docs: games/quebrada/docs/missions.md (volver_casa)
local ws = require("world_state")
local tod = require("time_of_day")
local fade = require("fade")
local dialogue = require("dialogue")
local npc = require("npc_placeholder")
local logic = require("simio_logic")

local CFG = logic.CONFIG
local M = {}

M.SPAWN = { x = 7712, y = 2044 }                       -- pies del simio: calle de los Caliles, bajo el cruce
M.RETRY = { x = 7588, y = 1784, facing = "right" }     -- esquina del jugador al reintentar (pies ~ (7600,1816), acera norte)
M.LABEL = "¿...?"

local st = nil              -- estado logico (nil = no hay pelea)
local ent, light = nil, nil
local vfx = {}              -- { { e = entidad, t = segundos } }
local held_fn, saved_input = nil, nil
local knock_t, knock_dx, knock_dy = 0, 0, 0
local flash, notice, notice_left = 0, "", 0
local slash_pending = false
local stage = nil           -- "lost" (fundido de derrota) | "rearm" (re-armar tras el fundido)
local telegraph = false
local hit_flash = 0         -- s con la etiqueta del simio en blanco tras recibir un golpe
local hit_pop = nil         -- { t, x, y }: "-1" que sube sobre el simio

local STUB = function() return 0, 0, false end
local KNOCK = function() return knock_dx, knock_dy, true end

-- ---- entrada del jugador ----
local function story_open()
  local ok, s = pcall(require, "story")
  return ok and s.is_open() or false
end

local function hold(fn)
  if not player_walker then return false end
  if held_fn == nil then
    if dialogue.is_open() or story_open() then return false end
    saved_input = player_walker.input
  end
  player_walker.input = fn
  held_fn = fn
  return true
end

local function release()
  if held_fn and player_walker and player_walker.input == held_fn then player_walker.input = saved_input end
  held_fn, saved_input = nil, nil
end

-- ---- entidades ----
local function say(text, secs) notice, notice_left = text, secs or 2 end

local function spawn_simio()
  ent = npc.spawn({ id = "simio", x = st.sx - 12, y = st.sy - 34, dir = "up" })
  light = add_light(st.sx, st.sy - 14, 46, 255, 150, 110, 0.5)
  if light and light <= 0 then light = nil end
end

local function destroy()
  if ent then pcall(destroy_entity, ent) end
  if light then pcall(remove_light, light) end
  for _, v in ipairs(vfx) do pcall(destroy_entity, v.e) end
  ent, light, vfx, st, telegraph = nil, nil, {}, nil, false
  hit_flash, hit_pop = 0, nil
  if ws.has("mona.battle") then ws.set("mona.battle", nil) end
end

local function effect(tag, x, y, flip)
  local e = create_entity()
  add_transform(e, x, y, 1, 1, 0)
  add_sprite(e, "vfx_machete", 32, 32)
  add_animation_atlas(e, "vfx_machete", tag, false)
  if flip and set_sprite_flip then set_sprite_flip(e, true) end
  vfx[#vfx + 1] = { e = e, t = 0.3 }
end

-- ---- API ----
function M.is_fighting() return st ~= nil end

-- El machete (tools.lua) pide un golpe: el siguiente step lo resuelve. true = habra golpe
function M.attack()
  if not st or st.phase == "appear" or st.phase == "flee" or st.slash_cd > 0 then return false end
  slash_pending = true
  return true
end
machete_hook = M.attack -- global: el machete lo lee con rawget(_G, "machete_hook")

function M.reset()
  release()
  destroy()
  stage, slash_pending, knock_t = nil, false, 0
end

function M.start(short)
  release()
  destroy()
  ws.set("mona.battle", true)
  pcall(function() require("tools").select_id("machete") end)
  st = logic.new(CFG, M.SPAWN.x, M.SPAWN.y)
  spawn_simio()
  slash_pending, stage = false, nil
  if short then
    say("(Otra vez esa cosa...)", 2.5)
  else
    dialogue.start(dialogue.scripts.simio_aparece, { on_end = function() ws.set("volver.simio_visto", true) end })
  end
end

local function retry()
  release()
  destroy()
  if player_entity and player_walker then
    set_position(player_entity, M.RETRY.x, M.RETRY.y)
    set_velocity(player_entity, 0, 0)
    player_walker:set_facing(M.RETRY.facing)
    player_walker.cam_state = {}
  end
  stage = "rearm"
  fade.start_in()
end

local function win()
  release()
  destroy()
  ws.set("volver.simio_vencido", true)
  local started = dialogue.start(dialogue.scripts.simio_huye, {
    on_end = function() pcall(function() require("save").autosave() end) end,
  })
  if not started then pcall(function() require("save").autosave() end) end
end

-- ---- HUD (en pantalla: draw_rect_world se oscurece con la noche) ----
local function draw_box(text, y, r, g, b)
  local sw = get_screen_size()
  local w = #text * 6 + 16
  local x = math.floor((sw - w) / 2)
  draw_rect(x, y, w, 16, 10, 10, 20, 220, true)
  draw_rect(x, y, w, 16, r, g, b, 255, false)
  draw_text(x + 8, y + 3, text, "default", r, g, b, 255)
end

local function draw_hud()
  local sw, sh = get_screen_size()
  if flash > 0 then draw_rect(0, 0, sw, sh, 150, 0, 0, math.floor(120 * math.min(1, flash / 0.5)), true) end
  if notice_left > 0 then draw_box(notice, 90, 255, 200, 130) end
  if not st then return end
  -- Barra de vida sobre la cabeza del simio (coordenadas de pantalla = mundo - camara) y "-1" al golpearlo
  if ent and get_camera_position then
    local cx, cy = get_camera_position()
    local bx, by = math.floor(st.sx - cx - 18), math.floor(st.sy - cy - 52)
    draw_rect(bx - 1, by - 1, 38, 7, 10, 10, 20, 230, true)
    draw_rect(bx, by, math.floor(36 * math.max(0, st.hp) / CFG.simio_hp), 5, 220, 70, 60, 255, true)
    draw_rect(bx - 1, by - 1, 38, 7, 235, 225, 200, 255, false)
    if hit_pop then
      local k = 1 - hit_pop.t / 0.6
      draw_text(math.floor(hit_pop.x - cx), math.floor(hit_pop.y - cy - k * 16), "-1", "default", 255, 230, 120, 255)
    end
  end
  for i = 1, CFG.player_hp do
    local on = i <= st.php
    draw_rect(8 + (i - 1) * 10, 8, 8, 8, on and 220 or 60, on and 50 or 50, on and 50 or 60, 255, true)
  end
  local w = 120
  local x = math.floor((sw - w) / 2)
  draw_text(math.floor((sw - #M.LABEL * 6) / 2), 58, M.LABEL, "default", 255, 140, 120, 255)
  draw_rect(x, 70, w, 5, 40, 30, 30, 230, true)
  draw_rect(x, 70, math.floor(w * math.max(0, st.hp) / CFG.simio_hp), 5, 220, 70, 60, 255, true)
  draw_rect(x, 70, w, 5, 235, 225, 200, 255, false)
end

-- ---- cada frame (walkback.tick) ----
function M.tick(dt)
  if flash > 0 then flash = flash - dt end
  if notice_left > 0 then notice_left = notice_left - dt end
  if hit_pop then hit_pop.t = hit_pop.t + dt; if hit_pop.t >= 0.6 then hit_pop = nil end end
  if hit_flash > 0 then
    hit_flash = hit_flash - dt
    if hit_flash <= 0 and ent and not telegraph then set_text_color(ent, 255, 140, 120, 255) end -- fin del destello
  end
  -- (el Lua del motor no trae `table`: se reconstruye la lista a mano)
  local alive = {}
  for _, v in ipairs(vfx) do
    v.t = v.t - dt
    if v.t <= 0 then pcall(destroy_entity, v.e) else alive[#alive + 1] = v end
  end
  vfx = alive
  if not player_entity then return end
  if stage == "rearm" then
    if not fade.is_active() and not tod.is_busy() then stage = nil; M.start(true) end
    return
  end
  if stage == "lost" then return end
  if held_fn == KNOCK then
    knock_t = knock_t - dt
    if knock_t <= 0 then release() end
  end
  if not st then return end

  local px, py = get_position(player_entity)
  px, py = px + 12, py + 32
  local blocked = tod.is_busy() or fade.is_active()
  local paused = dialogue.is_open() or story_open() or ws.has("libreta.open")
  if fade.alpha() <= 0 and not dialogue.is_open() then draw_hud() end
  if blocked then return end
  local mover = st.phase == "appear" or st.phase == "flee"
  if paused and not mover then slash_pending = false; return end

  local do_slash = slash_pending and not paused
  slash_pending = false
  local facing = player_walker and player_walker:get_facing() or "down"
  if do_slash and get_mouse_world_position then
    -- El golpe va hacia el cursor (el clic usa la herramienta): el jugador se orienta hacia el
    local mx, my = get_mouse_world_position()
    if mx and (math.abs(mx - px) > 4 or math.abs(my - (py - 8)) > 4) then
      facing = logic.dir_name(mx - px, my - (py - 8))
      if player_walker then player_walker:set_facing(facing) end
    end
  end
  local evs = logic.step(st, CFG, dt, { px = px, py = py, slash = do_slash, facing = facing })

  -- entidad y luz siguen al estado logico
  if ent then
    set_position(ent, st.sx - 12, st.sy - 34)
    local moving = st.phase == "appear" or st.phase == "chase" or st.phase == "lunge" or st.phase == "flee"
    play_animation(ent, (moving and "walk_" or "idle_") .. st.dir, true)
    if telegraph and st.phase ~= "windup" then
      telegraph = false
      set_text(ent, M.LABEL); set_text_color(ent, 255, 140, 120, 255)
    end
  end
  if light then set_light(light, { x = st.sx, y = st.sy - 14 }) end

  local vx, vy = logic.facing_vec(facing)
  for _, e in ipairs(evs) do
    if e == "windup" and ent then
      telegraph = true
      set_text(ent, "!!"); set_text_color(ent, 255, 60, 40, 255)
    elseif e == "simio_hit" then
      effect("hit", st.sx - 16, st.sy - 33)
      say("¡Le diste!", 1)
      hit_pop = { t = 0, x = st.sx - 4, y = st.sy - 40 }
      hit_flash = 0.15
      if ent then set_text_color(ent, 255, 255, 255, 255) end -- etiqueta blanca un instante
    elseif e == "simio_down" then
      say("¡Lo tumbaste!", 2)
    elseif e == "player_hit" then
      knock_dx, knock_dy, knock_t = st.kdx, st.kdy, CFG.knock_time
      hold(KNOCK)
      flash = 0.5
      say("¡Te alcanzó!", 1.2)
    elseif e == "player_down" then
      release()
      hold(STUB)
      stage = "lost"
      fade.start_out(retry)
    elseif e == "gone" then
      win()
      return
    end
    if e == "simio_hit" or e == "miss" then
      effect("slash", px + vx * 22 - 16, py - 8 + vy * 22 - 16, facing == "left")
    end
  end

  -- huir de la pelea: la pelea se reinicia sin bloquear nada (volvera a empezar al pisar la franja)
  if st and (st.phase == "chase" or st.phase == "windup" or st.phase == "lunge" or st.phase == "recover" or st.phase == "stagger")
      and not logic.leashed(CFG, px, py) then
    M.reset()
    say("(Se metió otra vez en los Caliles...)", 3)
  end
end

return M
