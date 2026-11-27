-- Iluminacion de Quebrada (issue #48). El ambiente sale de la hora de ambience.lua
-- (dia = blanco, sin costo; noche = casi negro azulado). El estado es del modulo:
-- se recarga con cada escena, igual que las luces del motor (load_scene las borra).
local amb = require("ambience")

local M = {}

local NIGHT = { 20, 26, 51 }
local DAY = { 255, 255, 255 }
local FADE_TIME = 2.0

-- Linterna del jugador (de dia no se nota porque el ambiente es blanco)
local LANTERN = { radius = 70, color = { r = 255, g = 210, b = 150 }, intensity = 0.9, flicker = 0.15 }

local applied = nil
local lantern_for = nil

local function target(t)
  return t == "night" and NIGHT or DAY
end

-- Al cargar la escena: ambiente inmediato (la pantalla llega en negro) y luces del mapa
function M.init(map)
  applied = amb.get_time()
  local c = target(applied)
  set_ambient(c[1], c[2], c[3], 0)
  lantern_for = nil
  if map then lights_from_map(map) end
end

-- Cada frame: transicion suave al cambiar la hora y linterna una sola vez por jugador
function M.tick()
  local t = amb.get_time()
  if t ~= applied then
    local c = target(t)
    set_ambient(c[1], c[2], c[3], FADE_TIME)
    applied = t
  end
  if player_entity and lantern_for ~= player_entity then
    attach_light(player_entity, LANTERN)
    lantern_for = player_entity
  end
end

return M
