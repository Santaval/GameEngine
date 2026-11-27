-- Libreta minima (issue #68): almacen persistente de pistas sobre world_state.
-- Aun no hay UI; el overlay F3 muestra los flags. Docs: games/quebrada/docs/stories.md
--   libreta.clue.<id>      true mientras la pista esta en la libreta
--   libreta.clue_n.<id>    numero de orden (se conserva si el flag se apaga y se reactiva)
--   libreta.clue_id.<n>    id de la pista n-esima
--   libreta.clue_text.<id> texto
--   libreta.clue_src.<id>  id de la historia de origen (opcional)
--   libreta.clue_count     cuantas pistas se han registrado
-- Pistas de boca en boca (#69, ver docs/leads.md), una por leyenda:
--   libreta.lead.<id>, libreta.lead_n.<id>, libreta.lead_id.<n>, libreta.lead_text.<id>,
--   libreta.lead_person.<id>, libreta.lead_src.<id>, libreta.lead_count
local ws = require("world_state")

local M = {}

-- Aviso suave de "Nuevo" (issue #80): suena al anotarse una entrada nueva. Silencioso si la
-- escena no declara el sonido o no hay motor (pruebas)
M.NEW_SOUND = "sfx_libreta_new"
function M.notify()
  if play_sound then pcall(play_sound, M.NEW_SOUND, { bus = "sfx", volume = 0.4 }) end
end

function M.has_clue(id) return ws.has("libreta.clue." .. id) end
function M.clue_count() return ws.get("libreta.clue_count", 0) end

-- Registra la pista. Devuelve true si es nueva (false si ya estaba)
function M.add_clue(id, text, source)
  if M.has_clue(id) then return false end
  local n = ws.get("libreta.clue_n." .. id)
  if type(n) ~= "number" then
    n = ws.add("libreta.clue_count", 1)
    ws.set("libreta.clue_n." .. id, n)
    ws.set("libreta.clue_id." .. n, id)
  end
  ws.set("libreta.clue_text." .. id, text or "")
  if source then ws.set("libreta.clue_src." .. id, source) end
  ws.set("libreta.clue." .. id, true)
  M.notify()
  return true
end

-- Lista ordenada: { { n, id, text, source }, ... } (solo las pistas activas)
function M.clues()
  local out = {}
  for n = 1, M.clue_count() do
    local id = ws.get("libreta.clue_id." .. n)
    if id and M.has_clue(id) then
      out[#out + 1] = { n = n, id = id, text = ws.get("libreta.clue_text." .. id, ""),
                        source = ws.get("libreta.clue_src." .. id) }
    end
  end
  return out
end

-- ---- pistas de boca en boca (issue #69): una por leyenda ----
function M.has_lead(id) return ws.has("libreta.lead." .. id) end
function M.lead_count() return ws.get("libreta.lead_count", 0) end

-- Devuelve true si es nueva
function M.add_lead(id, text, person, source)
  if M.has_lead(id) then return false end
  local n = ws.get("libreta.lead_n." .. id)
  if type(n) ~= "number" then
    n = ws.add("libreta.lead_count", 1)
    ws.set("libreta.lead_n." .. id, n)
    ws.set("libreta.lead_id." .. n, id)
  end
  ws.set("libreta.lead_text." .. id, text or "")
  if person then ws.set("libreta.lead_person." .. id, person) end
  if source then ws.set("libreta.lead_src." .. id, source) end
  ws.set("libreta.lead." .. id, true)
  M.notify()
  return true
end

-- { { n, id, text, person, source }, ... } (solo las activas)
function M.leads()
  local out = {}
  for n = 1, M.lead_count() do
    local id = ws.get("libreta.lead_id." .. n)
    if id and M.has_lead(id) then
      out[#out + 1] = { n = n, id = id, text = ws.get("libreta.lead_text." .. id, ""),
                        person = ws.get("libreta.lead_person." .. id),
                        source = ws.get("libreta.lead_src." .. id) }
    end
  end
  return out
end

return M
