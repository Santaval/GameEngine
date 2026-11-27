-- Leyenda "El chequelo" (issue #68). Todo lo que no es la grabacion es texto de la caja
-- de dialogo (issue #50). Campos: ver games/quebrada/docs/stories.md
local m = require("missions")

return {
  id = "chequelo",
  teller = "mama",                 -- valor de la propiedad `npc` del TMX
  teller_name = "Mamá",            -- nombre en el overlay
  sound = "story_chequelo",        -- assetId (declarar en la escena con stream = true)
  kind = "real",                   -- "real" (grabacion) | "generated"
  title = "El chequelo",
  summary = "Lo que cuentan en la quebrada sobre el chequelo y la noche en que se va la luz.",
  heard_at = 0.8,                  -- fraccion para contar como escuchada
  repeatable = false,              -- true: se puede volver a escuchar desde el prompt
  -- Disponible solo despues de la primera charla (asi "Hablar" va primero)
  requires = m.not_(m.mission_is("chequelo", "none")),
  mission_offer = "chequelo",      -- opcional: se ofrece al empezar (idempotente)
  greeting = {
    { speaker = "Mamá", text = "Siéntate, mijo. La grabé para que no se perdiera." },
    { speaker = "Mamá", text = "Escucha con calma. No hay que entenderla toda de una vez." },
  },
  closing = {
    { speaker = "Mamá", text = "Eso es lo que contaban. Ahora ya la sabes." },
  },
  recommendations = {
    { speaker = "Mamá", text = "Si quieres más historias, pregunta a los vecinos de la quebrada." },
  },
  -- Pistas: texto corto (<= 60 caracteres). Todos los campos presentes se cumplen (AND):
  --   map, zone (id de zona), time ("day"|"night"), near = {x,y,r} (px de mundo), when (condicion)
  clues = {
    { id = "luz", time = "night", when = "story.chequelo.started",
      text = "Cuando se va la luz, el chequelo empieza a silbar." },
    { id = "puerta", map = "maps/house_mama.tmx", near = { x = 96, y = 134, r = 16 },
      when = m.mission_accepted("chequelo"),
      text = "La puerta del monte nunca se cierra del todo." },
  },
  next = nil,                      -- reservado (#69): id de la siguiente historia
}
