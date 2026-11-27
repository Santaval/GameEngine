-- Iluminacion de Quebrada (issue #48). El ambiente y las luces del mapa los maneja
-- time_of_day.lua (issue #66); aqui solo queda la linterna del jugador. El estado es
-- del modulo: se recarga con cada escena, igual que las luces del motor (load_scene las borra).
local M = {}

-- Linterna del jugador (de dia no se nota porque el ambiente es blanco)
local LANTERN = { radius = 70, color = { r = 255, g = 210, b = 150 }, intensity = 0.9, flicker = 0.15 }

local lantern_for = nil

-- Al cargar la escena
function M.init()
  lantern_for = nil
end

-- Cada frame: linterna una sola vez por jugador
function M.tick()
  if player_entity and lantern_for ~= player_entity then
    attach_light(player_entity, LANTERN)
    lantern_for = player_entity
  end
end

return M
