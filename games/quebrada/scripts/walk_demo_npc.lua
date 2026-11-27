-- NPC del demo de walker: patrulla un rectangulo con input por funcion (derecha 2s,
-- abajo 1s, izquierda 2s, arriba 1s). Mismo walker, sin camara.
-- El timer vive en el closure: cada entidad con este script tiene el suyo.
local t = 0
local legs = {
  { dx = 1, dy = 0, time = 2 },
  { dx = 0, dy = 1, time = 1 },
  { dx = -1, dy = 0, time = 2 },
  { dx = 0, dy = -1, time = 1 },
}
local total = 0
for _, leg in ipairs(legs) do total = total + leg.time end

local function patrol(entity, dt)
  t = (t + dt) % total
  local acc = 0
  for _, leg in ipairs(legs) do
    acc = acc + leg.time
    if t < acc then return leg.dx, leg.dy, false end
  end
  return 0, 0, false
end

local walk_update = require("walker").make_update({
  walk_speed = 40,
  input = patrol,
})

-- La Llorona (issue #63): un emisor sonoro pegado al NPC. Volumen por distancia y
-- paneo segun donde este respecto al jugador (el oyente es player_entity).
-- Tecla 1: "mentira de distancia" ("si se oye lejos, esta cerca"): el volumen usa
-- la distancia invertida, pero el paneo sigue la direccion real.
local MAX_DIST = 220
local voice = nil
local lie = false
local was_down = false
-- Tecla m: alterna el volumen del bus de musica entre 1 y 0.3 (issue #64)
local was_mv = false

update = function()
  local entity = this
  walk_update()

  -- La Llorona va en el bus "voice": mientras suena, la musica y el ambiente bajan (ducking)
  if not voice or not is_playing(voice) then
    voice = play_sound_at("llorona", 0, 0, {
      loop = true, min_dist = 24, max_dist = MAX_DIST, follow = entity, bus = "voice",
    })
  end

  local mv = is_action_activated("music_vol")
  if mv and not was_mv then
    local v = get_bus_volume("music")
    set_bus_volume("music", v > 0.5 and 0.3 or 1.0)
    print("[audio] music bus volume: " .. tostring(get_bus_volume("music")))
  end
  was_mv = mv

  local down = is_action_activated("lie")
  if down and not was_down then
    lie = not lie
    print("[llorona] distance lie: " .. tostring(lie))
  end
  was_down = down

  if lie and player_entity then
    local nx, ny = get_position(entity)
    local px, py = get_position(player_entity)
    local d = math.sqrt((nx - px) ^ 2 + (ny - py) ^ 2)
    set_emitter_distance_override(voice, math.max(0, MAX_DIST - d))
  else
    set_emitter_distance_override(voice, nil)
  end
end
