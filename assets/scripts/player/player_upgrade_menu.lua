local player_upgrades_module = require("player_upgrades")

local player_upgrade_menu_module = {}

-- Las filas llegan a ~40 caracteres (~10 px c/u con la fuente default de 16)
local PANEL_WIDTH = 420
local MARGIN = 20
local LINE_HEIGHT = 22
local FEEDBACK_DURATION = 1.5

local is_open = false

-- is_action_activated reporta la tecla sostenida, no un flanco: mismo patron
-- que player_visual_helpers.lua para reaccionar una sola vez por tecla. Se
-- actualizan siempre, esten el panel abierto o no, para no arrastrar un
-- flanco viejo cuando se reabre.
local toggle_was_down = false
local upgrade_key_was_down = { false, false, false }

local feedback_text = ""
local feedback_timer = 0

local function set_feedback(text)
  feedback_text = text
  feedback_timer = FEEDBACK_DURATION
end

local function try_purchase(entity, index)
  local upgrade = player_upgrades_module.UPGRADES[index]
  if player_upgrades_module.purchase(entity, index) then
    local new_level = get_equipment_level(entity, upgrade.equipment)
    set_feedback(string.format("%s -> L%d", upgrade.label, new_level))
  else
    set_feedback("Not enough resources")
  end
end

-- El barco sigue volando y disparando mientras el panel esta abierto (multi-
-- jugador: no hay pausa). 1/2/3/E no chocan con W/S/T/C ni con el mouse.
function player_upgrade_menu_module.update(entity)
  local toggle_down = is_action_activated("toggle_upgrades")
  local toggle_edge = toggle_down and not toggle_was_down
  toggle_was_down = toggle_down
  if toggle_edge then
    is_open = not is_open
  end

  local upgrade_edge = { false, false, false }
  for i = 1, 3 do
    local down = is_action_activated("upgrade_" .. i)
    upgrade_edge[i] = down and not upgrade_key_was_down[i]
    upgrade_key_was_down[i] = down
  end

  if is_open then
    for i = 1, 3 do
      if upgrade_edge[i] then try_purchase(entity, i) end
    end
  end

  if feedback_timer > 0 then
    feedback_timer = math.max(0, feedback_timer - get_delta_time())
  end
end

local function affordability_color(entity, index, level)
  if level >= player_upgrades_module.MAX_LEVEL then return 150, 150, 150 end
  if player_upgrades_module.can_afford(entity, index) then return 120, 255, 120 end
  return 220, 90, 90
end

-- table.concat no existe en este motor: se arma el string a mano
local function format_cost(costs)
  local text = ""
  for i, cost in ipairs(costs) do
    if i > 1 then text = text .. "  " end
    text = text .. string.format("%s %d", cost.name, cost.qty)
  end
  return text
end

local function draw_upgrade_row(entity, index, x, y)
  local upgrade = player_upgrades_module.UPGRADES[index]
  local level = get_equipment_level(entity, upgrade.equipment)
  local r, g, b = affordability_color(entity, index, level)

  if level >= player_upgrades_module.MAX_LEVEL then
    draw_text(x, y, string.format("[%d] %s L%d   MAX", index, upgrade.label, level), "default", r, g, b)
    return
  end

  local cost_text = format_cost(player_upgrades_module.get_cost(entity, index))
  draw_text(x, y, string.format("[%d] %s L%d -> L%d   %s", index, upgrade.label, level, level + 1, cost_text),
    "default", r, g, b)
end

-- Panel compacto anclado arriba a la derecha, para no tapar el area de juego
function player_upgrade_menu_module.draw(entity)
  if not is_open then return end

  local screen_w, _ = get_screen_size()
  local panel_x = screen_w - PANEL_WIDTH - MARGIN
  local panel_y = MARGIN
  local row_count = 2 + #player_upgrades_module.UPGRADES + 1  -- titulo + recursos + filas + feedback
  local panel_height = LINE_HEIGHT * row_count + MARGIN

  draw_rect(panel_x, panel_y, PANEL_WIDTH, panel_height, 0, 0, 0, 160)
  draw_rect(panel_x, panel_y, PANEL_WIDTH, panel_height, 255, 255, 255, 255, false)

  local text_x = panel_x + 12
  local y = panel_y + 10

  draw_text(text_x, y, "UPGRADES  [E] close", "default", 255, 255, 255)
  y = y + LINE_HEIGHT

  draw_text(text_x, y, string.format("iron %d  gunpowder %d  plasma %d",
    get_item_count(entity, "iron"), get_item_count(entity, "gunpowder"), get_item_count(entity, "plasma")),
    "default", 180, 200, 255)
  y = y + LINE_HEIGHT

  for i = 1, #player_upgrades_module.UPGRADES do
    draw_upgrade_row(entity, i, text_x, y)
    y = y + LINE_HEIGHT
  end

  if feedback_timer > 0 then
    draw_text(text_x, y, feedback_text, "default", 255, 220, 120)
  end
end

return player_upgrade_menu_module
