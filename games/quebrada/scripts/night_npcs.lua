-- Vecinos que apuran al jugador en la primera mitad del camino de la noche del chequelo (antes de
-- que aparezca la luz): estan al borde de la ruta mientras mission.chequelo.night_active y todavia
-- no hay chequelo.light_appears; al aparecer la luz se meten a sus casas (se destruyen).
-- Se ubican por distancia sobre la ruta (objetos `route` del TMX), a un lado del camino.
-- tick(dt, idx, map) lo llama el controlador (cfg.on_tick). Docs: games/quebrada/docs/zona1.md
local ws = require("world_state")
local missions = require("missions")
local interaction = require("interaction")
local dialogue = require("dialogue")
local npc = require("npc_placeholder")
local clogic = require("companion_logic")

local M = {}

-- s = px de ruta desde la iglesia, side = +1 / -1 (normal de la ruta), script = clave en dialogues.lua
M.LIST = {
  { id = "lencho", s = 420, side = 1, offset = 44, script = "vecino_prisa_1" },
  { id = "tina", s = 1400, side = -1, offset = 44, script = "vecino_prisa_2" },
}

local path = nil
local spawned = nil -- { { entity, item } }

local function should_exist()
  return missions.state("chequelo") == "night_active"
      and not ws.has("chequelo.light_appears") and not ws.has("chequelo.arrived")
end

local function despawn()
  for _, n in ipairs(spawned or {}) do
    interaction.unregister(n.item)
    pcall(destroy_entity, n.entity)
  end
  spawned = nil
end

local function spawn()
  spawned = {}
  for _, d in ipairs(M.LIST) do
    local x, y, nx, ny = clogic.point_at(path, d.s)
    local ox, oy = x + nx * d.side * d.offset, y + ny * d.side * d.offset
    -- mira hacia el camino
    local dir
    if math.abs(nx) > math.abs(ny) then dir = (nx * d.side > 0) and "left" or "right"
    else dir = (ny * d.side > 0) and "up" or "down" end
    -- (x, y) = pies: la esquina del sprite 24x38 queda 12 a la izquierda y 34 arriba
    local e = npc.spawn({ id = d.id, x = ox - 12, y = oy - 34, dir = dir })
    local item = interaction.register({
      entity = e, size = { npc.SPRITE_W, npc.SPRITE_H }, radius = 40, label = "Hablar",
      target = (npc.ROSTER[d.id] or {}).name,
      on_interact = function() dialogue.start(dialogue.scripts[d.script]) end,
    })
    spawned[#spawned + 1] = { entity = e, item = item }
  end
end

-- Al cargar la escena: las entidades viejas ya no existen (load_scene las destruyo)
function M.init(map)
  spawned = nil
  path = map and clogic.route_from_objects(map.objects, "route") or nil
end

function M.tick(dt, idx, map)
  if not path then
    if map and not M.tried then M.tried = true; M.init(map) end
    if not path then return end
  end
  local want = should_exist()
  if want and not spawned then spawn()
  elseif not want and spawned then despawn() end
end

return M
