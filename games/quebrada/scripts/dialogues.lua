-- Guiones de dialogo como datos (issue #50, #51). Clave = valor de la propiedad `npc` del TMX.
-- Linea: { speaker, text, voice?, choices?, set_flag?, when?, mission_offer? }
-- Opcion: strings o { text, set_flag?, next?, when?, mission_accept?, mission_reject?, call? }
--   when: condicion (function o texto "a,!b"); si es falsa la linea/opcion se salta.
local m = require("missions")

return {
  -- Inicio de la partida (chequelo_day.on_start): al nacer en la casa
  mama_alistate = {
    { speaker = "Mamá", text = "Mijo, ya alístate que tienes que ir a misa." },
  },
  -- Al ir a la puerta (chequelo_day.on_door): aviso de la luz y decision de oir la historia
  mama_luz = {
    { speaker = "Mamá", text = "Esperate, mijo. Esta noche se va la luz, como cada año." },
    { speaker = "Mamá", text = "Cuando se vaya, no sigás la luz que veás por el monte. Nunca la sigás." },
    { speaker = "Mamá", text = "¿Querés escuchar la historia del chequelo antes de irte?",
      choices = {
        { text = "Sí, quiero escucharla", call = function() require("chequelo_day").want_story() end },
        { text = "Ahora no" },
      } },
  },
  -- Sin pregunta: la mision se acepta sola al terminar (chequelo_day)
  mama_bendicion = {
    { speaker = "Mamá", text = "Que Dios te bendiga, mijo. Andá con cuidado y no tardés." },
  },
  -- Despues de aceptada (mama ya no ofrece nada)
  mama = {
    { when = m.mission_is("chequelo", "accepted"), speaker = "Mamá",
      text = "Andá a la iglesia, mijo. Llevate el abrigo y que Dios te cuide." },
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
