-- Guiones de dialogo como datos (issue #50, #51). Clave = valor de la propiedad `npc` del TMX.
-- Linea: { speaker, text, voice?, choices?, set_flag?, when?, mission_offer? }
-- Opcion: strings o { text, set_flag?, next?, when?, mission_accept?, mission_reject?, call? }
--   when: condicion (function o texto "a,!b"); si es falsa la linea/opcion se salta.
local m = require("missions")

-- Primera vez (o mientras la mision sigue solo ofrecida)
local nueva = m.mission_is("chequelo", "none", "offered")

return {
  -- Saludo al entrar de dia (chequelo_day.maybe_greet, issue #82): una sola vez
  mama_saludo = {
    { speaker = "Mamá", text = "Ah, llegaste, mijo. Pasá, que afuera está todo cerrado." },
    { speaker = "Mamá", text = "Hoy solo mi casa está abierta. Sentate, descansá." },
    { speaker = "Mamá",
      text = "Si querés, escuchá la historia de la quebrada. La grabé para que no se perdiera.",
      set_flag = "mama.saludada" },
  },
  -- Oferta de mama (issue #82). Las `call` van en funciones: este modulo se carga antes que chequelo_day
  mama = {
    { when = nueva, speaker = "Mamá", mission_offer = "chequelo",
      text = "Mirá, mijo. Ya sabés lo que se cuenta del chequelo." },
    { when = nueva, speaker = "Mamá",
      text = "Esta noche se va la luz, como cada año. ¿Vas a ir a la iglesia después de la misa?",
      choices = {
        { text = "Sí, voy esta noche", set_flag = "mama.avisada", mission_accept = "chequelo",
          call = function() require("chequelo_day").go_to_church() end },
        { text = "Mejor no", mission_reject = "chequelo",
          call = function() require("chequelo_day").on_reject() end },
      } },
    -- Reacciones: se evaluan tras la eleccion y en cada conversacion posterior
    { when = m.mission_is("chequelo", "accepted"), speaker = "Mamá",
      text = "Llevate el abrigo y no tardés. ¡Que Dios te cuide!" },
    { when = m.mission_rejected("chequelo"), speaker = "Mamá",
      text = "Está bien, mijo. Quedate a cenar. Mañana pasá por la casa de Ña Chayo; ella vio irse la luz." },
    { when = m.mission_is("chequelo", "night_active", "done", "failed"), speaker = "Mamá",
      text = "Cuidate, mijo. La noche es larga." },
  },
  -- Casa de Abuela Paula y Abuelo Pepe (maps/house_paula.tmx)
  abuela_paula = {
    { when = m.mission_is("chequelo", "night_active"), speaker = "Abuela Paula",
      text = "Después de las ocho no se anda por el monte, mijo. Lléveselo bien tapado y no le conteste a nadie que lo llame." },
    { speaker = "Abuela Paula", text = "Siéntese un ratito, mijo, que ya está el café. Lo colé hace nada." },
    { speaker = "Abuela Paula", text = "Estoy tejiendo la cobija nueva para su mamá. Le faltan dos cuadros todavía." },
  },
  abuelo_pepe = {
    { speaker = "Abuelo Pepe", text = "Ya no se oye el monte como antes. Cuando yo era chiquillo, de aquí se oían hasta los monos." },
    { speaker = "Abuelo Pepe", text = "El cafetal de la esquina lo sembró mi papá, y yo le acarreaba el abono en carreta. Qué tiempos." },
  },
}
