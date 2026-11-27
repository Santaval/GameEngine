-- Guiones de dialogo como datos (issue #50, #51). Clave = valor de la propiedad `npc` del TMX.
-- Linea: { speaker, text, voice?, choices?, set_flag?, when?, mission_offer? }
-- Opcion: strings o { text, set_flag?, next?, when?, mission_accept?, mission_reject?, call? }
--   when: condicion (function o texto "a,!b"); si es falsa la linea/opcion se salta.
local m = require("missions")

-- Primera vez (o mientras la mision sigue solo ofrecida)
local nueva = m.mission_is("chequelo", "none", "offered")

return {
  mama = {
    { when = nueva, speaker = "Mamá", mission_offer = "chequelo",
      text = "¿Ya vas a salir? Está cayendo la noche y la quebrada no es lugar para andar sola, ni siquiera con linterna.",
      voice = "chequelo_mama_gancho" },
    { when = nueva, speaker = "Mamá",
      text = "Acuérdate de lo que decía tu abuela: después de las ocho no se anda por el monte, mijo." },
    { when = nueva, speaker = "Mamá", text = "¿Vas a ir esta noche?",
      choices = {
        { text = "Sí, voy esta noche", set_flag = "mama.avisada", mission_accept = "chequelo" },
        { text = "Mejor no", mission_reject = "chequelo" },
      } },
    -- Reacciones: se evaluan tras la eleccion y en cada conversacion posterior
    { when = m.mission_is("chequelo", "accepted"), speaker = "Mamá",
      text = "Entonces llévate el abrigo y no tardes. ¡Que Dios te cuide!" },
    { when = m.mission_rejected("chequelo"), speaker = "Mamá",
      text = "Eso es lo mejor. Quédate a cenar, ya casi está." },
    { when = m.mission_is("chequelo", "night_active", "done", "failed"), speaker = "Mamá",
      text = "Ten cuidado, mijo. La noche es larga." },
  },
}
