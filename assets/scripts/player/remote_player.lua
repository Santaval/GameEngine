-- Script runtime de la nave de otro jugador (ver prefabs/player/remote_player.lua).
-- No lee input: el movimiento viene de la fisica local y de las correcciones
-- de "state" (NetSyncSystem). Aqui solo se dibuja: llama, nombre y barra de vida.

-- spawn_state lo fija el motor mientras construye el prefab. Los locals del
-- chunk son por entidad porque el SceneLoader corre este archivo por cada una
local state = spawn_state or {}
local name = state.name
local max_hp = state.max_hp or 100

local SHIP_WIDTH = 430 * 0.2
local BAR_HEIGHT = 5
local BAR_GAP = 8

-- player.lua guarda aqui los player_stats que llegan, por netId
local function apply_stats(entity)
  local stats = remote_player_stats and remote_player_stats[get_net_id(entity)]
  if not stats then return end

  if stats.max_hp then max_hp = stats.max_hp end
  if stats.max_speed then set_max_speed(entity, stats.max_speed) end
  -- Se consume: no reaplicar cada frame
  remote_player_stats[get_net_id(entity)] = nil
end

function update()
  -- Los enemigos buscan a la nave mas cercana entre la local y estas
  -- (ver enemy.lua); se anota cada frame y ellos podan las que mueran
  player_ships = player_ships or {}
  local id = get_net_id(this)
  if id ~= nil then player_ships[id] = true end

  -- "this" aun no es esta entidad al cargar el chunk, por eso el nombre se
  -- resuelve aqui
  if not name then
    name = get_owner(this) or "?"
  end

  apply_stats(this)

  -- Misma regla que player_movement.read_thrust_input, pero con la
  -- aceleracion replicada en vez del input
  local _, accel_y = get_acceleration(this)
  if accel_y < 0 then
    set_sprite(this, "spaceship-movement")
  else
    set_sprite(this, "spaceship-idle")
  end

  local px, py = get_position(this)
  local hp = get_health(this)
  local ratio = math.max(0, math.min(1, hp / max_hp))
  local bar_y = py - BAR_GAP - BAR_HEIGHT

  draw_rect_world(px, bar_y, SHIP_WIDTH, BAR_HEIGHT, 60, 60, 60, 200, true)
  draw_rect_world(px, bar_y, SHIP_WIDTH * ratio, BAR_HEIGHT, 60, 200, 80, 255, true)
  draw_text_world(px, bar_y - 16, name, "default", 255, 255, 255)
end
