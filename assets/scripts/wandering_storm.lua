-- =====================================================================
--  Script de runtime de cada tormenta errante (prefabs/wandering_storm.lua).
--  Lo corre cada cliente con su copia: todos anotan la tormenta en los
--  globals wandering_storms / wandering_storm_radius (los lee map_storm.lua)
--  y solo el duenio (el host, o el nuevo host tras migrar) mueve el rumbo y
--  la borra al salir del mapa. El dano y el empuje los aplica
--  map_storm_world.lua. Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")

local WS = cfg.WANDERING_STORM
local W = cfg.WORLD_SIZE

-- Margen extra (px) antes de borrarla: nace con el centro a un radio del borde
local DESPAWN_PAD = 300

-- Datos de esta tormenta (spawn_state lo fija el motor mientras arma el prefab)
local state = spawn_state or {}
local radius = state.radius or WS.radius.min

function update()
  local id = get_net_id(this)
  if id ~= nil and wandering_storms ~= nil then
    wandering_storms[id] = true
    if wandering_storm_radius ~= nil then wandering_storm_radius[id] = radius end
  end

  if not is_local(this) then return end

  -- Paseo aleatorio del rumbo conservando la rapidez
  local vx, vy = get_velocity(this)
  local speed = math.sqrt(vx * vx + vy * vy)
  if speed > 0.001 then
    local turn = (math.random() * 2 - 1) * WS.turn_rate * get_delta_time()
    local c, s = math.cos(turn), math.sin(turn)
    set_velocity(this, vx * c - vy * s, vx * s + vy * c)
  end

  -- Fuera del mundo por mas de su radio: se borra (el host repone)
  local x, y = get_position(this)
  if x < -radius - DESPAWN_PAD or y < -radius - DESPAWN_PAD
      or x > W + radius + DESPAWN_PAD or y > W + radius + DESPAWN_PAD then
    net_despawn(this)
  end
end
