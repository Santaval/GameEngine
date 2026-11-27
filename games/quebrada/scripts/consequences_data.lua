-- Consecuencias de las decisiones como datos (issue #70). Docs: games/quebrada/docs/consequences.md
-- Entrada: { id, who = valor de la propiedad `npc` del TMX, when = condicion, once = bool (por defecto false),
--            lines = { { speaker, text, ... } } }  (cada linea es una linea de dialogo normal)
-- Las entradas que se cumplen se ANTEPONEN al guion base del NPC (dialogues.lua), en este orden.
local m = require("missions")

local manana = m.next_day("chequelo") -- ya paso al menos un dia desde el resultado

return {
  { id = "vecina_rechazada", who = "vecina",
    when = m.all(m.mission_rejected("chequelo"), manana),
    lines = { { speaker = "Vecina", text = "Dicen que anoche no saliste. Hiciste bien: se fue la luz y el monte silbó hasta el amanecer." } } },
  { id = "vecina_aceptada", who = "vecina",
    when = m.all(m.mission_is("chequelo", "accepted", "night_active"), manana),
    lines = { { speaker = "Vecina", text = "Te vi bajar con la linterna anoche. Qué valor, mijo. Aquí todos lo comentan." } } },
  { id = "vecina_hecha", who = "vecina",
    when = m.all(m.mission_done("chequelo"), m.not_(m.mission_done("chequelo", "detour_cafetal")), manana),
    lines = { { speaker = "Vecina", text = "Volviste entero, y eso ya es decir mucho. Los perros no ladraron en toda la madrugada." } } },
  -- Con resultado: en zona1 el trigger house_arrival llama missions.complete("chequelo", "detour_cafetal")
  -- si el jugador paso por el cafetal (scripts/chequelo_triggers.lua, docs/zona1.md)
  { id = "vecina_cafetal", who = "vecina",
    when = m.all(m.mission_done("chequelo", "detour_cafetal"), manana),
    lines = { { speaker = "Vecina", text = "Dicen que te vieron por el cafetal, lejos del camino. ¿Qué buscabas allá?" } } },
  { id = "vecina_fallida", who = "vecina",
    when = m.all(m.mission_failed("chequelo"), manana),
    lines = { { speaker = "Vecina", text = "Tu mamá no durmió esperándote. Mejor ve a verla." } } },
  -- Un NPC con guion base: el comentario sale una sola vez, antes de sus lineas de siempre
  { id = "mama_rechazada_manana", who = "mama", once = true,
    when = m.all(m.mission_rejected("chequelo"), manana),
    lines = { { speaker = "Mamá", text = "Hoy amaneció tranquilo. Bien que te quedaste anoche." } } },
}
