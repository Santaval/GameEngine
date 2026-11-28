-- Mandados de la manana siguiente (mision "papas") y la pista de Lito. Pegamento entre dialogos, misiones,
-- logros y guardado; los textos estan en dialogues.lua (maria, mama). Se pide desde las escenas donde se
-- habla con ellas (house_scene, house_abastecedor_scene) para registrar dialogue.on_end.
--   papas:  mama la pide (chequelo_day) -> Doña Maria vende (flag papas.compradas) -> se las llevas a mama
--   lito:   Doña Maria manda a preguntarle a Lito por "come mono" (mision aparte; su casa llega despues)
--   papa:   al recibir las papas mama manda a avisarle a papa (en el patio) que ya casi esta la comida
--   escalera: papa (en el patio) manda a pedirle prestada la escalera a Tio Enrique (la casa de Enrique llega despues)
--   Llegar tarde: si antes de entregar las papas se visito a Lito (flag lito.visitado, lo pondra su casa),
--   mama regana y se gana el logro "Castigados".
local ws = require("world_state")
local missions = require("missions")
local save = require("save")
local libreta = require("libreta")
local dialogue = require("dialogue")

local M = {}

-- Da un logro (idempotente) y avisa a la libreta
function M.logro(id)
  if ws.has("logro." .. id) then return end
  ws.set("logro." .. id, true)
  libreta.notify()
end

-- Fin de la conversacion con Doña Maria: si le pregunto por "come mono", nace la mision de Lito
function M.after_maria()
  if ws.has("maria.vendio") and missions.state("papas") == "accepted" then ws.set("papas.compradas", true) end
  if ws.has("lito.pista") then
    missions.offer("lito")
    missions.accept("lito")
    save.autosave()
  end
end

-- Fin de la entrega (al entrar a casa o al hablar con mama): si trae las papas, se cierra el mandado (a tiempo o tarde)
function M.after_mama()
  if missions.state("papas") ~= "accepted" or not ws.has("papas.compradas") then return end
  local late = ws.has("lito.visitado")
  if late then M.logro("castigados") end
  missions.jump("papas", "done", late and "Llegaste tarde: castigado" or "Entregadas a tiempo")
  -- Mama manda a avisarle a papa, que esta en el patio (mision aparte; el patio llega despues)
  missions.offer("papa")
  missions.accept("papa")
  save.autosave()
end

-- Fin del aviso a papa (patio): se cierra la mision `papa` y papa manda por la escalera de Tio Enrique
function M.after_papa()
  if missions.state("papa") ~= "accepted" then return end
  missions.jump("papa", "done", "Le avisaste a papá")
  missions.offer("escalera")
  missions.accept("escalera")
  save.autosave()
end

-- Al entrar a la casa de mama con las papas: la entrega es automatica (no hace falta hablarle).
-- Reusa el guion `mama` (solo casan las lineas de la entrega) y cierra el mandado al terminar
function M.on_enter_home()
  if missions.state("papas") ~= "accepted" or not ws.has("papas.compradas") then return end
  if dialogue.is_open() then return end
  dialogue.start(dialogue.scripts.mama, { on_end = M.after_mama })
end

dialogue.on_end.maria = M.after_maria
dialogue.on_end.mama = M.after_mama

return M
