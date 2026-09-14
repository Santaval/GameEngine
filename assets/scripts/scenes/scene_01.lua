scene = {
  -- Sprites
  sprites = {
    [0] =
    {assetId="spaceship-attack", filePath="./assets/sprites/spaceship/player/attack.png"},
    {assetId="spaceship-idle", filePath="./assets/sprites/spaceship/player/idle.png"},
    {assetId="spaceship-mine", filePath="./assets/sprites/spaceship/player/mine.png"},
    {assetId="spaceship-movement", filePath="./assets/sprites/spaceship/player/movement.png"},
    {assetId="bullet", filePath="./assets/sprites/bullets/bullets.png"},
  },

  -- Fuentes

  -- Keys
  keys = {
    [0] = 
    {name = "accelerate", key=119},
    {name = "brake", key=115},
    {name = "rotate_left", key=97},
    {name = "rotate_right", key=100},
    {name = "shoot", key=102},
  },

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
          width = 430, 
          height = 650,  
          src_rect = {x = 0, y = 0},
          rotation = 0,
        },
        animation = {
          numFrames = 4,
          frameSpeedRate = 5,
          isLoop=true
        },
        transform = {
          position = {x = 400, y = 100},
          scale = { x = 0.2, y = 0.2}
        },
        script = {
          path = "./assets/scripts/player.lua"
        }
      },
    },
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
          width = 430, 
          height = 650,  
          src_rect = {x = 0, y = 0},
          rotation = 0,
        },
        animation = {
          numFrames = 4,
          frameSpeedRate = 5,
          isLoop=true
        },
        transform = {
          position = {x = 500, y = 300},
          scale = { x = 0.2, y = 0.2}
        },
        script = {
          path = "./assets/scripts/enemy.lua"
        }
      },
    },
  },

}