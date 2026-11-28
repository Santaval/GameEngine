-- NPC placeholders (issue #56): entidades con el personaje grey de sprites/dummy.png (24x38)
-- y una etiqueta con el nombre encima de la cabeza. El motor no tiene tinte de sprite, asi que
-- cada NPC se distingue por el color de su etiqueta (add_text sigue a la entidad).
-- Los sprites van registrados en la escena (assetId "dummy"); el spawn solo crea la entidad.
local M = {}

M.SPRITE_ID = "dummy"
M.SPRITE_W = 24
M.SPRITE_H = 38
M.FONT = "default"
M.DIRS = { down = true, up = true, left = true, right = true }

-- Roster de la zona 1: id -> nombre visible y color de la etiqueta (r, g, b).
M.ROSTER = {
  mama = { name = "Mamá", color = { 255, 214, 120 } },
  papa = { name = "Papá", color = { 150, 200, 255 } },
  tio = { name = "Tío", color = { 190, 255, 160 } },
  lencho = { name = "Ño Lencho", color = { 255, 150, 150 } },
  chayo = { name = "Ña Chayo", color = { 230, 170, 255 } },
  tina = { name = "Ña Tina", color = { 255, 255, 255 } },
}

-- Posicion de la etiqueta respecto a la esquina superior izquierda del sprite: centrada
-- en X y justo encima de la cabeza. Funcion pura (sin motor) para poder reutilizarla.
function M.label_offset(text_w, text_h, sprite_w)
  return math.floor((sprite_w - text_w) / 2), -(text_h + 2)
end

-- def = { id, x, y, dir?, name? }. id busca el nombre y el color en ROSTER.
-- Devuelve la entidad creada (existe en el siguiente frame, como cualquier create_entity).
function M.spawn(def)
  local info = M.ROSTER[def.id] or {}
  local name = def.name or info.name or tostring(def.id)
  local color = info.color or { 255, 255, 255 }
  local dir = M.DIRS[def.dir] and def.dir or "down"

  local e = create_entity()
  add_transform(e, def.x, def.y, 1, 1, 0)
  add_sprite(e, M.SPRITE_ID, M.SPRITE_W, M.SPRITE_H)
  add_animation_atlas(e, M.SPRITE_ID, "idle_" .. dir)

  local tw, th = measure_text(name, M.FONT)
  local ox, oy = M.label_offset(tw, th, M.SPRITE_W)
  add_text(e, name, M.FONT, color[1], color[2], color[3], 255, ox, oy)
  return e
end

return M
