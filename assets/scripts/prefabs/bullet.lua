-- Prefab de una bala (ver docs/lua-api.md, seccion Network). Mismos
-- componentes que la bala de player_shooting.lua. pos/rot/vel del spawn
-- sobreescriben transform y rigid_body.
return {
  components = {
    transform = {
      position = { x = 0, y = 0 },
      scale = { x = 0.5, y = 0.5 },
    },
    rigid_body = {
      velocity = { x = 0, y = 0 },
    },
    gravity = {
      mass = 1,
      attracts = false,
      affected = true,
    },
    sprite = {
      assetId = "bullet",
      width = 64,
      height = 32,
      src_rect = { x = 0, y = 192 },
    },
    animation = {
      numFrames = 8,
      frameSpeedRate = 5,
      isLoop = true,
    },
    circle_collider = {
      radius = 30,
      width = 64,
      heigth = 32,
    },
    damage = {
      amount = 20,
      destroy_on_hit = true,
    },
    script = {
      path = "./assets/scripts/bullet.lua",
    },
  },
}
