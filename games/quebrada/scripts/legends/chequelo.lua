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
  -- Final alcanzado (libreta, issue #80): flag con el valor y texto de cada valor
  ending_flag = "chequelo.ending",
  endings = { stayed_home = "Te quedaste en casa", failed = "Saliste mal parado", done = "Fuiste al monte" },
  greeting = {
    { speaker = "Mamá", text = "Siéntate, mijo. La grabé para que no se perdiera." },
    { speaker = "Mamá", text = "Escucha con calma. No hay que entenderla toda de una vez." },
  },
  closing = {
    { speaker = "Mamá", text = "Eso es lo que contaban. Ahora ya la sabes." },
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
  -- Boca en boca (#69): ver games/quebrada/docs/leads.md. Primera regla cuyo `when` se cumple.
  next = {
    { when = m.mission_rejected("chequelo"), person = "chayo",
      line = "Mejor quédate. Mañana pasa donde Ña Chayo, ella vio irse la luz.",
      unlocks = { "house.chayo" } },
    { person = "chayo",
      line = "Ña Chayo vio algo raro anoche. Pásale a preguntar antes de bajar.",
      unlocks = { "house.chayo" } },
  },
}
