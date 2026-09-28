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

-- La barra de vida se pone roja por debajo de un tercio
local function draw_health(entity, y)
  local hp, hp_max = get_health(entity), get_max_health(entity)
  local hp_g = hp * 3 >= hp_max and 220 or 60
  draw_text(HUD_X, y, string.format("HP:    %8d / %d", hp, hp_max), "default", 255, hp_g, 60)
end

-- Equipo: una linea por herramienta, en el orden con el que el loader las
-- guardo (alfabetico si vienen de la escena). Iteracion por indice 1-based
-- porque table.* no existe en este motor. Devuelve cuantas lineas ocupo.
local function draw_equipment(entity, y)
  local equipment_count = get_equipment_count(entity)
  for i = 1, equipment_count do
    local eq_name, eq_level = get_equipment_at(entity, i)
    draw_text(HUD_X, y + i * LINE_HEIGHT, string.format("%s: %d", eq_name, eq_level), "default", 180, 200, 255)
  end
  return equipment_count
end

-- Bodega: total/capacidad y una linea por item, misma iteracion que el equipo
local function draw_cargo(entity, y)
  local cargo_total, cargo_capacity = get_inventory_total(entity), get_inventory_capacity(entity)
  draw_text(HUD_X, y, string.format("Cargo: %d / %d", cargo_total, cargo_capacity), "default", 180, 255, 180)

  local inventory_count = get_inventory_count(entity)
  for i = 1, inventory_count do
    local item_name, item_qty = get_inventory_at(entity, i)
    draw_text(HUD_X, y + i * LINE_HEIGHT, string.format("%s: %d", item_name, item_qty), "default", 180, 255, 180)
  end
end

-- Etiqueta en coordenadas del mundo: sigue a la nave
local function draw_world_label(entity)
  local x, y = get_position(entity)
  draw_text_world(x - 30, y - 60, "PLAYER", "default", 255, 200, 0)
end

-- El HUD se vuelve a pedir cada frame
function player_hud_module.draw(entity)
  local hp_y = 130

  draw_debug_stats(entity)
  draw_health(entity, hp_y)
  local equipment_lines = draw_equipment(entity, hp_y)
  draw_cargo(entity, hp_y + (equipment_lines + 1) * LINE_HEIGHT)
  draw_world_label(entity)
end

return player_hud_module
