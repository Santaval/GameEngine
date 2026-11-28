-- Logica pura del minijuego "Quieto cuando silba" (apagon de la noche del chequelo). Sin motor.
-- Cada cierto tiempo suena un silbido: tras un margen de reaccion (grace) el jugador debe estar
-- quieto y con el foco apagado hasta que acabe. Un descuido cuenta un golpe; con max_strikes pierde.
local M = {}

M.CONFIG = {
  first_delay = 5,     -- s tras el apagon hasta el primer silbido
  interval_min = 6,    -- s entre silbidos (al azar en el rango)
  interval_max = 20,
  quick_chance = 0.3,  -- probabilidad de un silbido seguido del anterior
  quick_min = 2.5,     -- s de ese silbido seguido
  quick_max = 4.5,
  grace = 0.8,         -- s para reaccionar desde que empieza a sonar
  min_duration = 3.5,  -- s minimos de la ventana (el audio puede durar mas)
  max_strikes = 3,
  move_speed = 8,      -- px/s sobre los que el jugador cuenta como en movimiento
}

function M.new(cfg)
  return { phase = "idle", t = 0, next = (cfg or M.CONFIG).first_delay, violated = false,
           duration = 0, strikes = 0 }
end

-- Ventana de un silbido: la del audio (+1 s de cola) y nunca menos de min_duration
function M.window(cfg, audio_len)
  return math.max(cfg.min_duration, (audio_len or 0) + 1)
end

-- inp = { moving, light_on, duration (s de la ventana si empieza ahora) }; rnd() en 0..1
-- Devuelve un evento: "start" | "strike" | "fail" | "pass" | nil
function M.step(st, cfg, dt, inp, rnd)
  st.t = st.t + dt
  if st.phase == "idle" then
    if st.t >= st.next then
      st.phase, st.t, st.violated, st.duration = "whistle", 0, false, inp.duration or cfg.min_duration
      return "start"
    end
    return nil
  end
  local ev = nil
  if not st.violated and st.t >= cfg.grace and (inp.moving or inp.light_on) then
    st.violated = true
    st.strikes = st.strikes + 1
    ev = (st.strikes >= cfg.max_strikes) and "fail" or "strike"
  end
  if st.t >= st.duration then
    st.phase, st.t = "idle", 0
    rnd = rnd or math.random
    if rnd() < cfg.quick_chance then
      st.next = cfg.quick_min + rnd() * (cfg.quick_max - cfg.quick_min)
    else
      st.next = cfg.interval_min + rnd() * (cfg.interval_max - cfg.interval_min)
    end
    if not ev and not st.violated then ev = "pass" end
  end
  return ev
end

-- Fraccion de la ventana que queda (1 al empezar, 0 al acabar)
function M.left(st)
  if st.phase ~= "whistle" or st.duration <= 0 then return 0 end
  return math.max(0, 1 - st.t / st.duration)
end

function M.in_grace(st, cfg) return st.phase == "whistle" and st.t < cfg.grace end

return M
