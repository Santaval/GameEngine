-- Inicio de la partida (issue #82, refinado): el jugador nace en la casa de mama, de dia.
--   1. mama: "ya alistate que tienes que ir a misa"  (on_start de la casa)
--   2. un indicador senala la puerta de salida
--   3. al ir a la puerta, mama lo detiene: avisa de la luz y pregunta si quiere oir la historia (decision)
--   4. sin preguntar por la mision: bendicion, la mision se acepta sola y fundido a la iglesia,
--      donde la llegada a walk_start empieza la noche.
-- Pegamento entre dialogos, historia, guardado y fundido; la logica de la mision esta en mission_defs.lua.
-- Los requires de los dialogos van dentro de las funciones (dialogues.lua pide este modulo).
-- Docs: games/quebrada/docs/missions.md
local ws = require("world_state")
local missions = require("missions")
local save = require("save")
local libreta = require("libreta")
local dialogue = require("dialogue")
local fade = require("fade")
local tod = require("time_of_day")

local M = {}

M.FOCO_SHELF = { x = 96, y = 24 } -- linterna de maps/house_mama.tmx (x 88-104, y 24)
M.EXIT_DOOR = { x = 96, y = 128 } -- puerta de salida de maps/house_mama.tmx (centro del borde superior del rect)

local want_story = false -- el jugador pidio oir la historia
local stage = nil        -- nil | "listening" (esperando que termine la historia) | "morning"
local clock = 0

-- La historia entra en la libreta aunque el jugador nunca la haya escuchado
local function record_story()
  if not ws.has("story.chequelo.started") then
    ws.set("story.chequelo.started", true)
    libreta.notify() -- historia nueva en la libreta (issue #80)
  end
end

-- Mision aceptada (sin preguntar), guardado y fundido a la puerta de la iglesia
local function go_to_church()
  missions.offer("chequelo")
  missions.accept("chequelo")
  ws.set("mama.avisada", true)
  ws.set("intro.bendecido", true)
  record_story()
  if player_walker then player_walker.input = function() return 0, 0, false end end
  fade.start_out(function()
    ws.set_ctx({ arrival = { map = "maps/zona1.tmx", spawn = "default" } })
    save.autosave({ map = "maps/zona1.tmx", scene = "scenes/main.lua" })
    load_scene("scenes/main.lua")
  end)
end

local function bless()
  local s = dialogue.scripts.mama_bendicion
  if not dialogue.start(s, { on_end = go_to_church }) then go_to_church() end
end

-- Eleccion "Si, quiero oirla" del dialogo mama_luz
function M.want_story() want_story = true end

-- Fin del aviso de mama: con la historia pedida se escucha primero; si no, bendicion directa
local function after_warning()
  if want_story then
    want_story = false
    stage = "listening"
    require("story").listen("chequelo")
  else
    bless()
  end
end

-- Regreso de la noche: fundido a la casa de mama, donde ella lo recibe (on_start -> regreso)
function M.go_home()
  if player_walker then player_walker.input = function() return 0, 0, false end end
  fade.start_out(function()
    ws.set_ctx({
      arrival = { map = "maps/house_mama.tmx", spawn = "inside_door", facing = "up" },
      return_map = "maps/zona1.tmx", return_spawn = "exit_mama", return_facing = "down",
    })
    save.autosave({ map = "maps/house_mama.tmx", scene = "scenes/house_demo.lua" })
    load_scene("scenes/house_demo.lua")
  end)
end

-- Tras la charla de la noche: fundido, "a la manana siguiente" (dia nuevo) y mama pide las papas
local function morning()
  fade.start_out(function()
    ws.set("regreso.pendiente", nil)
    tod.set("day", { title = "A la mañana siguiente..." })
    stage = "morning"
    fade.start_in()
  end)
end

-- Paso 1 (on_start de la casa): solo de dia y mientras no se haya ido a misa
function M.on_start()
  if ws.has("regreso.pendiente") then
    if not dialogue.start(dialogue.scripts.mama_regreso, { on_end = morning }) then morning() end
    return
  end
  if ws.has("intro.bendecido") or ws.has("intro.alistado") or tod.get() ~= "day" then return end
  if missions.state("chequelo") ~= "none" then return end
  dialogue.start(dialogue.scripts.mama_alistate, { on_end = function() ws.set("intro.alistado", true) end })
end

local function pending_exit()
  return ws.has("intro.alistado") and not ws.has("intro.bendecido") and missions.state("chequelo") == "none"
end

-- Pasos 2 y 3 (cfg.on_door): la puerta de salida no sale; mama avisa. Devuelve true si consume la puerta
function M.on_door(door)
  local p = door and door.properties or {}
  if p.target_map ~= "@return" or not pending_exit() then return false end
  -- Sin el foco no sale: mama lo manda a tomarlo de la repisa
  if not require("tools").has("foco") then
    dialogue.start(dialogue.scripts.mama_foco)
    return true
  end
  dialogue.start(dialogue.scripts.mama_luz, { on_end = after_warning })
  return true
end

-- Flags de la caminata de la noche (los mismos que limpia chequelo_triggers.walk_start)
local WALK_FLAGS = {
  "chequelo.on_road", "chequelo.off_road", "chequelo.light_appears", "chequelo.detour",
  "chequelo.detour_cafetal", "chequelo.detour_door", "chequelo.arrived", "chequelo.silbidos",
}

-- Reintentar la noche: fundido, mision de nuevo en `accepted`, de dia, y aparece en la puerta de la
-- iglesia; entrar en walk_start vuelve a empezar la noche
function M.restart_night()
  if player_walker then player_walker.input = function() return 0, 0, false end end
  fade.start_out(function()
    for _, f in ipairs(WALK_FLAGS) do ws.set(f, nil) end
    ws.set("chequelo.ending", nil)
    missions.jump("chequelo", "accepted")
    tod.set("day", { instant = true, advance_day = false })
    ws.set_ctx({ arrival = { map = "maps/zona1.tmx", spawn = "default" } })
    save.autosave({ map = "maps/zona1.tmx", scene = "scenes/main.lua" })
    load_scene("scenes/main.lua")
  end)
end

-- El chequelo te encontro (3 silbidos): reintentar desde la iglesia o rendirse (mision fallida)
function M.on_caught()
  local opts = { on_end = nil }
  if not dialogue.start(dialogue.scripts.chequelo_fallo, opts) then M.restart_night() end
end

-- Cada frame (cfg.on_tick): indicador sobre la puerta y espera del fin de la historia
function M.tick(dt)
  clock = clock + dt
  if stage == "morning" then
    if not tod.is_busy() and not fade.is_active() and not dialogue.is_open() then
      stage = nil
      dialogue.start(dialogue.scripts.mama_papas, {
        on_end = function()
          missions.offer("papas")
          missions.accept("papas")
          save.autosave()
        end,
      })
    end
    return
  end
  if stage == "listening" then
    local story = require("story")
    if not story.is_open() and not dialogue.is_open() then
      stage = nil
      bless()
    end
    return
  end
  if pending_exit() and not dialogue.is_open() and not fade.is_active() then
    local bob = math.floor(math.sin(clock * 5) * 2 + 0.5)
    -- Primero el foco (linterna de la repisa); con el foco en mano, la puerta
    local at = require("tools").has("foco") and M.EXIT_DOOR or M.FOCO_SHELF
    draw_text_world(at.x - 3, at.y - 20 + bob, "v", "default", 255, 220, 80, 255)
  end
end

return M
