-- Guardado de la partida (issue #52). Docs: games/quebrada/docs/save.md
-- Pega el estado del juego (world_state, hora del dia, foco, lugar) con el binding del
-- motor save_data/load_data. La logica pura (forma, version, migraciones) esta en
-- save_logic.lua. Este modulo NO debe requerir missions, interaction ni town_controller
-- (missions lo pide perezosamente al terminar una mision).
-- Un fallo al guardar nunca rompe el juego: se registra con "[save]" y se sigue.
local ws = require("world_state")
local logic = require("save_logic")

local SLOT = "slot1"

-- Mapa y escena actuales: los fija el controlador al cargar. Global para sobrevivir
-- a load_scene (los modulos se recargan, los globales no)
save_state = save_state or { map = nil, scene = nil }

local M = {}

-- El controlador lo llama al cargar cada mapa
function M.note_map(map, scene)
  save_state.map = map
  save_state.scene = scene
end

function M.exists()
  return has_save ~= nil and has_save(SLOT) or false
end

-- Guarda ya. opts opcional: map/scene (para guardar justo al cambiar de mapa, antes de
-- que el controlador de la escena nueva lo anote). Devuelve true si se escribio
function M.save(opts)
  opts = opts or {}
  local map = opts.map or save_state.map
  local scene = opts.scene or save_state.scene
  if not save_data then return false end
  if not map or not scene then
    print("[save] aun no se sabe en que mapa estas: no se guarda")
    return false
  end
  local tod = rawget(_G, "time_state")
  local foco = rawget(_G, "foco_state")
  local data = logic.build({
    flags = ws.snapshot(),
    phase = tod and tod.phase or "day",
    battery = foco and foco.battery or nil,
    map = map,
    scene = scene,
    ctx = ws.ctx(),
  })
  local ok, res = pcall(save_data, SLOT, data)
  if not ok or not res then
    print("[save] no se pudo guardar: " .. tostring(ok and "error de escritura" or res))
    return false
  end
  print("[save] guardado (" .. map .. ")")
  return true
end

-- Guardado automatico: igual que save() pero nunca lanza
function M.autosave(opts)
  local ok, res = pcall(M.save, opts)
  if not ok then
    print("[save] autosave fallo: " .. tostring(res))
    return false
  end
  return res
end

-- Carga la partida y deja el juego listo para abrir la escena guardada. Devuelve la
-- ruta de la escena a cargar con load_scene, o nil y el motivo
function M.load()
  if not load_data then return nil, "el motor no tiene load_data" end
  local data = load_data(SLOT)
  if not data then return nil, "no hay partida guardada" end
  local migrated, err = logic.migrate(data)
  if not migrated then return nil, err end
  local p, perr = logic.parts(migrated)
  if not p then return nil, perr end

  ws.restore(p.flags)
  ws.set_ctx(p.ctx)
  -- time_of_day.init y foco.init releen estos globales al cargar la escena
  time_state = time_state or { phase = "day" }
  time_state.phase = p.phase
  time_state.card = nil
  foco_state = foco_state or { on = false, battery = p.battery }
  foco_state.on = false
  foco_state.battery = p.battery
  M.note_map(p.map, p.scene)
  print("[save] partida cargada (" .. p.map .. ")")
  return p.scene
end

return M
