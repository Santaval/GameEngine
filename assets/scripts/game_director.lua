-- Director de la partida: entidad invisible (solo script) que muestra el
-- game over cuando muere el jugador y permite reiniciar o volver al menu.
-- player.lua pone el global game_over en true desde su on_death.
local ui = require("ui_helpers")

local GAME_SCENE = "./assets/scripts/scenes/solar_system.lua"
local MENU_SCENE = "./assets/scripts/scenes/menu.lua"

-- Segundos antes de mostrar el cartel: deja ver la explosion y evita que un
-- ENTER apretado justo al morir reinicie sin querer
local GAME_OVER_DELAY = 1.0

local game_over_timer = 0
-- Para distinguir "se cayo el servidor" de "nunca nos conectamos"
local was_online = false
local confirm_pressed = ui.edge("confirm")
local menu_pressed = ui.edge("menu")

-- Cartel cuando se pierde la conexion (NetClient reintenta solo). Si se
-- reconecta, el welcome y el snapshot_request resincronizan y el cartel se va
local function draw_connection_lost(to_menu)
  local w, h = get_window_size()
  local cy = h / 2
  draw_rect(0, cy - 70, w, 140, 0, 0, 0, 170)
  ui.draw_centered(cy - 40, "Connection to server lost - reconnecting...", "debug-big", 28, 255, 120, 120)
  ui.draw_centered(cy + 20, "M  -  Main menu", "debug-big", 28, 180, 180, 180)
  if to_menu then
    load_scene(MENU_SCENE)
  end
end

function update()
  local status = net_status()
  if status == "online" then was_online = true end

  if not game_over then
    -- menu_pressed se consulta siempre (lo comparte el game over)
    local to_menu = menu_pressed()
    if was_online and status == "connecting" then
      draw_connection_lost(to_menu)
    end
    return
  end

  game_over_timer = game_over_timer + get_delta_time()
  if game_over_timer < GAME_OVER_DELAY then return end

  local w, h = get_window_size()
  local cy = h / 2

  draw_rect(0, 0, w, h, 0, 0, 0, 140)
  ui.draw_centered(cy - 100, "GAME OVER", "title", 56, 255, 80, 80)
  ui.draw_centered(cy, "ENTER  -  Restart", "debug-big", 28, 255, 255, 255)
  ui.draw_centered(cy + 50, "M  -  Main menu", "debug-big", 28, 180, 180, 180)

  -- Los detectores se consultan siempre, para que el estado de las teclas
  -- quede al dia aunque se aprete una sola
  local restart = confirm_pressed()
  local to_menu = menu_pressed()

  if restart then
    load_scene(current_game_scene or GAME_SCENE)
  elseif to_menu then
    load_scene(MENU_SCENE)
  end
end
