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
  -- Abastecedor El Jardin (maps/house_abastecedor.tmx): la compra de las papas y la pregunta por "come mono".
  -- papas.compradas lo pone mandados.after_maria al terminar (si no, las lineas de despues saldrian en la misma charla)
  maria = {
    { when = m.all(m.mission_is("papas", "accepted"), m.not_flag("papas.compradas")), speaker = "Doña María",
      text = "¡Buenas, mijo! ¿Qué se le ofrece?" },
    { when = m.all(m.mission_is("papas", "accepted"), m.not_flag("papas.compradas")), speaker = "Yo",
      text = "Buenas, Doña María. Mi mamá manda a pedirle unas papas para la olla de carne del almuerzo." },
    { when = m.all(m.mission_is("papas", "accepted"), m.not_flag("papas.compradas")), speaker = "Doña María",
      text = "Ay, qué rico, olla de carne. Mire, justo me llegaron frescas. ¿Le pongo dos kilos?" },
    { when = m.all(m.mission_is("papas", "accepted"), m.not_flag("papas.compradas")), speaker = "Yo", text = "Sí, por favor." },
    { when = m.all(m.mission_is("papas", "accepted"), m.not_flag("papas.compradas")), speaker = "Doña María",
      text = "Aquí tiene, mijo. Dígale a su mamá que me las pasa a pagar luego.", set_flag = "maria.vendio" },
    { when = m.all(m.mission_is("papas", "accepted"), m.not_flag("papas.compradas")), speaker = "Yo",
      text = "Doña María, ¿sabe por qué nos dicen come mono?" },
    { when = m.all(m.mission_is("papas", "accepted"), m.not_flag("papas.compradas")), speaker = "Doña María",
      text = "¡JAJA! No tengo ni idea. El que puede saber es Lito, vaya búsquelo a la casa y le pregunta.",
      set_flag = "lito.pista" },
    { when = m.all(m.mission_is("papas", "accepted"), m.not_flag("papas.compradas")), speaker = "",
      text = "(Tengo las papas. Mamá espera, pero la curiosidad... ¿voy donde Lito o vuelvo a casa?)" },
    -- De noche, a pagar las papas (mision pagar_maria; mandados.after_maria la cierra al terminar)
    { when = m.mission_is("pagar_maria", "accepted"), speaker = "Yo",
      text = "Buenas noches, Doña María. Disculpe la hora, vengo a pagarle lo de las papas." },
    { when = m.mission_is("pagar_maria", "accepted"), speaker = "Doña María",
      text = "Ay, mijo, a esta hora y con la noche como está. No era para tanto, pero se lo agradezco. Son tres mil colones." },
    { when = m.mission_is("pagar_maria", "accepted"), speaker = "Yo", text = "Aquí tiene.", set_flag = "maria.pagado" },
    { when = m.mission_is("pagar_maria", "accepted"), speaker = "Doña María",
      text = "Gracias, mijo. Váyase con cuidado y dígale a su papá que aquí tiene su cuenta al día." },
    { when = m.all(m.mission_is("papas", "accepted"), m.flag("papas.compradas")), speaker = "Doña María",
      text = "¿Todavía por aquí, mijo? Si busca a Lito, vaya a su casa. Y no se tarde, que su mamá espera las papas." },
    { when = m.all(m.not_(m.mission_is("papas", "accepted")), m.not_(m.mission_is("pagar_maria", "accepted"))),
      speaker = "Doña María", text = "¡Buenas, mijo! Mire lo que necesite." },
  },
  -- Papa en el patio (day_npcs.lua): salta solo al acercarse con la mision `papa`; mandados.after_papa abre la de la escalera
  papa_patio = {
    { speaker = "Yo", text = "Pa, ya va a estar la comida." },
    { speaker = "Papá", text = "Mmmm ya casi voy, que tengo que apear unos limones. ¿Por qué no vas donde tu tío Enrique y le pedís prestada la escalera?" },
  },
  -- Vuelve con la escalera (day_npcs.lua): salta solo; mandados.after_papa_escalera cierra la mision y abre la de pagar
  papa_mono = {
    { speaker = "Yo", text = "Pa, aquí está la escalera." },
    { speaker = "Papá", text = "Gracias, mijo. Ahora sí puedo apear esos limones." },
    { speaker = "Yo", text = "Pa', vieras lo que me contó el tío... la historia del hombre de camisa blanca." },
    { speaker = "Papá", text = "Ah sí, acá a veces pasan cosas raras, como cuando me encontré un mono. ¿La querés escuchar?",
      choices = {
        { text = "Sí, cuéntemela", call = function() require("mandados").want_mono() end },
        { text = "Ahora no, pa" },
      } },
  },
  -- Despues de la historia del mono (o si no la quiso oir): la excusa para mandarlo al pueblo de noche
  papa_pagar = {
    { speaker = "Papá", text = "Antes de que se me olvide, mijo: ándese a pagarle a Doña María lo de las papas, que quedamos debiendo." },
    { speaker = "Papá", text = "Vaya ahora, que se hace tarde. Y ojo: el pueblo de noche no es el mismo." },
  },
  -- Hablarle de nuevo
  papa = {
    { when = m.mission_is("escalera", "accepted"), speaker = "Papá",
      text = "¿Ya fuiste donde tu tío Enrique por la escalera? Los limones no se apean solos." },
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
    -- Entrega de las papas (al entrar a la casa con las papas: mandados.on_enter_home; cierra el mandado y abre el aviso a papa)
    { when = m.all(m.mission_is("papas", "accepted"), m.flag("papas.compradas"), m.not_flag("lito.visitado")),
      speaker = "Mamá", text = "¡Las papas! Gracias, mijo. Ya mismo las echo a la olla de carne." },
    { when = m.all(m.mission_is("papas", "accepted"), m.flag("papas.compradas"), m.flag("lito.visitado")),
      speaker = "Mamá", text = "¿¡Hasta ahora llegás con las papas!? Son las tantas y el almuerzo se arruinó por andar de vago." },
    { when = m.all(m.mission_is("papas", "accepted"), m.flag("papas.compradas"), m.flag("lito.visitado")),
      speaker = "Mamá", text = "¡Estás castigado, mijo! Hoy no sales más... bueno, solo una cosa más." },
    { when = m.all(m.mission_is("papas", "accepted"), m.flag("papas.compradas")),
      speaker = "Mamá", text = "Andá a decirle a tu papá, que está en el patio, que ya casi va a estar la comida." },
    { when = m.all(m.mission_is("papas", "accepted"), m.not_flag("papas.compradas")), speaker = "Mamá",
      text = "¿Ya fuiste a El Jardín por las papas, mijo? La olla de carne no espera." },
    { when = m.mission_is("papa", "accepted"), speaker = "Mamá",
      text = "¿Ya le avisaste a tu papá? Está en el patio. Que ya casi está la comida." },
    { when = m.all(m.mission_is("papas", "done"), m.mission_is("papa", "none")), speaker = "Mamá",
      text = "Ya está la olla de carne en el fogón. Gracias por las papas, mijo." },
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
