-- Logica pura del ambiente (issue #65): definiciones por zona/hora, crossfade y
-- planificador de one-shots. Sin llamadas al motor; rng se inyecta.
local M = {}

M.FADE_TIME = 3.0     -- segundos del crossfade
M.DEFAULT_TIME = "day"
M.SPAWN_MIN, M.SPAWN_MAX = 120, 300 -- distancia (px) de los one-shots al jugador

local function oneshot(min, max, sounds) return { min = min, max = max, sounds = sounds } end
local function s(id, volume) return { id = id, volume = volume or 0.7 } end

-- SETS[clave][hora] = { loop = id, volume = n, oneshots = {min,max,sounds} | nil }
-- Las claves son las de la propiedad `ambience` de las zonas del TMX.
M.SETS = {
  pueblo = {
    day = { loop = "amb_pueblo_day", volume = 0.5, oneshots = oneshot(20, 50, {
      s("moto_pass_01"), s("moto_pass_02"), s("moto_pass_03"), s("moto_far_01"),
      s("dog_far_01", 0.5), s("dog_far_02", 0.5), s("rooster_far_01", 0.5) }) },
    night = { loop = "amb_pueblo_night", volume = 0.5, oneshots = oneshot(15, 40, {
      s("dog_far_03", 0.5), s("dog_far_04", 0.5), s("dogs_chorus_far_01", 0.5),
      s("dogs_chorus_far_02", 0.5), s("owl_01", 0.5), s("owl_02", 0.5) }) },
  },
  monte = {
    day = { loop = "amb_monte_day", volume = 0.5, oneshots = oneshot(25, 60, {
      s("rooster_far_02", 0.5), s("cow_far_01", 0.5), s("dog_far_01", 0.4) }) },
    night = { loop = "amb_monte_night", volume = 0.5, oneshots = oneshot(20, 50, {
      s("owl_03", 0.5), s("owl_04", 0.5), s("wind_gust", 0.5), s("dogs_chorus_far_03", 0.4) }) },
  },
  quebrada = {
    day = { loop = "amb_quebrada_day", volume = 0.55 },
    night = { loop = "amb_quebrada_night", volume = 0.55, oneshots = oneshot(25, 60, {
      s("owl_01", 0.4), s("dog_far_02", 0.4) }) },
  },
  casa = {
    day = { loop = "amb_casa_day", volume = 0.5 },
    night = { loop = "amb_casa_night", volume = 0.5 },
  },
  -- sin usar aun (sin zona en los mapas actuales)
  cafetal = { day = { loop = "amb_cafetal_day", volume = 0.5 }, night = { loop = "amb_cafetal_night", volume = 0.5 } },
  eolicas = { day = { loop = "amb_eolicas_day", volume = 0.5 }, night = { loop = "amb_eolicas_night", volume = 0.5 } },
}

-- Set para clave+hora; nil si la clave no existe
function M.resolve(key, time)
  local per = key and M.SETS[key]
  return per and (per[time] or per[M.DEFAULT_TIME]) or nil
end

-- Avanza el crossfade. layers = array de { id, level 0..1, vol, handle }.
-- Crea la capa objetivo si falta (level 0), sube la objetivo y baja las demas.
-- Cada capa sube o baja por su cuenta: cambiar de objetivo a mitad no salta.
-- Devuelve las capas retiradas (level 0); el pegamento les hace stop_sound.
function M.step_layers(layers, target_id, target_vol, dt, fade_time)
  local found = false
  for i = 1, #layers do
    if layers[i].id == target_id then found = true end
  end
  if target_id and not found then
    layers[#layers + 1] = { id = target_id, level = 0, vol = target_vol }
  end
  local step = (fade_time > 0) and (dt / fade_time) or 1
  local keep, removed = {}, {}
  for i = 1, #layers do
    local l = layers[i]
    if l.id == target_id then
      l.vol = target_vol
      l.level = math.min(1, l.level + step)
    else
      l.level = math.max(0, l.level - step)
    end
    if l.id ~= target_id and l.level <= 0 then
      removed[#removed + 1] = l
    else
      keep[#keep + 1] = l
    end
  end
  for i = 1, #layers do layers[i] = nil end
  for i = 1, #keep do layers[i] = keep[i] end
  return removed
end

-- Volumen real de una capa: curva equal-power
function M.layer_volume(l)
  return math.sin(l.level * math.pi / 2) * l.vol
end

-- ---- one-shots ----
function M.next_delay(spec, rng) return spec.min + rng() * (spec.max - spec.min) end

-- Elige un sonido sin repetir el anterior (si hay mas de uno)
function M.pick_sound(list, last_id, rng)
  if #list == 1 then return list[1] end
  local pick
  repeat pick = list[math.min(#list, math.floor(rng() * #list) + 1)] until pick.id ~= last_id
  return pick
end

-- Punto aleatorio alrededor de (px, py), a distancia entre SPAWN_MIN y SPAWN_MAX
function M.place(px, py, rng)
  local ang = rng() * 2 * math.pi
  local d = M.SPAWN_MIN + rng() * (M.SPAWN_MAX - M.SPAWN_MIN)
  return px + math.cos(ang) * d, py + math.sin(ang) * d
end

-- st = { timer = nil, last_id = nil }. oneshots puede ser nil (sin one-shots).
-- Devuelve la entrada de sonido que toca disparar ahora, o nil.
function M.oneshot_step(st, dt, oneshots, rng)
  if not oneshots then st.timer = nil; return nil end
  if st.timer == nil then st.timer = M.next_delay(oneshots, rng) end
  st.timer = st.timer - dt
  if st.timer > 0 then return nil end
  st.timer = M.next_delay(oneshots, rng)
  local pick = M.pick_sound(oneshots.sounds, st.last_id, rng)
  st.last_id = pick.id
  return pick
end

return M
