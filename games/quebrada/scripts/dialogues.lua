-- Guiones de dialogo como datos (issue #50). Clave = valor de la propiedad `npc` del TMX.
-- Linea: { speaker, text, voice?, choices?, set_flag? }
--   voice: id de sonido (bus "voice"); por ahora solo se reproduce, no gobierna el tiempo.
--   choices: strings o { text, set_flag?, next? } ; `next` es un guion que se intercala tras elegir.
return {
  mama = {
    { speaker = "Mamá",
      text = "¿Ya vas a salir? Está cayendo la noche y la quebrada no es lugar para andar sola, ni siquiera con linterna.",
      voice = "chequelo_mama_gancho" },
    { speaker = "Mamá",
      text = "Acuérdate de lo que decía tu abuela: después de las ocho no se anda por el monte, mijo." },
    { speaker = "Mamá", text = "¿Vas a ir esta noche?",
      choices = {
        { text = "Sí, voy esta noche", set_flag = "mama.avisada",
          next = { { speaker = "Mamá", text = "Entonces llévate el abrigo y no tardes. ¡Que Dios te cuide!" } } },
        { text = "Mejor no",
          next = { { speaker = "Mamá", text = "Eso es lo mejor. Quédate a cenar, ya casi está." } } },
      } },
  },
}
