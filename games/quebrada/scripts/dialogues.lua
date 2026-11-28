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
    { speaker = "Mamá", text = "Y si oís un silbido, quedate quieto y apagá el foco hasta que pase. No te muevas." },
    { speaker = "Mamá", text = "¿Querés escuchar la historia del chequelo antes de irte?",
      choices = {
        { text = "Sí, quiero escucharla", call = function() require("chequelo_day").want_story() end },
        { text = "Ahora no" },
      } },
  },
  -- Tres silbidos mal: te encontro (chequelo_day.on_caught)
  chequelo_fallo = {
    { speaker = "", text = "El silbido te encontró. La luz se apagó para siempre y el monte se cerró a tu alrededor...",
      choices = {
        { text = "Volver a la iglesia e intentarlo de nuevo", call = function() require("chequelo_day").restart_night() end },
        { text = "Rendirme", call = function() require("missions").fail("chequelo") end },
      } },
  },
  -- Al llegar a casa tras la noche (chequelo_day.go_home): mama lo recibe
  mama_regreso = {
    { speaker = "Mamá", text = "¿La viste, verdad? ¿O por qué esa cara?",
      choices = {
        { text = "Sí, la vi", next = {
          { speaker = "Mamá", text = "Ay, mijo... ya lo sabía yo. No se lo contés a cualquiera. Andá, acostate." } } },
        { text = "No vi nada, mamá", next = {
          { speaker = "Mamá", text = "Mm. Esa cara dice otra cosa. Andá, acostate, mijo." } } },
      } },
  },
  -- A la manana siguiente (chequelo_day): el mandado
  mama_papas = {
    { speaker = "Mamá", text = "Buenos días, mijo. ¿Dormiste algo?" },
    { speaker = "Mamá", text = "Hoy hago olla de carne para el almuerzo y me faltan las papas." },
    { speaker = "Mamá", text = "Andá al abastecedor El Jardín y traeme unas papas, ¿sí? Apurate, que la olla no espera." },
  },
  -- Camino al abastecedor (day_npcs.lua): salta solo al acercarse; la segunda linea es un pensamiento
  come_mono = {
    { speaker = "Vecino", text = "¡Hey, come monooooo!" },
    { speaker = "", text = "(¿Come mono? Nunca entendí por qué nos dicen así...)" },
  },
  -- Sin el foco no sale (chequelo_day.on_door)
  mama_foco = {
    { speaker = "Mamá", text = "¿Y el foco, mijo? No vas a salir a oscuras. Tomalo de la repisa." },
    { speaker = "Mamá", text = "Se elige con su número y se prende con X. Pero gasta batería: apagalo cuando no lo necesités." },
  },
  -- Sin pregunta: la mision se acepta sola al terminar (chequelo_day)
  mama_bendicion = {
    { speaker = "Mamá", text = "Que Dios te bendiga, mijo. Andá con cuidado y no tardés." },
  },
  -- Vecinos del camino que apuran al jugador antes de que aparezca la luz (night_npcs.lua)
  vecino_prisa_1 = {
    { speaker = "Ño Lencho", text = "¡Mijo, apurate! Ya casi se va la luz y el monte no perdona." },
    { speaker = "Ño Lencho", text = "Seguí derecho por la calle hasta la casa de tu mamá y no te pares a hablar con nadie." },
  },
  vecino_prisa_2 = {
    { speaker = "Ña Tina", text = "Ay, mijo, ¿todavía andás por aquí? Se va a ir la luz de un momento a otro." },
    { speaker = "Ña Tina", text = "Apurate, que cuando se apague todo no vas a ver ni la mano." },
  },
  -- Despues de aceptada (mama ya no ofrece nada)
  mama = {
    { when = m.mission_is("papas", "accepted"), speaker = "Mamá",
      text = "¿Ya fuiste a El Jardín por las papas, mijo? La olla de carne no espera." },
    { when = m.mission_is("chequelo", "accepted"), speaker = "Mamá",
      text = "Andá a la iglesia, mijo. Llevate el abrigo y que Dios te cuide." },
    { when = m.mission_is("chequelo", "night_active", "failed"), speaker = "Mamá",
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
