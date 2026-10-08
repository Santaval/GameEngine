-- Prefab de la nave de otro jugador (ver docs/lua-api.md, seccion Network).
-- Misma nave que el jugador de scene_01 pero sin player.lua: no lee input.
-- Su posicion la corrige el duenio por la red. pos/rot/vel/acc del spawn
-- sobreescriben transform y rigid_body.
return function(state)
  return {
    components = {
      circle_collider = {
        radius = 170,
        width = 430,
        heigth = 650,
      },
      rigid_body = {
        velocity = { x = 0, y = 0 },
      },
      sprite = {
        assetId = "spaceship-idle",
        width = 430,
        height = 650,
        src_rect = { x = 0, y = 0 },
      },
      animation = {
        numFrames = 4,
        frameSpeedRate = 5,
        isLoop = true,
      },
      transform = {
        position = { x = 0, y = 0 },
        scale = { x = 0.2, y = 0.2 },
      },
    },
  }
end
