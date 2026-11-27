-- Leyenda "La cuenta de Ña Chayo" (issue #69): nodo de demostracion SIN grabacion (no hay `sound`).
-- Se resuelve al entrar por primera vez a su casa.
return {
  id = "chayo",
  teller = "chayo",
  teller_name = "Ña Chayo",
  kind = "real",
  title = "La cuenta de Ña Chayo",
  summary = "Lo que vio Ña Chayo la noche que se fue la luz.",
  resolve_when = "lead.seen.house.chayo",
  final = true, -- ultimo nodo de la demo: no apunta a otra persona
  next = {
    { line = "Ña Chayo: Si quiere más, baje a la quebrada. Pero de día, mijo.",
      unlocks = { "zone.quebrada" } },
  },
}
