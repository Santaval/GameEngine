-- Leyenda "Los come-monos": lo que cuenta Lito (mision `lito`, mandados.lua). Grabacion: sounds/stories/come-mono.mp3.
-- La charla de entrada (greeting) y la despedida (closing) son cajas de dialogo; el audio suena entre las dos.
-- Al escucharla (on_heard) se cierra la mision de Lito. Campos: games/quebrada/docs/stories.md
return {
  id = "come_monos",
  teller = "lito",                 -- valor de la propiedad `npc`
  teller_name = "Lito",
  sound = "story_come_monos",      -- assetId (declarar en la escena con stream = true)
  kind = "real",
  title = "Los come-monos",
  summary = "Lo que cuenta Lito de por qué a los de Quebrada Grande nos dicen come-monos.",
  heard_at = 0.8,
  repeatable = true,
  on_heard = function()
    local missions = require("missions")
    if missions.state("lito") == "accepted" then
      missions.jump("lito", "done", "Supiste por qué nos dicen come-monos")
    end
    require("save").autosave()
  end,
  greeting = {
    { speaker = "Lito", text = "¿Cómo me le va?" },
    { speaker = "Yo", text = "Bien, Lito, ¿y usted? Vengo a preguntarle, ¿por qué a los de Quebrada Grande nos dicen come-monos?" },
  },
  closing = {
    { speaker = "Yo", text = "Gracias por contármelo, Lito. Ya me voy, que mi mamá me espera." },
    { speaker = "Lito", text = "Vaya con Dios, mijo. Salúdeme a su mamá." },
    { speaker = "Yo", text = "Se lo digo. Hasta luego." },
  },
}
