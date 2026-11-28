-- Leyenda "El hombre de camisa blanca": la cuenta Tio Enrique al ir por la escalera (mision `escalera`).
-- Grabacion: sounds/stories/camisa-blanca.mp3 (solo la primera parte, 1:58; el audio completo esta en camisa-blanca-completo.mp3). Al oirla (on_heard) nace la mision "Buscar al hombre de camisa blanca".
-- Campos: games/quebrada/docs/stories.md
return {
  id = "camisa_blanca",
  teller = "enrique",
  teller_name = "Tío Enrique",
  sound = "story_camisa_blanca",   -- assetId (declarar en la escena con stream = true)
  kind = "real",
  title = "El hombre de camisa blanca",
  summary = "Lo que le pasó a Tío Enrique en la finca San Luis: un hombre de camisa blanca y sombrero le puso el gamarrón a la yegua y no se supo por dónde llegó.",
  heard_at = 0.8,
  repeatable = true,
  on_heard = function()
    local missions = require("missions")
    missions.offer("camisa_blanca")
    missions.accept("camisa_blanca")
    require("save").autosave()
  end,
  greeting = {
    { speaker = "Yo", text = "Buenas, tío Enrique. Mi papá manda a pedirle prestada la escalera, que va a apear unos limones." },
    { speaker = "Tío Enrique", text = "Ahí está, sobrino, llévesela, está recostada en el aguacate. Pero siéntese un ratito, que le voy a contar algo que me pasó en finca San Luis." },
  },
  closing = {
    { speaker = "Yo", text = "Qué susto, tío. ¿Y quién será ese hombre de la camisa blanca?" },
    { speaker = "Tío Enrique", text = "Quién sabe, sobrino. Dicen que todavía anda por esos potreros. Llévele cuidado." },
    { speaker = "Yo", text = "Gracias por la escalera. Hasta luego." },
  },
}
