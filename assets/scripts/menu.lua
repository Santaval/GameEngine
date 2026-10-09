local ui = require("ui_helpers")

local GAME_SCENE = "./assets/scripts/scenes/aval_cup.lua"

-- Segundos antes de avisar que el servidor no responde
local SLOW_CONNECT_TIME = 5
-- Segundos que se muestra el aviso de "falta --server"
local NO_SERVER_MSG_TIME = 4

local confirm_pressed = ui.edge("confirm")
local quit_pressed = ui.edge("quit")
local multiplayer_pressed = ui.edge("multiplayer")
local back_pressed = ui.edge("back")

-- Volver al menu siempre termina la sesion: los demas reciben peer_left
net_disconnect()

local connecting = false
local connect_timer = 0
local no_server_timer = 0

function update()
  local w, h = get_window_size()
  local cy = h / 2

  draw_rect(0, cy - 160, w, 400, 0, 0, 0, 160)

  ui.draw_centered(cy - 120, "ASTEROID MINER", "title", 56, 255, 220, 120)

  -- Los detectores se consultan siempre, para que el estado de las teclas
  -- quede al dia aunque se aprete una sola
  local confirm = confirm_pressed()
  local quit = quit_pressed()
  local multiplayer = multiplayer_pressed()
  local back = back_pressed()

  if connecting then
    ui.draw_centered(cy, "Connecting to " .. net_server_url() .. "...", "debug-big", 28, 255, 255, 255)
    connect_timer = connect_timer + get_delta_time()
    if connect_timer > SLOW_CONNECT_TIME then
      ui.draw_centered(cy + 40, "Server not responding (still retrying)", "debug-big", 28, 255, 120, 120)
    end
    ui.draw_centered(cy + 90, "BACKSPACE  -  Cancel", "debug-big", 28, 180, 180, 180)

    if net_status() == "online" then
      -- game_director.lua reinicia esta escena al morir
      current_game_scene = GAME_SCENE
      load_scene(GAME_SCENE)
    elseif back then
      net_disconnect()
      connecting = false
    end
    return
  end

  ui.draw_centered(cy, "ENTER  -  Aval Cup (single player)", "debug-big", 28, 255, 255, 255)
  ui.draw_centered(cy + 50, "M  -  Aval Cup (multiplayer)", "debug-big", 28, 255, 255, 255)
  ui.draw_centered(cy + 100, "Q  -  Quit", "debug-big", 28, 180, 180, 180)

  if no_server_timer > 0 then
    no_server_timer = no_server_timer - get_delta_time()
    ui.draw_centered(cy + 150, "Multiplayer needs --server <url> or GAME_SERVER", "default", 16, 255, 120, 120)
  end

  if confirm then
    current_game_scene = GAME_SCENE
    load_scene(GAME_SCENE)
  elseif multiplayer then
    if net_connect() then
      connecting = true
      connect_timer = 0
    else
      no_server_timer = NO_SERVER_MSG_TIME
    end
  elseif quit then
    quit_game()
  end
end
