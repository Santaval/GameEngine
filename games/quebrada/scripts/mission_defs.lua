-- Definiciones de misiones (issue #51). Los hooks son opcionales; reciben (id, arg).
--   on_offer, on_accept, on_reject, on_start_night, on_complete(id, outcome), on_fail
local ws = require("world_state")

return {
  chequelo = {
    title = "El chequelo",
    -- "Sí, voy esta noche": aceptar solo marca la mision. La noche empieza al llegar a la
    -- puerta de la iglesia (walk_start en zona1, issue #82), que llama a start_night
    on_accept = function()
      ws.set("chequelo.accepted", true)
    end,
    -- La hora es de la historia (issue #66): la mision lleva a la noche y de vuelta al dia
    on_start_night = function() require("time_of_day").set("night", { title = "Esa noche..." }) end,
    on_reject = function() ws.set("chequelo.ending", "stayed_home") end,
    on_complete = function(_, outcome)
      ws.set("chequelo.ending", outcome or "done")
      -- Llegando a casa (regreso.pendiente) el amanecer lo pone chequelo_day tras hablar con mama
      if not ws.has("regreso.pendiente") then
        require("time_of_day").set("day", { title = "Amanece..." })
      end
    end,
    on_fail = function()
      ws.set("chequelo.ending", "failed")
      require("time_of_day").set("day", { title = "Amanece..." })
    end,
  },
  -- Mandado de la manana siguiente (chequelo_day.lua): mama pide papas para la olla de carne.
  -- Aparece en la pestana Misiones de la libreta (ofrecida y aceptada al pedirlas mama)
  papas = {
    title = "Papas para la olla (abastecedor El Jardín)",
  },
  -- Pista de Doña Maria (mandados.lua): preguntar a Lito por que nos dicen "come mono". Su casa se hace despues
  lito = {
    title = "Preguntarle a Lito por qué nos dicen \"come mono\"",
  },
  -- Mama manda a avisarle a papa (esta en el patio) que ya casi esta la comida (mandados.after_mama)
  papa = {
    title = "Avisarle a papá que ya casi está la comida (está en el patio)",
  },
  -- Papa va a apear limones y manda por la escalera (mandados.after_papa)
  escalera = {
    title = "Pedirle prestada la escalera a Tío Enrique",
  },
  -- Nace al oir la historia de Tio Enrique (legends/camisa_blanca.lua): buscar a quien ve en la finca
  camisa_blanca = {
    title = "Buscar al hombre de camisa blanca",
  },
  -- Obligatoria: papa manda a pagarle a Doña Maria las papas (mandados.after_papa_escalera); el pueblo ya de noche
  pagar_maria = {
    title = "Pagarle a Doña María lo de las papas",
  },
  -- Tras pagar a Doña Maria (mandados.after_maria): volver a casa de noche; en la entrada de los Caliles hay que pelear
  -- contra el simio (walkback.lua / simio.lua) y al llegar a casa mama lo recibe (chequelo_day, mama_simio)
  volver_casa = {
    title = "Volver a casa (de noche)",
  },
}
