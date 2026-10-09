-- Prefab de un portal inestable (ver docs/aval-cup.md, seccion Portals).
-- Entidad invisible: sin sprite, collider, vida ni gravedad. La posicion del
-- transform es el CENTRO del portal; el dibujo y la entrada los hace
-- map_portal_world.lua. pos/life del estado de spawn: la vida viaja en el
-- estado (unstable_portal.lua la lee de spawn_state).
-- state: life, world
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
        path = "./assets/scripts/unstable_portal.lua",
      },
    },
  }
end
