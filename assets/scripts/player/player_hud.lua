local ship_overlay_module = require("ship_overlay")

local player_hud_module = {}

local LINE_HEIGHT = 22
local HUD_X = 20

local function draw_debug_stats(entity)
  local x, y = get_position(entity)
  local vx, vy = get_velocity(entity)
  local speed = math.sqrt(vx * vx + vy * vy)
  local dt = get_delta_time()

  draw_text(HUD_X, 20, string.format("Pos:   %8.1f , %8.1f", x, y), "default", 255, 255, 255)
  draw_text(HUD_X, 42, string.format("Vel:   %8.1f , %8.1f", vx, vy), "default", 120, 220, 255)
  draw_text(HUD_X, 64, string.format("Speed: %8.1f", speed), "default", 120, 220, 255)
  draw_text(HUD_X, 86, string.format("Rot:   %8.2f", get_rotation(entity)), "default", 200, 200, 120)
  draw_text(HUD_X, 108, string.format("FPS:   %8.0f", 1.0 / math.max(dt, 0.0001)), "default", 200, 200, 120)
end

-- Bodega: total/capacidad y una linea por item. Iteracion por indice 1-based
-- porque table.* no existe en este motor
local function draw_cargo(entity, y)
  local cargo_total, cargo_capacity = get_inventory_total(entity), get_inventory_capacity(entity)
  draw_text(HUD_X, y, string.format("Cargo: %d / %d", cargo_total, cargo_capacity), "default", 180, 255, 180)

  local inventory_count = get_inventory_count(entity)
  for i = 1, inventory_count do
    local item_name, item_qty = get_inventory_at(entity, i)
    draw_text(HUD_X, y + i * LINE_HEIGHT, string.format("%s: %d", item_name, item_qty), "default", 180, 255, 180)
  end
end

-- Nombre, niveles y barra de vida encima de la nave (igual que las remotas)
local function draw_ship_overlay(entity)
  local x, y = get_position(entity)
  ship_overlay_module.draw(x, y, "PLAYER", 255, 200, 0,
    get_health(entity), get_max_health(entity),
    get_equipment_level(entity, "engine"),
    get_equipment_level(entity, "shield"),
    get_equipment_level(entity, "gun"))
end

-- El HUD se vuelve a pedir cada frame
function player_hud_module.draw(entity)
  draw_debug_stats(entity)
  draw_cargo(entity, 130)
  draw_ship_overlay(entity)
end

return player_hud_module
