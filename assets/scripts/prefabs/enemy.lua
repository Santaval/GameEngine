-- Prefab de un enemigo (ver docs/lua-api.md, seccion Network). Ningun escenario
-- lo usa todavia; para crear uno, solo el host:
--   net_spawn("enemy.lua", { pos = {x = ..., y = ...}, world = true })
-- pos/rot/vel/hp del estado sobreescriben transform, rigid_body y health.
-- state: max_hp (por defecto 50), world.
return function(state)
  state = state or {}
  return {
    components = {
      health = {
        max = state.max_hp or 50,
        invulnerability = 0.2,
      },
      circle_collider = {
        radius = 170,
        width = 430,
        heigth = 650,
      },
      gravity = {
        mass = 10,
        attracts = false,
        affected = true,
      },
      rigid_body = {
        velocity = { x = 0, y = 0 },
        max_speed = 80,
      },
      sprite = {
        assetId = "spaceship-idle",
        width = 430,
        height = 650,
        src_rect = { x = 0, y = 0 },
      },
      transform = {
        position = { x = 0, y = 0 },
        scale = { x = 0.2, y = 0.2 },
      },
      script = {
        path = "./assets/scripts/enemy.lua",
      },
    },
  }
end
