-- Prefab de la nave de otro jugador (ver docs/lua-api.md, seccion Network).
-- Misma nave que el jugador de scene_01 pero sin player.lua: su script es
-- player/remote_player.lua, que no lee input. Su posicion la corrige el duenio
-- por la red. pos/rot/vel/acc del spawn sobreescriben transform y rigid_body.
-- state: name, hp, max_hp, max_speed y niveles (engine, gun, shield).
return function(state)
  state = state or {}
  return {
    components = {
      -- Sin esto la nave remota seria indestructible para las balas locales.
      -- Solo su dueño le resta vida; aqui se refleja lo que el dueño informa
      health = {
        max = state.max_hp or 100,
        player = true,
      },
      circle_collider = {
        radius = 170,
        width = 430,
        heigth = 650,
      },
      rigid_body = {
        velocity = { x = 0, y = 0 },
        max_speed = state.max_speed,
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
      script = {
        path = "./assets/scripts/player/remote_player.lua",
      },
    },
  }
end
