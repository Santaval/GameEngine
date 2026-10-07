local ui = require("ui_helpers")

local GAME_SCENE = "./assets/scripts/scenes/solar_system.lua"

local confirm_pressed = ui.edge("confirm")
local quit_pressed = ui.edge("quit")

function update()
  local w, h = get_window_size()
  local cy = h / 2

  draw_rect(0, cy - 160, w, 300, 0, 0, 0, 160)

  ui.draw_centered(cy - 120, "ASTEROID MINER", "title", 56, 255, 220, 120)
  ui.draw_centered(cy, "ENTER  -  Start", "debug-big", 28, 255, 255, 255)
  ui.draw_centered(cy + 50, "Q  -  Quit", "debug-big", 28, 180, 180, 180)

  if confirm_pressed() then
    load_scene(GAME_SCENE)
  elseif quit_pressed() then
    quit_game()
  end
end
