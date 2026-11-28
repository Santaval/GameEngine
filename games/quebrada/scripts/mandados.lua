-- Mandados de la manana siguiente (mision "papas") y la pista de Lito. Pegamento entre dialogos, misiones,
-- logros y guardado; los textos estan en dialogues.lua (maria, mama). Se pide desde las escenas donde se
-- habla con ellas (house_scene, house_abastecedor_scene) para registrar dialogue.on_end.
--   papas:  mama la pide (chequelo_day) -> Doña Maria vende (flag papas.compradas) -> se las llevas a mama
--   lito:   Doña Maria manda a preguntarle a Lito por "come mono" (mision aparte; su casa llega despues)
--   papa:   al recibir las papas mama manda a avisarle a papa (en el patio) que ya casi esta la comida
--   escalera: papa (en el patio) manda a pedirle prestada la escalera a Tio Enrique (la casa de Enrique llega despues)
--   pagar_maria: papa (al recibir la escalera) manda a pagarle a Doña Maria las papas; teletransporta de noche frente al abastecedor; se paga a Doña Maria dentro
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
  if ws.has("maria.pagado") and missions.state("pagar_maria") == "accepted" then
    missions.jump("pagar_maria", "done", "Le pagaste a Doña María")
    save.autosave()
  end
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

-- Papa recibe la escalera y ofrece la historia del mono (opcional: audio resumido en legends/mono.lua). Se cierra la
-- mision `escalera`; despues de la historia (o sin ella) papa manda a pagar a Doña Maria (mision obligatoria
-- `pagar_maria`) y el jugador aparece de noche frente a la puerta del abastecedor (spawn `exit_abastecedor`), donde esta Doña Maria
local want_mono, stage = false, nil

function M.want_mono() want_mono = true end

local function pay_dialogue()
  local started = dialogue.start(dialogue.scripts.papa_pagar, { on_end = M.after_pagar })
  if not started then M.after_pagar() end
end

function M.after_papa_escalera()
  if missions.state("escalera") ~= "accepted" then return end
  missions.jump("escalera", "done", "Le llevaste la escalera a papá")
  if want_mono then
    want_mono = false
    stage = "mono"
    require("story").listen("mono") -- saludo, audio y cierre; tick() sigue cuando acaba
  else
    pay_dialogue()
  end
end

-- Cada frame (day_npcs.tick): esperar el fin de la historia del mono y seguir con el pago
function M.tick()
  if stage == "mono" and not require("story").is_open() and not dialogue.is_open() then
    stage = nil
    pay_dialogue()
  end
end

function M.after_pagar()
  missions.offer("pagar_maria")
  missions.accept("pagar_maria")
  M.go_pay_maria()
end

function M.go_pay_maria()
  local fade = require("fade")
  if player_walker then player_walker.input = function() return 0, 0, false end end
  fade.start_out(function()
    ws.set("noche.pendiente", true) -- el controlador de zona1 lo ve al llegar y pone la noche con su tarjeta
    ws.set_ctx({ arrival = { map = "maps/zona1.tmx", spawn = "exit_abastecedor", facing = "up" } }) -- frente a la puerta del abastecedor
    save.autosave({ map = "maps/zona1.tmx", scene = "scenes/main.lua" })
    load_scene("scenes/main.lua")
  end)
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
