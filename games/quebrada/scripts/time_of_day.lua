-- Hora del dia dirigida por la historia (issue #66). Docs: docs/time-of-day.md
-- Fases: day, dusk, night, dawn. No hay reloj: la cambian las misiones (set), la cama
-- (sleep) o la tecla N de depuracion (toggle).
-- El estado es GLOBAL (los modulos se recargan en cada escena, los globales no).
-- Este modulo NO debe requerir missions, interaction ni town_controller (ciclos);
-- consequences se pide perezosamente.
local logic = require("time_of_day_logic")
local amb = require("ambience")
local ws = require("world_state")

local FONT = "default"
local CHAR_W = 6          -- ancho aproximado de la fuente a tamano 10
local CARD_HOLD = 1.6     -- segundos de la tarjeta a plena opacidad
local TRANSITION_TIME = 4.0   -- segundos que tarda el color ambiente en llegar a la fase nueva
local LIGHT_FADE = 1.5    -- segundos que tardan en encender o apagar las luces del mapa

time_state = time_state or { phase = "day", card = nil }
local st = time_state

local M = {}

-- Aviso opcional al pasar de noche a dia: on_day(numero_de_dia). Lo conecta el controlador
M.on_day = nil

-- Apagon de la noche del chequelo: con la mision en night_active se apagan todas las luces del
-- pueblo (casas, postes) y las ventanas (roofs.lua lo consulta)
function M.blackout() return ws.has("mission.chequelo.night_active") and true or false end

-- Luces del mapa: se vuelven a crear en cada escena (load_scene las borra)
local lights = {}

function M.get() return st.phase end
function M.base() return logic.base(st.phase) end

-- true mientras cambia la fase o se ve la tarjeta de titulo
function M.is_busy()
  return st.card ~= nil
end

-- Acepta la tabla `properties` de un objeto de Tiled o directamente el texto de `only`
function M.visible(props_or_only)
  local only = props_or_only
  if type(props_or_only) == "table" then only = props_or_only.only end
  return logic.visible(only, st.phase)
end

local function sync_flags()
  for name, value in pairs(logic.flags(st.phase)) do ws.set(name, value) end
end

local function refresh_lights(seconds)
  for _, l in ipairs(lights) do
    local target = (logic.visible(l.only, st.phase) and not M.blackout()) and l.intensity or 0
    if seconds > 0 then fade_light(l.id, target, seconds)
    else set_light(l.id, { intensity = target }) end
  end
end

-- Aplica una fase: ambiente (set_ambient con transicion), hora gruesa, flags y luces
local function apply_phase(phase, seconds, advance_day)
  local prev = st.phase
  st.phase = phase
  local r, g, b = logic.color(phase)
  set_ambient(r, g, b, seconds)
  amb.set_time(logic.base(phase))
  sync_flags()
  refresh_lights(seconds > 0 and LIGHT_FADE or 0)
  -- Amanecer = dia nuevo (issue #70)
  if phase == "day" and (prev == "night" or prev == "dawn") and advance_day ~= false then
    local d = require("consequences").advance_day()
    if M.on_day then M.on_day(d) end
  end
end

-- Cambia a `phase` de inmediato: la fase, los flags, las luces y la hora gruesa (ambiente
-- sonoro y objetos con `only`) cambian ya, y el color ambiente se funde en TRANSITION_TIME
-- (pasando por tonos intermedios) tapado por la tarjeta de titulo.
-- opts: title (tarjeta de texto), instant (sin transicion), advance_day = false
-- (no sumar dia al llegar a day desde la noche)
function M.set(phase, opts)
  opts = opts or {}
  if not logic.valid(phase) then
    print("[time_of_day] fase desconocida: " .. tostring(phase))
    return false
  end
  if phase == st.phase then return true end
  if opts.title and not opts.instant then
    st.card = { t = 0, total = logic.CARD_FADE * 2 + CARD_HOLD, text = opts.title }
    st.busy_t = 0
  end
  apply_phase(phase, opts.instant and 0 or TRANSITION_TIME, opts.advance_day)
  return true
end

-- Tecla N: del dia a la noche y de la noche al dia
function M.toggle()
  if logic.base(st.phase) == "day" then
    M.set("night", { title = "Esa noche..." })
  else
    M.set("day", { title = "Amanece..." })
  end
end

-- La cama: solo de noche. Devuelve true si se durmio
function M.sleep()
  if M.is_busy() or logic.base(st.phase) ~= "night" then return false end
  M.set("day", { title = "Amanece..." })
  return true
end

-- Al cargar la escena: reaplica la fase actual de inmediato (la pantalla llega en negro)
-- y crea las luces del mapa (objetos `light`: radius, r, g, b, intensity, flicker, only)
function M.init(map)
  st.dark = M.blackout()
  lights = {}  -- las luces del motor ya se borraron con la escena anterior
  st.card = nil
  local r, g, b = logic.color(st.phase)
  set_ambient(r, g, b, 0)
  amb.set_time(logic.base(st.phase))
  sync_flags()
  for _, o in ipairs((map and map.objects) or {}) do
    if o.type == "light" then
      local p = o.properties or {}
      local radius = tonumber(p.radius) or 0
      if radius > 0 then
        local x, y = o.x or 0, o.y or 0
        if o.rect then
          x = o.rect.x + (o.rect.w or 0) / 2
          y = o.rect.y + (o.rect.h or 0) / 2
        end
        local intensity = tonumber(p.intensity) or 1
        local visible = logic.visible(p.only, st.phase) and not M.blackout()
        local id = add_light(x, y, radius, tonumber(p.r) or 255, tonumber(p.g) or 255,
          tonumber(p.b) or 255, visible and intensity or 0)
        if id > 0 then
          local flicker = tonumber(p.flicker)
          if flicker and flicker > 0 then set_light(id, { flicker = flicker }) end
          lights[#lights + 1] = { id = id, intensity = intensity, only = p.only }
        end
      end
    end
  end
end

function M.tick(dt)
  -- Se va la luz (o vuelve): las luces del mapa se funden
  local dark = M.blackout()
  if dark ~= st.dark then
    st.dark = dark
    refresh_lights(dark and 2.5 or LIGHT_FADE)
  end
  if not st.card then return end
  st.card.t = st.card.t + dt
  -- Seguro: la tarjeta dura ~3 s; pasados 8 s algo fallo y se libera
  if st.card.t >= st.card.total or st.card.t > 8 then st.card = nil end
end

-- Tarjeta de titulo: pantalla negra con texto centrado. Llamar el ultimo del frame
function M.draw()
  local card = st.card
  if not card then return end
  local a = logic.card_alpha(card.t, card.total)
  if a <= 0 then return end
  local w, h = get_screen_size()
  draw_rect(0, 0, w, h, 0, 0, 0, math.floor(255 * a + 0.5), true)
  local len = (utf8 and utf8.len(card.text)) or #card.text
  draw_text(math.floor((w - len * CHAR_W) / 2), math.floor(h / 2) - 5, card.text, FONT,
    255, 255, 255, math.floor(255 * a + 0.5))
end

return M
