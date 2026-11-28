-- Luz companera de la noche del chequelo (issue #81): camina por el camino delante del jugador.
-- La logica pura (ruta, estados, deriva) vive en companion_logic.lua. El estado es global
-- (companion_state) y se reinicia en cada init(); las entidades, luces y sonidos del motor se
-- borran en cada carga de escena, asi que los handles se recrean al vuelo en tick().
local logic = require("companion_logic")
local ws = require("world_state")
local missions = require("missions")

local CFG = logic.CONFIG

companion_state = companion_state or logic.new()

local M = {}

local path, detours = nil, nil
local ent, light_id, snd = nil, nil, nil
local last_anim = nil
local born = false -- true el frame en que se crea la entidad (no se llama set_position)

local function release()
  if snd then stop_sound(snd, 400) end
  if light_id then remove_light(light_id) end
  if ent then destroy_entity(ent) end
  ent, light_id, snd, last_anim = nil, nil, nil, nil
end

-- Al cargar la escena: los handles viejos ya no existen. `enabled` = el mapa lleva la luz
function M.init(map, enabled)
  ent, light_id, snd, last_anim, born = nil, nil, nil, nil, false
  path, detours = nil, nil
  companion_state = logic.new()
  if enabled and map then
    path = logic.route_from_objects(map.objects, "route")
    if path then detours = logic.detours_from_objects(path, map.objects) end
  end
end

function M.tick(dt)
  if not path or not player_entity then return end
  local st = companion_state
  local px, py = get_position(player_entity)
  logic.step(st, path, detours, CFG, dt, {
    px = px + 8, py = py + 12, -- centro de los pies (la caja del sprite es 16x16)
    light_appears = ws.has("chequelo.light_appears"),
    off_road = ws.has("chequelo.off_road"),
    arrived = ws.has("chequelo.arrived"),
    night_active = missions.state("chequelo") == "night_active",
  })

  local v = logic.visual(st, path, CFG)
  if v.anim == nil then
    if ent or light_id then release() end
    return
  end

  born = false
  if not ent then
    ent = create_entity()
    add_transform(ent, v.x - 16, v.y - 16, 1, 1, 0)
    add_sprite(ent, "vfx_luz", 32, 32)
    add_animation_atlas(ent, "vfx_luz", v.anim, false)
    set_sprite_layer(ent, "above")
    last_anim = v.anim
    born = true
  end
  if not light_id then
    local c = CFG.light_rgb
    light_id = add_light(v.x, v.y, v.radius, c[1], c[2], c[3], 0)
  end
  if not snd and CFG.sound_id then
    snd = play_sound_at(CFG.sound_id, v.x, v.y, {
      loop = true, volume = CFG.sound_volume, min_dist = CFG.sound_min, max_dist = CFG.sound_max, follow = ent,
    })
  end

  if not born then set_position(ent, v.x - 16, v.y - 16) end
  set_light(light_id, { x = v.x, y = v.y, radius = v.radius, intensity = v.intensity, flicker = v.flicker })
  if v.anim ~= last_anim then
    play_animation(ent, v.anim, v.anim == "idle")
    last_anim = v.anim
  end
end

-- Depuracion: estado, s de la luz y s del jugador
function M.debug()
  local st = companion_state
  return st.state, st.s, st.player_s
end

return M
