-- Definiciones de misiones (issue #51). Los hooks son opcionales; reciben (id, arg).
--   on_offer, on_accept, on_reject, on_start_night, on_complete(id, outcome), on_fail
local ws = require("world_state")

return {
  chequelo = {
    title = "El chequelo",
    on_accept = function() ws.set("chequelo.accepted", true) end,
    on_reject = function() ws.set("chequelo.ending", "stayed_home") end,
    on_complete = function(_, outcome) ws.set("chequelo.ending", outcome or "done") end,
    on_fail = function() ws.set("chequelo.ending", "failed") end,
  },
}
