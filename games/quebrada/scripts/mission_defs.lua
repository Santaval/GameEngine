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
      require("time_of_day").set("day", { title = "Amanece..." })
    end,
    on_fail = function()
      ws.set("chequelo.ending", "failed")
      require("time_of_day").set("day", { title = "Amanece..." })
    end,
  },
}
