-- Sonidos del apagon de la noche del chequelo. Las luces y ventanas las apaga time_of_day.blackout()
-- (mission.chequelo.night_active); aqui suena: el corte de la luz al empezar, un bucle de viento
-- con silbido de fondo y caballos que se oyen cerca del camino.
-- tick(dt) lo llama el controlador (cfg.on_tick). Docs: games/quebrada/docs/blackout.md
local tod = require("time_of_day")

local M = {}

-- Silbidos del minijuego (silbido.lua)
M.WHISTLES = { "whistle_01", "whistle_02", "whistle_03" }
M.HORSES = { "horse_neigh_far_01", "horse_neigh_far_02", "horse_neigh_far_03",
             "horse_snort_01", "horse_snort_02", "horse_hooves_far_01" }
M.HORSE_EVERY = { 9, 20 }    -- s entre sonidos de caballo
M.DIST = { 180, 340 }        -- px del jugador a la fuente

local was = nil       -- apagon el frame anterior (nil = aun no se sabe: no suena el corte al cargar)
local loop = nil
local t_horse = nil

local function rnd(lo, hi) return lo + math.random() * (hi - lo) end

local function seed_once()
  if not audio_rng_seeded then math.randomseed(random_seed()); audio_rng_seeded = true end
end

-- Un sonido posicional a una distancia y angulo al azar alrededor del jugador
function M.around(id, volume)
  if not player_entity then return end
  local px, py = get_position(player_entity)
  local a, d = rnd(0, 2 * math.pi), rnd(M.DIST[1], M.DIST[2])
  pcall(play_sound_at, id, px + 12 + math.cos(a) * d, py + 19 + math.sin(a) * d,
    { volume = volume, min_dist = 96, max_dist = 520, bus = "ambience" })
end

local function stop_all()
  if loop then pcall(stop_sound, loop, 1500); loop = nil end
  t_horse = nil
end

function M.tick(dt)
  local dark = tod.blackout()
  if dark ~= was then
    if dark and was == false then pcall(play_sound, "power_cut", { volume = 0.9, bus = "sfx" }) end
    if not dark then stop_all() end
    was = dark
  end
  if not dark or tod.is_busy() then return end
  seed_once()
  if loop and not is_playing(loop) then loop = nil end
  if not loop then
    local ok, h = pcall(play_sound, "blackout_loop", { loop = true, volume = 0.45, bus = "ambience" })
    if ok and h and h ~= 0 then loop = h end
  end
  t_horse = (t_horse or rnd(6, 12)) - dt
  if t_horse <= 0 then
    M.around(M.HORSES[math.random(#M.HORSES)], 0.7)
    t_horse = rnd(M.HORSE_EVERY[1], M.HORSE_EVERY[2])
  end
end

return M
