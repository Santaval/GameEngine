local bullet_lifetime = require("bullet_lifetime")

-- Las balas replicadas (prefabs/bullet.lua) y las locales comparten esta vida.
-- El chunk corre una vez por entidad, asi que cada una tiene su contador.
update = bullet_lifetime.make_update()
