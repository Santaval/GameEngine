scene = {
  -- Sprites
  sprites = {
    [0] =
    {assetId="spaceship-attack", filePath="./assets/sprites/spaceship/player/attack.png"},
    {assetId="spaceship-idle", filePath="./assets/sprites/spaceship/player/idle.png"},
    {assetId="spaceship-mine", filePath="./assets/sprites/spaceship/player/mine.png"},
  }

  -- Fuentes

  -- Keys
  keys = {
    [0] = 
    {name = "accelerate", key=119},
    {name = "rotate_left", key=97},
    {name = "rotate_right", key=100},
  }

  -- Mouse

  -- Entities
  entities = {
    [0] =
    -- Player
    {
      components = {
        circle_collider =  {
          radius = 8,
          width = 16,
          heigth = 16,
        },
        rigid_body = {
          velocity = { x = 0, y = 0}
        },
        sprite = {
          assetId = "spaceship-idle",
          width = 443.5, 
          height = 530, 
          src_rect = {x = 0, y = 165},
          scale = 0.2,
          rotation = 0,
        },
        transform = {
          position = {x = 400, y = 300},
        },
        script = {
          path = "./assets/scripts/player.lua"
        }
      }
    }
  }

}