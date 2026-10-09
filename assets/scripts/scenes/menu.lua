-- Menu principal: una sola entidad con script, sin sprites
scene = {
  sprites = {},

  fonts = {
    [0] =
    {fontId="default", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=16},
    {fontId="debug-big", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=28},
    {fontId="title", filePath="./assets/fonts/DejaVuSansMono.ttf", fontSize=56},
  },

  keys = {
    [0] =
    {name = "confirm", key = 13},
    {name = "quit", key = 113},
    {name = "multiplayer", key = 109},
    {name = "back", key = 8},
  },

  entities = {
    [0] =
    {
      components = {
        script = {
          path = "./assets/scripts/menu.lua"
        }
      },
    },
  },
}
