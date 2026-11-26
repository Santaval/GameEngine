-- Mundo del demo de walker: 640x480 (mayor que la pantalla logica de 480x270).
-- Los muros estaticos se crean una vez (se borran solos al cargar otra escena) y
-- se dibujan cada frame, porque las cajas estaticas no se ven por si solas.
-- Los rects se pintan por encima de las entidades: el suelo es solo una rejilla
-- fina y los muros/bloques son macizos (el jugador no puede entrar en ellos).
local WORLD_W, WORLD_H = 640, 480
local T = 16 -- grosor de los muros del borde, justo fuera del mundo

local walls = {
  { -T, -T, WORLD_W + 2 * T, T },
  { -T, WORLD_H, WORLD_W + 2 * T, T },
  { -T, 0, T, WORLD_H },
  { WORLD_W, 0, T, WORLD_H },
}
local blocks = {
  { 160, 120, 64, 48 },
  { 320, 260, 48, 96 },
  { 480, 100, 80, 32 },
  { 100, 340, 96, 32 },
}

local created = false
local was_down = false

update = function()
  if not created then
    created = true
    for _, r in ipairs(walls) do add_static_box(r[1], r[2], r[3], r[4]) end
    for _, r in ipairs(blocks) do add_static_box(r[1], r[2], r[3], r[4]) end
  end

  -- Rejilla de suelo cada 32 px
  for x = 0, WORLD_W, 32 do draw_rect_world(x, 0, 1, WORLD_H, 90, 90, 100, 90, true) end
  for y = 0, WORLD_H, 32 do draw_rect_world(0, y, WORLD_W, 1, 90, 90, 100, 90, true) end
  -- Limites del mundo
  draw_rect_world(0, 0, WORLD_W, WORLD_H, 255, 255, 255, 255, false)
  for _, r in ipairs(walls) do draw_rect_world(r[1], r[2], r[3], r[4], 60, 40, 40, 255, true) end
  for _, r in ipairs(blocks) do draw_rect_world(r[1], r[2], r[3], r[4], 120, 90, 60, 255, true) end

  -- Volver al demo de efectos (tecla 0, flanco de subida)
  local down = is_action_activated("back")
  if down and not was_down then load_scene("scenes/main.lua") end
  was_down = down
end
