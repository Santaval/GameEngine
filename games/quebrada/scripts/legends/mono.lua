-- Leyenda "El simio de los Caliles": la cuenta papa en el patio (flujo en mandados.lua / day_npcs.lua).
-- Grabacion: sounds/stories/mono.mp3 (version resumida, 2:12; el audio completo esta en mono-completo.mp3).
-- Campos: games/quebrada/docs/stories.md
return {
  id = "mono",
  teller = "papa",
  teller_name = "Papá",
  sound = "story_mono",            -- assetId (declarar en la escena con stream = true)
  kind = "real",
  title = "El simio de los Caliles",
  summary = "Lo que le pasó a papá una noche de Semana Santa de 2012 volviendo a pie a casa: en la entrada de los Caliles se topó con una figura alta que caminaba en cuatro patas y de pie. Era un simio.",
  heard_at = 0.8,
  repeatable = true,
  greeting = {
    { speaker = "Papá", text = "Siéntese, mijo. Esto me pasó a mí hace años, una noche de Semana Santa." },
  },
  closing = {
    { speaker = "Papá", text = "Hasta el día de hoy no sé qué fue eso. Por eso le digo, mijo: acá de noche pasan cosas raras." },
    { speaker = "Yo", text = "Qué miedo, pa." },
  },
}
