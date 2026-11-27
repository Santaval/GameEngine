-- Emisores de sonido del mapa con filtro de hora y condicion (issue #78). El motor ya tiene
-- emitters_from_map, pero no entiende `only` ni `when`: aqui cada objeto class="emitter" se
-- reproduce con play_sound_at solo mientras su `only` (time_of_day) y su `when` (flags, como
-- las puertas) se cumplen. Propiedades: sound, loop (por defecto true), interval (s; un disparo
-- cada tanto en vez de bucle), volume, min_distance, max_distance / radius, bus, only, when.
--   emitters.init(map)   en la carga del mapa (load_scene ya detuvo los sonidos anteriores)
--   emitters.tick(dt)    cada frame
local ws = require("world_state")
local tod = require("time_of_day")
local door_logic = require("door_logic")
local logic = require("triggers_logic")

local M = {}

local list = {}

local function truthy(v, default)
  if v == nil or v == "" then return default end
  return v == true or v == "true"
end

function M.init(map)
  list = {}
  for _, o in ipairs((map and map.objects) or {}) do
    local p = o.properties or {}
    if o.type == "emitter" and type(p.sound) == "string" and p.sound ~= "" then
      local x, y = o.x, o.y
      if o.rect then x, y = o.rect.x + o.rect.w / 2, o.rect.y + o.rect.h / 2 end
      local interval = tonumber(p.interval)
      list[#list + 1] = {
        name = o.name, props = p, x = x or 0, y = y or 0,
        interval = (interval and interval > 0) and interval or nil,
        loop = truthy(p.loop, true), timer = 0, handle = nil,
      }
    end
  end
end

local function active(e)
  local p = e.props
  if type(p.only) == "string" and p.only ~= "" and not tod.visible(p.only) then return false end
  if type(p.when) == "string" and p.when ~= "" and not door_logic.eval_condition(p.when, ws.has) then return false end
  return true
end

local function opts(e)
  local p = e.props
  return {
    volume = tonumber(p.volume) or 1,
    loop = (e.interval == nil) and e.loop or false,
    min_dist = tonumber(p.min_distance) or 64,
    max_dist = tonumber(p.max_distance) or tonumber(p.radius) or 400,
    bus = (type(p.bus) == "string" and p.bus ~= "") and p.bus or "sfx",
  }
end

function M.tick(dt)
  for _, e in ipairs(list) do
    if e.handle and not is_playing(e.handle) then e.handle = nil end -- voz muerta (fin o load_scene)
    if active(e) then
      if e.interval then
        local fired
        e.timer, fired = logic.interval_step(e.timer, dt, e.interval)
        if fired then play_sound_at(e.props.sound, e.x, e.y, opts(e)) end
      elseif not e.handle then
        local h = play_sound_at(e.props.sound, e.x, e.y, opts(e))
        if h and h ~= 0 then e.handle = h end
      end
    else
      e.timer = 0
      if e.handle then
        stop_sound(e.handle, 500)
        e.handle = nil
      end
    end
  end
end

return M
