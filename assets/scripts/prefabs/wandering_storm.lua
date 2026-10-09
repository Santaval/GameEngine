-- Prefab de una tormenta errante (ver docs/aval-cup.md, seccion Wandering
-- Storms). Entidad invisible: sin sprite, collider, vida ni gravedad, asi que
-- no choca ni duerme. La posicion del transform es el CENTRO de la nube.
-- pos/vel del estado de spawn sobreescriben transform y rigid_body; el radio
-- viaja en el estado (wandering_storm.lua lo lee de spawn_state), asi que un
-- cliente que entra tarde via snapshot la reconstruye igual.
-- state: radius, world
return function(state)
  state = state or {}
  return {
    components = {
      transform = {
        position = { x = 0, y = 0 },
        scale = { x = 1, y = 1 },
        rotation = 0,
      },
      rigid_body = {
        velocity = { x = 0, y = 0 },
      },
      script = {
        path = "./assets/scripts/wandering_storm.lua",
      },
    },
  }
end
