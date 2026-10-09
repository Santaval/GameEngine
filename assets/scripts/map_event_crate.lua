-- =====================================================================
--  Caja de loot alto de Pal para los eventos del mapa (#25, #26): la crean y
--  la borran la Contraccion de la tormenta y la Senal de Pal.
--  - spawn(p, key) (host): crea la caja centrada en (p.x, p.y) y guarda su netId
--    en p.crate (el director copia params despues de fire, asi que llega a todos).
--  - despawn(ev, key) (host, en on_end): borra la caja si nadie la abrio; vale
--    tambien para el host nuevo tras migrar (el id va en params).
--  key separa la caja sin netId (sin red) de cada tipo de evento.
--  Ver docs/aval-cup.md.
-- =====================================================================

local cfg = require("map_config")

local CRATE = cfg.LOOT_CRATE_PAL

local crate = {}

-- Cajas del host sin netId (sin red): get_net_id da nil y despawn las busca aqui
local local_crates = {}

function crate.spawn(p, key)
  local w = CRATE.size
  local h = w * CRATE.sheet.src_h / CRATE.sheet.frame_w
  local e = net_spawn("loot_crate_pal.lua", { pos = { p.x - w / 2, p.y - h / 2 }, world = true, kind = "pal" })
  if e == nil then return false end
  local id = get_net_id(e)
  if id ~= nil then p.crate = id else local_crates[key] = e end
  return true
end

function crate.despawn(ev, key)
  if not net_is_host() then return end
  local e = nil
  if ev.params ~= nil and ev.params.crate ~= nil then e = find_by_net_id(ev.params.crate)
  else e = local_crates[key] end
  local_crates[key] = nil
  if e ~= nil and is_alive(e) and is_local(e) then net_despawn(e) end
end

return crate
